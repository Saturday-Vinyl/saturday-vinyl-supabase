// Shared FCM v1 Push Helper
//
// Canonical primitive for sending a single push via Firebase Cloud Messaging v1.
// Mints an OAuth2 access token from a service-account JWT, POSTs the message,
// parses the response, and returns a categorized result.
//
// Two important invariants vs. the previous inline implementations:
//
//   1. `errorCategory` matches the buckets the admin dashboard view
//      `admin_push_error_patterns` already groups by (apns_env_mismatch,
//      fcm_auth_error, token_unregistered, token_invalid, fcm_quota,
//      unauthenticated, rate_limited, other). Saving the helper's raw
//      `error` to notification_delivery_log keeps that view's ILIKE matching
//      working without changes.
//
//   2. `tokenShouldDeactivate` is only true for token-specific failures
//      (Unregistered, InvalidRegistration, BadEnvironmentKeyInToken).
//      Server-wide auth failures (THIRD_PARTY_AUTH_ERROR, 401) are NOT
//      grounds for deactivation — they affect every token identically and
//      need an alert, not silent cleanup. This is the fix for the May 14
//      outage pattern.
//
// Environment variables required:
//   FIREBASE_PROJECT_ID
//   FIREBASE_CLIENT_EMAIL
//   FIREBASE_PRIVATE_KEY (PEM, newlines may be encoded as \n)

import { pemToArrayBuffer } from './send-push.ts'

export type FcmErrorCategory =
  | 'apns_env_mismatch'
  | 'fcm_auth_error'
  | 'token_unregistered'
  | 'token_invalid'
  | 'fcm_quota'
  | 'unauthenticated'
  | 'rate_limited'
  | 'not_configured'
  | 'other'

export interface SendFcmPushArgs {
  /** Device FCM registration token. */
  token: string
  /** Notification title (visible in alert). */
  title: string
  /** Notification body (visible in alert). */
  body: string
  /** Custom data payload. FCM requires all values to be strings. */
  data?: Record<string, string>
  /** Android-specific overrides. */
  android?: {
    channel_id?: string
    priority?: 'high' | 'normal'
    sound?: string
  }
  /** APNs-specific overrides. Included for iOS tokens. */
  apns?: {
    sound?: string
    badge?: number
  }
}

export interface SendFcmPushResult {
  success: boolean
  /** FCM message name on success (projects/.../messages/<id>). */
  messageId?: string
  /** Raw error message, suitable for storage in notification_delivery_log.error_message. */
  error?: string
  /** Categorized error bucket aligned with admin_push_error_patterns. */
  errorCategory?: FcmErrorCategory
  /**
   * True only when the failure is token-specific (the FCM token is no longer
   * valid for this device). Server-wide auth or environment errors are NOT
   * grounds for deactivation.
   */
  tokenShouldDeactivate?: boolean
}

// Cache the access token for its full hour validity to avoid re-minting per push.
let cachedAccessToken: string | null = null
let cachedAccessTokenExpiry = 0

/**
 * Send one push via the FCM v1 API.
 *
 * Returns a structured result instead of throwing — callers can branch on
 * `errorCategory` and `tokenShouldDeactivate` rather than re-parsing error
 * strings.
 */
export async function sendFcmPush(
  args: SendFcmPushArgs,
): Promise<SendFcmPushResult> {
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID')
  const rawPrivateKey = Deno.env.get('FIREBASE_PRIVATE_KEY')
  const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL')

  if (!projectId || !rawPrivateKey || !clientEmail) {
    console.log('[send-fcm-push] Firebase not configured, skipping')
    return {
      success: false,
      error: 'Firebase not configured (missing FIREBASE_* env vars)',
      errorCategory: 'not_configured',
    }
  }

  const privateKey = rawPrivateKey.replace(/\\n/g, '\n')

  let accessToken: string
  try {
    accessToken = await getFirebaseAccessToken(privateKey, clientEmail)
  } catch (err) {
    const message = (err as Error).message
    console.error('[send-fcm-push] Failed to mint OAuth token:', message)
    return {
      success: false,
      error: `Failed to obtain Firebase access token: ${message}`,
      errorCategory: 'fcm_auth_error',
    }
  }

  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  const message: Record<string, unknown> = {
    token: args.token,
    notification: { title: args.title, body: args.body },
  }
  if (args.data) {
    message.data = args.data
  }
  if (args.android) {
    message.android = {
      priority: args.android.priority ?? 'high',
      notification: {
        channel_id: args.android.channel_id ?? 'default',
        sound: args.android.sound ?? 'default',
      },
    }
  }
  if (args.apns) {
    message.apns = {
      payload: {
        aps: {
          sound: args.apns.sound ?? 'default',
          ...(args.apns.badge !== undefined ? { badge: args.apns.badge } : {}),
        },
      },
    }
  }

  let response: Response
  try {
    response = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message }),
    })
  } catch (err) {
    const message = (err as Error).message
    console.error('[send-fcm-push] Network error:', message)
    return {
      success: false,
      error: `Network error: ${message}`,
      errorCategory: 'other',
    }
  }

  if (response.ok) {
    const json = await response.json().catch(() => null) as { name?: string } | null
    return { success: true, messageId: json?.name }
  }

  const errorBody = await response.text()
  const errorMessage = `Firebase push failed: ${response.status} - ${errorBody}`
  const { category, tokenShouldDeactivate } = categorizeFcmError(
    response.status,
    errorBody,
  )

  console.error(
    `[send-fcm-push] FCM error (category=${category}, deactivate=${tokenShouldDeactivate}):`,
    errorMessage,
  )

  return {
    success: false,
    error: errorMessage,
    errorCategory: category,
    tokenShouldDeactivate,
  }
}

/**
 * Bucket an FCM error into the categories admin_push_error_patterns groups by.
 *
 * `tokenShouldDeactivate` is only true for token-specific failures. Server-wide
 * failures stay false so the admin sees the spike in the dashboard instead of
 * silently shedding tokens.
 */
export function categorizeFcmError(
  status: number,
  body: string,
): { category: FcmErrorCategory; tokenShouldDeactivate: boolean } {
  const lower = body.toLowerCase()

  // Token-specific failures — safe to deactivate.
  if (lower.includes('badenvironmentkeyintoken')) {
    return { category: 'apns_env_mismatch', tokenShouldDeactivate: true }
  }
  if (lower.includes('unregistered')) {
    return { category: 'token_unregistered', tokenShouldDeactivate: true }
  }
  if (lower.includes('invalidregistration') || lower.includes('invalid_argument')) {
    return { category: 'token_invalid', tokenShouldDeactivate: true }
  }

  // Server-wide / credential failures — do NOT deactivate tokens.
  if (lower.includes('third_party_auth_error')) {
    return { category: 'fcm_auth_error', tokenShouldDeactivate: false }
  }
  if (lower.includes('quotaexceeded')) {
    return { category: 'fcm_quota', tokenShouldDeactivate: false }
  }
  if (status === 401 || lower.includes('unauthenticated')) {
    return { category: 'unauthenticated', tokenShouldDeactivate: false }
  }
  if (status === 429 || lower.includes('rate')) {
    return { category: 'rate_limited', tokenShouldDeactivate: false }
  }

  return { category: 'other', tokenShouldDeactivate: false }
}

/**
 * Get a cached or freshly-minted OAuth2 access token for FCM.
 *
 * The token is valid for one hour; we cache it for that full hour minus a
 * 60-second safety margin so concurrent pushes don't all re-sign.
 */
async function getFirebaseAccessToken(
  privateKey: string,
  clientEmail: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedAccessToken && cachedAccessTokenExpiry > now + 60) {
    return cachedAccessToken
  }

  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }

  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedPayload = base64UrlEncode(JSON.stringify(payload))
  const signatureInput = `${encodedHeader}.${encodedPayload}`

  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(signatureInput),
  )
  const encodedSignature = base64UrlEncode(
    String.fromCharCode(...new Uint8Array(signature)),
  )
  const jwt = `${signatureInput}.${encodedSignature}`

  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  if (!tokenResponse.ok) {
    const errorText = await tokenResponse.text()
    throw new Error(`${tokenResponse.status} - ${errorText}`)
  }

  const tokenData = await tokenResponse.json()
  if (!tokenData.access_token) {
    throw new Error('OAuth response missing access_token')
  }

  cachedAccessToken = tokenData.access_token
  cachedAccessTokenExpiry = now + 3600
  return tokenData.access_token
}

function base64UrlEncode(input: string): string {
  return btoa(input)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}
