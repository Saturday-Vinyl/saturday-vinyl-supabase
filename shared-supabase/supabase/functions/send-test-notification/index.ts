/**
 * Edge Function: send-test-notification
 * Project: saturday-admin-app
 * Description: Admin-gated free-form push to a single token. Used by ops to
 *              confirm push delivery is working end-to-end (e.g. after an APNs
 *              credential change) without waiting for a real event.
 *
 * Body: { token_id: string, title: string, body: string, data?: Record<string,string> }
 * Response: { success, delivery_log_id, error?, error_category? }
 *
 * Routes through the same `sendFcmPush` helper as production paths, so the
 * test is a faithful proxy for what real pushes do.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders, jsonResponse } from '../_shared/cors.ts'
import { getAdminClient, resolveCaller } from '../_shared/auth.ts'
import { sendFcmPush } from '../_shared/send-fcm-push.ts'

interface TestRequest {
  token_id?: string
  title?: string
  body?: string
  data?: Record<string, unknown>
}

const MAX_TITLE = 200
const MAX_BODY = 500

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  try {
    const admin = getAdminClient()

    const caller = await resolveCaller(req, admin)
    if (!caller || caller.kind !== 'user') {
      return jsonResponse({ error: 'Unauthorized' }, 401)
    }

    const { data: callerRow, error: callerErr } = await admin
      .from('users')
      .select('id, is_admin')
      .eq('id', caller.databaseUserId)
      .maybeSingle()
    if (callerErr || !callerRow || !callerRow.is_admin) {
      return jsonResponse({ error: 'Forbidden — admin required' }, 403)
    }

    // ---- Validate body --------------------------------------------------
    const body = (await req.json().catch(() => null)) as TestRequest | null
    if (!body) {
      return jsonResponse({ error: 'Invalid JSON body' }, 400)
    }

    const tokenId = body.token_id
    const title = (body.title ?? '').trim()
    const messageBody = (body.body ?? '').trim()

    if (!tokenId) {
      return jsonResponse({ error: 'Missing token_id' }, 400)
    }
    if (!title) {
      return jsonResponse({ error: 'Missing title' }, 400)
    }
    if (!messageBody) {
      return jsonResponse({ error: 'Missing body' }, 400)
    }
    if (title.length > MAX_TITLE) {
      return jsonResponse(
        { error: `Title exceeds ${MAX_TITLE} characters` },
        400,
      )
    }
    if (messageBody.length > MAX_BODY) {
      return jsonResponse(
        { error: `Body exceeds ${MAX_BODY} characters` },
        400,
      )
    }

    // FCM v1 requires all data values to be strings. Coerce defensively and
    // reject anything that can't be represented.
    const dataPayload: Record<string, string> = { type: 'admin_test' }
    if (body.data && typeof body.data === 'object') {
      for (const [key, value] of Object.entries(body.data)) {
        if (typeof value !== 'string') {
          return jsonResponse(
            {
              error: `data.${key} must be a string (FCM requirement); got ${typeof value}`,
            },
            400,
          )
        }
        dataPayload[key] = value
      }
    }

    // ---- Load target token ---------------------------------------------
    const { data: token, error: tokenErr } = await admin
      .from('push_notification_tokens')
      .select('id, token, user_id, platform, is_active')
      .eq('id', tokenId)
      .maybeSingle()

    if (tokenErr) {
      console.error('[send-test-notification] Token lookup error:', tokenErr)
      return jsonResponse({ error: 'Database error' }, 500)
    }
    if (!token) {
      return jsonResponse({ error: 'Token not found' }, 404)
    }
    if (!token.is_active) {
      return jsonResponse(
        { error: 'Token is inactive — reactivate it or pick a different device' },
        400,
      )
    }

    // ---- Send -----------------------------------------------------------
    const result = await sendFcmPush({
      token: token.token,
      title,
      body: messageBody,
      data: dataPayload,
      ...(token.platform === 'android'
        ? { android: { channel_id: 'admin_test', priority: 'high' as const } }
        : {}),
      apns: { sound: 'default' },
    })

    // ---- Audit log ------------------------------------------------------
    const insertRow = {
      user_id: token.user_id,
      notification_type: 'admin_test',
      source_id: null,
      token_id: token.id,
      status: result.success ? 'sent' : 'failed',
      error_message: result.error ?? null,
      sent_at: result.success ? new Date().toISOString() : null,
      sent_by_user_id: caller.databaseUserId,
    }
    const { data: inserted, error: insertErr } = await admin
      .from('notification_delivery_log')
      .insert(insertRow)
      .select('id')
      .single()

    if (insertErr) {
      console.error('[send-test-notification] Failed to insert log row:', insertErr)
      // Don't fail the response — the push may have actually succeeded. Best
      // effort: surface what we know.
      return jsonResponse({
        success: result.success,
        delivery_log_id: null,
        error: 'Push attempted but failed to log',
      }, 500)
    }

    // ---- Token deactivation (same policy as primary path) --------------
    if (!result.success && result.tokenShouldDeactivate) {
      await admin
        .from('push_notification_tokens')
        .update({ is_active: false })
        .eq('id', token.id)
    }

    return jsonResponse({
      success: result.success,
      delivery_log_id: inserted.id,
      ...(result.error ? { error: result.error } : {}),
      ...(result.errorCategory ? { error_category: result.errorCategory } : {}),
    })
  } catch (err) {
    console.error('[send-test-notification] Unhandled error:', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
