// Shared Postmark email helper for alerting.
//
// Single primitive that any edge function can call to deliver an alert
// email. Mirrors the shape of send-fcm-push.ts / send-activity-push.ts so
// future channels (Slack, in-app, SMS) can slot in with the same interface.
//
// Environment variables required:
//   POSTMARK_SERVER_TOKEN     — Server-level API token from Postmark
//   POSTMARK_FROM_EMAIL       — Verified Sender Signature address
//   POSTMARK_MESSAGE_STREAM   — Transactional stream ID (e.g. 'outbound')

export interface SendAlertEmailArgs {
  to: string
  subject: string
  textBody: string
  htmlBody?: string
  /** Optional Postmark tag for grouping (e.g. 'push_health'). */
  tag?: string
}

export interface SendAlertEmailResult {
  success: boolean
  messageId?: string
  error?: string
}

export async function sendAlertEmail(
  args: SendAlertEmailArgs,
): Promise<SendAlertEmailResult> {
  const token = Deno.env.get('POSTMARK_SERVER_TOKEN')
  const from = Deno.env.get('POSTMARK_FROM_EMAIL')
  const stream = Deno.env.get('POSTMARK_MESSAGE_STREAM') ?? 'outbound'

  if (!token || !from) {
    console.log('[send-alert-email] Postmark not configured, skipping')
    return {
      success: false,
      error: 'Postmark not configured (missing POSTMARK_SERVER_TOKEN or POSTMARK_FROM_EMAIL)',
    }
  }

  const body: Record<string, unknown> = {
    From: from,
    To: args.to,
    Subject: args.subject,
    TextBody: args.textBody,
    MessageStream: stream,
  }
  if (args.htmlBody) body.HtmlBody = args.htmlBody
  if (args.tag) body.Tag = args.tag

  let response: Response
  try {
    response = await fetch('https://api.postmarkapp.com/email', {
      method: 'POST',
      headers: {
        'X-Postmark-Server-Token': token,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    })
  } catch (err) {
    const message = (err as Error).message
    console.error('[send-alert-email] Network error:', message)
    return { success: false, error: `Network error: ${message}` }
  }

  const payload = await response.json().catch(() => null) as
    | { MessageID?: string; ErrorCode?: number; Message?: string }
    | null

  if (!response.ok) {
    const errorMessage =
      `Postmark error ${response.status}: ${payload?.Message ?? '(no message)'} ` +
      `(ErrorCode=${payload?.ErrorCode ?? 'n/a'})`
    console.error('[send-alert-email]', errorMessage)
    return { success: false, error: errorMessage }
  }

  return { success: true, messageId: payload?.MessageID }
}
