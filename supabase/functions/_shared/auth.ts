/**
 * Auth helpers for Saturday edge functions.
 *
 * Supports two caller contexts:
 *
 *   1. User JWT - app or Hub-during-BLE-adoption holds a Supabase user JWT
 *      and sends it as `Authorization: Bearer <jwt>`.
 *
 *   2. Device session token - Hub for boot reconciliation holds a device
 *      access token (issued at adoption, stored in device_sessions). Sent the
 *      same way: `Authorization: Bearer <token>`.
 *
 * `resolveCaller` distinguishes the two: device session tokens are looked up
 * directly in `device_sessions`; user JWTs are validated via Supabase Auth.
 */

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

export interface ResolvedCaller {
  kind: 'user' | 'device'
  authUserId: string       // auth.users(id)
  databaseUserId: string   // public.users(id)
  deviceId?: string        // present when kind === 'device'
  deviceSessionId?: string // present when kind === 'device'
}

export function getAdminClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  return createClient(url, serviceKey, { auth: { persistSession: false } })
}

export function extractBearerToken(req: Request): string | null {
  const auth = req.headers.get('Authorization')
  if (!auth || !auth.startsWith('Bearer ')) return null
  return auth.slice('Bearer '.length).trim()
}

/**
 * Resolve the caller from the Authorization header.
 *
 * Tries device session token first (single indexed lookup), then falls back to
 * validating as a Supabase user JWT. This ordering means we can distinguish the
 * two without requiring the caller to declare their type.
 */
export async function resolveCaller(
  req: Request,
  admin: SupabaseClient,
): Promise<ResolvedCaller | null> {
  const token = extractBearerToken(req)
  if (!token) return null

  // 1. Try device session token.
  const { data: session } = await admin
    .from('device_sessions')
    .select('id, device_id, auth_user_id, expires_at, status')
    .eq('access_token', token)
    .eq('status', 'active')
    .maybeSingle()

  if (session) {
    if (new Date(session.expires_at).getTime() < Date.now()) {
      return null // Expired; caller must refresh first.
    }
    const dbUserId = await lookupDatabaseUserId(admin, session.auth_user_id)
    if (!dbUserId) return null
    return {
      kind: 'device',
      authUserId: session.auth_user_id,
      databaseUserId: dbUserId,
      deviceId: session.device_id,
      deviceSessionId: session.id,
    }
  }

  // 2. Validate as a Supabase user JWT.
  const url = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const userClient = createClient(url, anonKey, {
    auth: { persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  })

  const { data: { user }, error } = await userClient.auth.getUser()
  if (error || !user) return null

  const dbUserId = await lookupDatabaseUserId(admin, user.id)
  if (!dbUserId) return null

  return {
    kind: 'user',
    authUserId: user.id,
    databaseUserId: dbUserId,
  }
}

async function lookupDatabaseUserId(
  admin: SupabaseClient,
  authUserId: string,
): Promise<string | null> {
  const { data, error } = await admin
    .from('users')
    .select('id')
    .eq('auth_user_id', authUserId)
    .maybeSingle()
  if (error || !data) return null
  return data.id
}
