/**
 * Device session token issuance and revocation.
 *
 * Sessions are opaque random tokens stored in the device_sessions table.
 * Unlike Supabase user JWTs, they are not self-validating; the edge function
 * must look them up in the table on each authenticated call. This is fine for
 * the Hub's low-frequency cloud calls (boot reconciliation, occasional config
 * fetches) and avoids the complexity of issuing real signed JWTs for devices.
 *
 * Heartbeats and Realtime continue to use the shared anonymous key; only the
 * authenticated edge function paths require a device session token.
 */

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { bytesToHex } from './crypto.ts'

const ACCESS_TOKEN_TTL_SEC = 60 * 60          // 1 hour
const ACCESS_TOKEN_BYTES = 32
const REFRESH_TOKEN_BYTES = 32

export interface IssuedSession {
  access_token: string
  refresh_token: string
  expires_at: string  // ISO 8601
}

/**
 * Issue (or rotate) the device's session tokens. UPSERT on device_id so each
 * device has at most one active session.
 */
export async function issueDeviceSession(
  admin: SupabaseClient,
  deviceId: string,
  authUserId: string,
): Promise<IssuedSession> {
  const accessToken = randomHex(ACCESS_TOKEN_BYTES)
  const refreshToken = randomHex(REFRESH_TOKEN_BYTES)
  const expiresAt = new Date(Date.now() + ACCESS_TOKEN_TTL_SEC * 1000).toISOString()

  const { error } = await admin
    .from('device_sessions')
    .upsert(
      {
        device_id: deviceId,
        auth_user_id: authUserId,
        access_token: accessToken,
        refresh_token: refreshToken,
        expires_at: expiresAt,
        status: 'active',
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'device_id' },
    )

  if (error) throw new Error(`issueDeviceSession failed: ${error.message}`)

  return { access_token: accessToken, refresh_token: refreshToken, expires_at: expiresAt }
}

export async function revokeDeviceSession(
  admin: SupabaseClient,
  deviceId: string,
): Promise<void> {
  const { error } = await admin
    .from('device_sessions')
    .update({ status: 'revoked', updated_at: new Date().toISOString() })
    .eq('device_id', deviceId)
  if (error) throw new Error(`revokeDeviceSession failed: ${error.message}`)
}

function randomHex(byteLen: number): string {
  return bytesToHex(crypto.getRandomValues(new Uint8Array(byteLen)))
}
