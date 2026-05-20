/**
 * Edge Function: refresh_device_session
 * Project: sv-hub-firmware
 * Description: Rotates a device's access/refresh token pair using its
 *              refresh token. Used by Hub firmware when its access token is
 *              expired or about to expire.
 *
 * Body: { refresh_token: string }
 * Returns: { access_token, refresh_token, expires_at }
 *
 * No `Authorization` header required - the refresh token in the body is the
 * credential. The endpoint single-uses the refresh token (rotates it on every
 * call) to limit the window of replay.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders, jsonResponse } from '../_shared/cors.ts'
import { getAdminClient } from '../_shared/auth.ts'
import { issueDeviceSession } from '../_shared/device_sessions.ts'

interface RefreshRequest {
  refresh_token?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await readJson<RefreshRequest>(req)
    if (!body?.refresh_token) {
      return jsonResponse({ error: 'refresh_token required' }, 400)
    }

    const admin = getAdminClient()
    const { data: session } = await admin
      .from('device_sessions')
      .select('id, device_id, auth_user_id, status')
      .eq('refresh_token', body.refresh_token)
      .eq('status', 'active')
      .maybeSingle()

    if (!session) {
      return jsonResponse({ error: 'invalid_refresh_token' }, 401)
    }

    // Rotate both tokens. The UPSERT path in issueDeviceSession overwrites
    // the current row keyed by device_id, so the old refresh token becomes
    // unusable after this call.
    const tokens = await issueDeviceSession(
      admin,
      session.device_id,
      session.auth_user_id,
    )

    return jsonResponse({
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      expires_at: tokens.expires_at,
    })
  } catch (err) {
    console.error('refresh_device_session unexpected error', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})

async function readJson<T>(req: Request): Promise<T | null> {
  try {
    return await req.json() as T
  } catch {
    return null
  }
}
