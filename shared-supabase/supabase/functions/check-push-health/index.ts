/**
 * Edge Function: check-push-health
 * Project: shared
 * Description: Evaluates push notification health against a small set of
 *              alert rules, manages the notification_alerts table (insert
 *              on first trigger, refresh on re-trigger, clear when the
 *              condition stops holding), and sends an email on transition
 *              edges (fired and cleared). Designed to be invoked on a cron
 *              schedule (every 5 minutes). Also callable manually for
 *              testing — POST with no body is fine.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendAlertEmail } from '../_shared/send-alert-email.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Until we read recipients dynamically from users(is_admin=true), keep this
// list inline. Easy to change later.
const ALERT_RECIPIENTS = ['dave@saturdayvinyl.com']

// Rule thresholds — collected at the top so they're easy to tune.
const FAILURE_RATE_MIN_ATTEMPTS = 20      // ignore noise from low-volume types
const FAILURE_RATE_THRESHOLD = 0.5         // 50% failure rate fires the alert
const SILENT_FAILURE_BASELINE_PER_HOUR = 5 // type must average >5/hr over 7d to count
const SILENT_FAILURE_QUIET_HOURS = 2       // …and have 0 sends in this window
const EVAL_WINDOW = '1 hour'                // window for failure_rate_high + server_wide_auth_error

type Severity = 'info' | 'warning' | 'critical'

interface FiringAlert {
  ruleId: string
  notificationType: string | null
  severity: Severity
  subject: string
  textBody: string
  payload: Record<string, unknown>
}

interface ExistingAlert {
  id: string
  rule_id: string
  notification_type: string | null
  fired_at: string
  email_sent_at: string | null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false },
    })

    const firing = await evaluateRules(supabase)
    const { fired, cleared, refreshed } = await reconcileAlerts(supabase, firing)

    return new Response(
      JSON.stringify({
        evaluated_at: new Date().toISOString(),
        firing_count: firing.length,
        newly_fired: fired,
        cleared: cleared,
        refreshed: refreshed,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    console.error('check-push-health failed:', err)
    return new Response(
      JSON.stringify({ error: (err as Error).message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      },
    )
  }
})

/**
 * Evaluate all rules and return the set of currently-firing alerts.
 */
async function evaluateRules(supabase: SupabaseClient): Promise<FiringAlert[]> {
  const firing: FiringAlert[] = []

  // Rule 1: failure_rate_high
  // Per notification_type, in the last hour: >= FAILURE_RATE_MIN_ATTEMPTS
  // attempts and failure rate > FAILURE_RATE_THRESHOLD.
  const windowStart = new Date(Date.now() - 60 * 60 * 1000).toISOString()
  const { data: rows, error: rowsErr } = await supabase
    .from('notification_delivery_log')
    .select('notification_type, status')
    .gte('created_at', windowStart)
    .returns<Array<{ notification_type: string; status: string }>>()

  if (rowsErr) throw new Error(`Rule eval failed: ${rowsErr.message}`)

  // Aggregate in memory — volume is small (last hour, all rows are short).
  const stats = new Map<string, { sent: number; failed: number }>()
  for (const r of rows ?? []) {
    const s = stats.get(r.notification_type) ?? { sent: 0, failed: 0 }
    if (r.status === 'sent') s.sent++
    else if (r.status === 'failed') s.failed++
    stats.set(r.notification_type, s)
  }

  for (const [notificationType, { sent, failed }] of stats) {
    const total = sent + failed
    if (total < FAILURE_RATE_MIN_ATTEMPTS) continue
    const failureRate = failed / total
    if (failureRate <= FAILURE_RATE_THRESHOLD) continue

    firing.push({
      ruleId: 'failure_rate_high',
      notificationType,
      severity: failureRate >= 0.8 ? 'critical' : 'warning',
      subject: `[Push Alert] ${notificationType}: ${Math.round(failureRate * 100)}% failure rate`,
      textBody:
        `Push notification type "${notificationType}" is failing.\n\n` +
        `Last ${EVAL_WINDOW}: ${total} attempts, ${failed} failed ` +
        `(${Math.round(failureRate * 100)}% failure rate).\n\n` +
        `Investigate: ${dashboardUrl()}\n\n` +
        `Playbook: shared-docs/playbooks/push_notification_firefighting.md`,
      payload: { sent, failed, total, failureRate },
    })
  }

  // Rule 2: server_wide_auth_error
  // Any failure in the last hour with a server-wide error category.
  // These never appear in healthy state — even one occurrence warrants attention.
  const { data: errorPatterns, error: epErr } = await supabase
    .from('admin_push_error_patterns')
    .select('notification_type, error_category, n, last_seen, affected_users')
    .gte('last_seen', windowStart)
    .in('error_category', ['apns_env_mismatch', 'fcm_auth_error', 'unauthenticated'])

  if (epErr) {
    // View might not exist yet on a non-migrated DB — log but don't fail.
    console.warn('admin_push_error_patterns query failed:', epErr.message)
  }

  for (const ep of (errorPatterns ?? [])) {
    firing.push({
      ruleId: 'server_wide_auth_error',
      notificationType: ep.notification_type,
      severity: 'critical',
      subject: `[Push Alert CRITICAL] Server-wide auth error: ${ep.error_category}`,
      textBody:
        `Push pipeline reporting server-wide credential failures.\n\n` +
        `Type: ${ep.notification_type}\n` +
        `Category: ${ep.error_category}\n` +
        `Count last ${EVAL_WINDOW}: ${ep.n}\n` +
        `Affected users: ${ep.affected_users}\n\n` +
        `This is NOT a per-token failure. Likely causes:\n` +
        `  - APNs Auth Key in Firebase Console is scoped wrong or missing\n` +
        `  - Firebase service account credentials are stale\n` +
        `  - FCM API has been disabled at GCP\n\n` +
        `Runbook: shared-docs/playbooks/push_notification_firefighting.md\n` +
        `Dashboard: ${dashboardUrl()}`,
      payload: {
        errorCategory: ep.error_category,
        count: ep.n,
        affectedUsers: ep.affected_users,
      },
    })
  }

  // Rule 3: silent_failure
  // A normally-active notification_type has had zero sends in the last
  // SILENT_FAILURE_QUIET_HOURS hours. "Normally active" = averaged
  // > SILENT_FAILURE_BASELINE_PER_HOUR sends/hour over the prior 7d.
  const quietWindowStart = new Date(
    Date.now() - SILENT_FAILURE_QUIET_HOURS * 60 * 60 * 1000,
  ).toISOString()
  const baselineWindowStart = new Date(
    Date.now() - 7 * 24 * 60 * 60 * 1000,
  ).toISOString()

  // Baseline: per-type sent counts over last 7d.
  const { data: baselineRows } = await supabase
    .from('notification_delivery_log')
    .select('notification_type, status')
    .gte('created_at', baselineWindowStart)
    .eq('status', 'sent')
    .returns<Array<{ notification_type: string; status: string }>>()

  const baseline = new Map<string, number>()
  for (const r of baselineRows ?? []) {
    baseline.set(r.notification_type, (baseline.get(r.notification_type) ?? 0) + 1)
  }

  // Quiet check: per-type sent counts in the recent quiet window.
  const { data: quietRows } = await supabase
    .from('notification_delivery_log')
    .select('notification_type, status')
    .gte('created_at', quietWindowStart)
    .eq('status', 'sent')
    .returns<Array<{ notification_type: string; status: string }>>()

  const recentSends = new Map<string, number>()
  for (const r of quietRows ?? []) {
    recentSends.set(r.notification_type, (recentSends.get(r.notification_type) ?? 0) + 1)
  }

  const baselineHours = 7 * 24
  for (const [notificationType, sevenDaySent] of baseline) {
    const perHour = sevenDaySent / baselineHours
    if (perHour < SILENT_FAILURE_BASELINE_PER_HOUR) continue
    if ((recentSends.get(notificationType) ?? 0) > 0) continue

    firing.push({
      ruleId: 'silent_failure',
      notificationType,
      severity: 'warning',
      subject: `[Push Alert] ${notificationType} has gone silent`,
      textBody:
        `Push notification type "${notificationType}" has had zero successful sends ` +
        `in the last ${SILENT_FAILURE_QUIET_HOURS} hours, despite averaging ` +
        `${perHour.toFixed(1)}/hour over the prior 7 days.\n\n` +
        `This may indicate either a broken upstream emitter (no attempts ` +
        `being made) or a 100% delivery failure. Check the activity log:\n` +
        `${dashboardUrl()}\n\n` +
        `Playbook: shared-docs/playbooks/push_notification_firefighting.md`,
      payload: {
        baselinePerHour: perHour,
        sevenDaySent,
        quietWindowHours: SILENT_FAILURE_QUIET_HOURS,
      },
    })
  }

  return firing
}

/**
 * Reconcile the currently-firing set against active rows in notification_alerts.
 * - For each NEW firing (no matching uncleared row): insert + send email.
 * - For each EXISTING firing (matching uncleared row): refresh last_evaluated_at + payload.
 * - For each EXISTING uncleared alert NOT in the firing set: mark cleared_at,
 *   send "resolved" email.
 */
async function reconcileAlerts(
  supabase: SupabaseClient,
  firing: FiringAlert[],
): Promise<{ fired: string[]; cleared: string[]; refreshed: string[] }> {
  const { data: active, error } = await supabase
    .from('notification_alerts')
    .select('id, rule_id, notification_type, fired_at, email_sent_at')
    .is('cleared_at', null)
    .returns<ExistingAlert[]>()

  if (error) throw new Error(`Could not load active alerts: ${error.message}`)

  const activeMap = new Map<string, ExistingAlert>()
  for (const a of active ?? []) {
    activeMap.set(alertKey(a.rule_id, a.notification_type), a)
  }

  const firingMap = new Map<string, FiringAlert>()
  for (const f of firing) {
    firingMap.set(alertKey(f.ruleId, f.notificationType), f)
  }

  const fired: string[] = []
  const refreshed: string[] = []
  const cleared: string[] = []

  // Insert or refresh.
  for (const [key, f] of firingMap) {
    const existing = activeMap.get(key)
    if (existing) {
      await supabase
        .from('notification_alerts')
        .update({
          last_evaluated_at: new Date().toISOString(),
          last_payload: f.payload,
        })
        .eq('id', existing.id)
      refreshed.push(key)
    } else {
      const emailResult = await dispatchEmail(f, 'fired')
      const { error: insertErr } = await supabase
        .from('notification_alerts')
        .insert({
          rule_id: f.ruleId,
          notification_type: f.notificationType,
          severity: f.severity,
          last_payload: f.payload,
          email_sent_at: emailResult.success ? new Date().toISOString() : null,
          email_message_id: emailResult.messageId,
        })
      if (insertErr) {
        console.error('Failed to insert alert row:', insertErr.message)
      } else {
        fired.push(key)
      }
    }
  }

  // Clear active alerts whose conditions no longer hold.
  for (const [key, existing] of activeMap) {
    if (firingMap.has(key)) continue
    const clearedAt = new Date().toISOString()
    await supabase
      .from('notification_alerts')
      .update({ cleared_at: clearedAt })
      .eq('id', existing.id)
    cleared.push(key)
    // Send a "resolved" email — symmetric with the fired email.
    await dispatchEmail(
      {
        ruleId: existing.rule_id,
        notificationType: existing.notification_type,
        severity: 'info',
        subject: `[Push Alert RESOLVED] ${existing.rule_id}` +
          (existing.notification_type ? ` / ${existing.notification_type}` : ''),
        textBody:
          `The alert for rule "${existing.rule_id}"` +
          (existing.notification_type ? ` on type "${existing.notification_type}"` : '') +
          ` has cleared.\n\n` +
          `Originally fired at: ${existing.fired_at}\n` +
          `Resolved at: ${clearedAt}\n\n` +
          `Dashboard: ${dashboardUrl()}`,
        payload: {},
      },
      'cleared',
    )
  }

  return { fired, cleared, refreshed }
}

async function dispatchEmail(
  alert: FiringAlert,
  phase: 'fired' | 'cleared',
): Promise<{ success: boolean; messageId?: string }> {
  const results: { to: string; success: boolean; messageId?: string }[] = []
  for (const to of ALERT_RECIPIENTS) {
    const r = await sendAlertEmail({
      to,
      subject: alert.subject,
      textBody: alert.textBody,
      tag: `push_health:${alert.ruleId}:${phase}`,
    })
    results.push({ to, success: r.success, messageId: r.messageId })
    if (!r.success) {
      console.error(`Alert email to ${to} failed:`, r.error)
    }
  }
  // Surface the first successful messageId for the audit row.
  const firstSuccess = results.find((r) => r.success)
  return {
    success: firstSuccess !== undefined,
    messageId: firstSuccess?.messageId,
  }
}

function alertKey(ruleId: string, notificationType: string | null): string {
  return `${ruleId}::${notificationType ?? ''}`
}

function dashboardUrl(): string {
  // Placeholder until the admin app exposes a deep link to the push observability
  // surface. Update when the URL is finalized.
  return 'https://admin.saturdayvinyl.com/push'
}
