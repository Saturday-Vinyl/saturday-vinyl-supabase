// Shared APNs ActivityKit Push Helper
// Used by edge functions to send Live Activity updates via Apple Push Notification service.
//
// Environment variables required:
//   APNS_KEY_ID       — Key ID from Apple Developer portal (e.g., 46Y479Y6DF)
//   APNS_TEAM_ID      — Apple Developer Team ID
//   APNS_PRIVATE_KEY  — .p8 key contents (PEM-encoded, newlines as \n)
//   APNS_BUNDLE_ID    — App bundle ID (e.g., com.saturdayvinyl.consumer)

import { pemToArrayBuffer } from './send-push.ts'

// Cache the JWT to avoid re-signing on every push (valid for 1 hour)
let cachedJwt: string | null = null
let cachedJwtExpiry = 0

/**
 * Send an ActivityKit push notification to update a Live Activity on iOS.
 *
 * @param pushToken - The ActivityKit push token for the specific Live Activity
 * @param contentState - The ContentState object matching LiveActivitiesAppAttributes.ContentState
 * @param options - Optional event type and dismissal date
 */
export async function sendActivityPush(
  pushToken: string,
  contentState: Record<string, unknown>,
  options?: {
    event?: 'update' | 'end'
    dismissalDate?: number
    relevanceScore?: number
    staleDate?: number
  }
): Promise<{ success: boolean; error?: string }> {
  const keyId = Deno.env.get('APNS_KEY_ID')
  const teamId = Deno.env.get('APNS_TEAM_ID')
  const rawPrivateKey = Deno.env.get('APNS_PRIVATE_KEY')
  const bundleId = Deno.env.get('APNS_BUNDLE_ID')

  if (!keyId || !teamId || !rawPrivateKey || !bundleId) {
    console.log('[send-activity-push] APNs not configured, skipping push')
    return { success: false, error: 'apns_not_configured' }
  }

  const privateKey = rawPrivateKey.replace(/\\n/g, '\n')

  try {
    // Get or refresh JWT
    const jwt = await getApnsJwt(keyId, teamId, privateKey)

    const now = Math.floor(Date.now() / 1000)
    const event = options?.event ?? 'update'

    // Build APNs payload
    const payload: Record<string, unknown> = {
      aps: {
        timestamp: now,
        event,
        'content-state': contentState,
        ...(options?.relevanceScore !== undefined && {
          'relevance-score': options.relevanceScore,
        }),
        ...(options?.staleDate !== undefined && {
          'stale-date': options.staleDate,
        }),
        ...(options?.dismissalDate !== undefined && {
          'dismissal-date': options.dismissalDate,
        }),
      },
    }

    // Use production APNs endpoint
    const apnsUrl = `https://api.push.apple.com/3/device/${pushToken}`

    const response = await fetch(apnsUrl, {
      method: 'POST',
      headers: {
        authorization: `bearer ${jwt}`,
        'apns-push-type': 'liveactivity',
        'apns-topic': `${bundleId}.push-type.liveactivity`,
        'apns-priority': '10',
      },
      body: JSON.stringify(payload),
    })

    if (!response.ok) {
      const errorBody = await response.text()
      console.error(
        `[send-activity-push] APNs error: ${response.status} - ${errorBody}`
      )

      // Token is no longer valid
      if (response.status === 410 || response.status === 400) {
        return { success: false, error: 'invalid_token' }
      }

      return { success: false, error: `apns_error_${response.status}` }
    }

    return { success: true }
  } catch (error) {
    console.error('[send-activity-push] Error:', error)
    return { success: false, error: (error as Error).message }
  }
}

/**
 * Get a cached or fresh APNs JWT (ES256-signed, 1 hour validity).
 *
 * APNs requires token-based authentication using a JWT signed with the
 * ES256 algorithm (ECDSA with P-256 curve and SHA-256 hash).
 */
async function getApnsJwt(
  keyId: string,
  teamId: string,
  privateKey: string
): Promise<string> {
  const now = Math.floor(Date.now() / 1000)

  // Return cached JWT if still valid (refresh 5 min before expiry)
  if (cachedJwt && cachedJwtExpiry > now + 300) {
    return cachedJwt
  }

  // JWT header
  const header = { alg: 'ES256', kid: keyId }
  // JWT payload
  const payload = { iss: teamId, iat: now }

  // Base64url encode header and payload
  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedPayload = base64UrlEncode(JSON.stringify(payload))

  const signatureInput = `${encodedHeader}.${encodedPayload}`

  // Import the .p8 private key for ECDSA P-256
  const keyBuffer = pemToArrayBuffer(privateKey)
  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyBuffer,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  )

  // Sign with ECDSA SHA-256
  const signatureBuffer = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signatureInput)
  )

  // ECDSA signature from Web Crypto is in DER format — convert to raw r||s
  const rawSignature = derToRawSignature(new Uint8Array(signatureBuffer))
  const encodedSignature = base64UrlEncode(
    String.fromCharCode(...rawSignature)
  )

  const jwt = `${signatureInput}.${encodedSignature}`

  // Cache for reuse
  cachedJwt = jwt
  cachedJwtExpiry = now + 3600 // 1 hour

  return jwt
}

/**
 * Base64url encode a string (no padding).
 */
function base64UrlEncode(input: string): string {
  return btoa(input)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
}

/**
 * Convert DER-encoded ECDSA signature to raw r||s format.
 *
 * Web Crypto's ECDSA sign() returns DER-encoded signatures, but APNs
 * expects raw concatenated r||s (64 bytes for P-256).
 */
function derToRawSignature(der: Uint8Array): Uint8Array {
  // DER format: 0x30 <len> 0x02 <r-len> <r> 0x02 <s-len> <s>
  let offset = 2 // Skip 0x30 and total length

  // Read r
  if (der[offset] !== 0x02) throw new Error('Invalid DER signature')
  offset++
  const rLen = der[offset]
  offset++
  let r = der.slice(offset, offset + rLen)
  offset += rLen

  // Read s
  if (der[offset] !== 0x02) throw new Error('Invalid DER signature')
  offset++
  const sLen = der[offset]
  offset++
  let s = der.slice(offset, offset + sLen)

  // Remove leading zero padding (DER uses it for positive sign)
  if (r.length === 33 && r[0] === 0) r = r.slice(1)
  if (s.length === 33 && s[0] === 0) s = s.slice(1)

  // Pad to 32 bytes each (P-256)
  const raw = new Uint8Array(64)
  raw.set(r, 32 - r.length)
  raw.set(s, 64 - s.length)

  return raw
}
