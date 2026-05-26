/**
 * Edge Function: register-push-token
 * Project: saturday-consumer-app
 * Description: Registers and manages FCM push notification tokens for the mobile app
 */

// Called by the app to register/update FCM push notification tokens
//
// This function:
// 1. Validates the authenticated user
// 2. Upserts the push token into push_notification_tokens
// 3. Marks previous tokens for this device as inactive (token refresh)
// 4. Optionally updates last_used_at for presence tracking

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RegisterTokenRequest {
  token: string
  platform: 'ios' | 'android'
  device_identifier: string
  app_version?: string
}

interface RegisterActivityTokenRequest {
  action: 'register_activity_token'
  push_token: string
  session_id: string
}

interface UpdatePresenceRequest {
  device_identifier: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // Get the authorization header to authenticate the user
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create client with user's JWT to validate authentication
    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false }
    })

    // Get the authenticated user (validates the JWT)
    const { data: { user }, error: authError } = await authClient.auth.getUser()
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create service role client for database operations (bypasses RLS)
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false }
    })

    // Look up the users table ID from the auth UID
    // The push_notification_tokens table references users.id, not auth.uid()
    const { data: dbUser, error: userError } = await supabase
      .from('users')
      .select('id')
      .eq('auth_user_id', user.id)
      .single()

    if (userError || !dbUser) {
      console.error('User not found in users table:', user.id, userError)
      return new Response(
        JSON.stringify({ error: 'User not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const userId = dbUser.id
    console.log(`Authenticated user: auth_uid=${user.id}, db_id=${userId}`)

    const url = new URL(req.url)
    const path = url.pathname.split('/').pop()

    // Handle different endpoints
    if (req.method === 'POST' && path === 'register-push-token') {
      return await handleRegisterToken(supabase, userId, await req.json())
    } else if (req.method === 'POST' && path === 'update-presence') {
      return await handleUpdatePresence(supabase, userId, await req.json())
    } else if (req.method === 'DELETE') {
      return await handleUnregisterToken(supabase, userId, await req.json())
    }

    // Default: register token
    return await handleRegisterToken(supabase, userId, await req.json())

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function handleRegisterToken(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  body: RegisterTokenRequest | RegisterActivityTokenRequest
): Promise<Response> {
  // Dispatch ActivityKit push tokens to a separate handler — different table,
  // different lifecycle, different keying. The body shape is the discriminator.
  if ((body as RegisterActivityTokenRequest).action === 'register_activity_token') {
    return await handleRegisterActivityToken(
      supabase,
      userId,
      body as RegisterActivityTokenRequest,
    )
  }

  const { token, platform, device_identifier, app_version } = body as RegisterTokenRequest

  // Validate required fields
  if (!token || !platform || !device_identifier) {
    return new Response(
      JSON.stringify({ error: 'Missing required fields: token, platform, device_identifier' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  if (!['ios', 'android'].includes(platform)) {
    return new Response(
      JSON.stringify({ error: 'Invalid platform. Must be "ios" or "android"' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  console.log(`Registering token for user ${userId}, device ${device_identifier}, platform ${platform}`)

  // Look up the existing row so we can tell whether the app is presenting
  // a genuinely new FCM string, or re-registering the same string the server
  // may already have flagged as dead.
  const { data: existing } = await supabase
    .from('push_notification_tokens')
    .select('id, token, is_active')
    .eq('user_id', userId)
    .eq('device_identifier', device_identifier)
    .maybeSingle() as { data: { id: string; token: string; is_active: boolean } | null }

  const isFreshToken = !existing || existing.token !== token

  // Build upsert payload. Only flip is_active back to true when the token
  // string genuinely changed — re-registering the same dead string should
  // NOT silently un-deactivate, otherwise we get a flap loop where every
  // push attempt re-deactivates the same token forever.
  const upsertData: Record<string, unknown> = {
    user_id: userId,
    token,
    platform,
    device_identifier,
    app_version: app_version || null,
    updated_at: new Date().toISOString(),
    last_used_at: new Date().toISOString(),
  }
  if (isFreshToken) {
    upsertData.is_active = true
  }

  const { data, error } = await supabase
    .from('push_notification_tokens')
    .upsert(upsertData, {
      onConflict: 'user_id,device_identifier',
    })
    .select('id')
    .single()

  if (error) {
    console.error('Error upserting token:', error)
    return new Response(
      JSON.stringify({ error: 'Failed to register token' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  // Cross-device dedup: if the same FCM string somehow shows up on another
  // device row, deactivate it. Unchanged from original behavior.
  await supabase
    .from('push_notification_tokens')
    .update({ is_active: false })
    .eq('token', token)
    .neq('id', data.id)

  // If the just-registered token is the same string the server has already
  // marked inactive, tell the client to rotate it. The client should call
  // FirebaseMessaging.deleteToken() + getToken() and re-register, breaking
  // the cycle.
  const shouldRefresh = !isFreshToken && existing !== null && existing.is_active === false
  let refreshReason: string | null = null
  if (shouldRefresh && existing) {
    const { data: lastFailure } = await supabase
      .from('notification_delivery_log')
      .select('error_message')
      .eq('token_id', existing.id)
      .eq('status', 'failed')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle() as { data: { error_message: string | null } | null }

    const msg = (lastFailure?.error_message ?? '').toLowerCase()
    if (msg.includes('badenvironmentkeyintoken')) refreshReason = 'apns_env_mismatch'
    else if (msg.includes('unregistered')) refreshReason = 'token_unregistered'
    else if (msg.includes('invalidregistration')) refreshReason = 'token_invalid'
    else refreshReason = 'deactivated'
  }

  console.log(
    `Token registered: ${data.id}, fresh=${isFreshToken}, should_refresh=${shouldRefresh}`,
  )

  return new Response(
    JSON.stringify({
      success: true,
      token_id: data.id,
      should_refresh: shouldRefresh,
      refresh_reason: refreshReason,
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

/**
 * Register an ActivityKit push token tied to a specific Live Activity instance.
 *
 * ActivityKit tokens differ from FCM tokens in three important ways:
 *   - One token per Live Activity instance, not per device.
 *   - Tokens are minted by iOS at Activity start and become invalid when the
 *     Activity ends. We never "rotate" them; we deactivate and replace.
 *   - Delivery bypasses Firebase entirely (direct APNs in update-track-progression).
 *
 * Verifies the session belongs to the calling user before persisting, so an
 * attacker with another user's session_id can't attach a token to it.
 */
async function handleRegisterActivityToken(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  body: RegisterActivityTokenRequest,
): Promise<Response> {
  const { push_token, session_id } = body

  if (!push_token || !session_id) {
    return new Response(
      JSON.stringify({ error: 'Missing required fields: push_token, session_id' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  // Defensive: confirm the session is the caller's. Activity tokens stay
  // bound to a single session — pointing one at someone else's session would
  // both leak Live Activity state and pollute analytics.
  const { data: session, error: sessionErr } = await supabase
    .from('playback_sessions')
    .select('id, user_id')
    .eq('id', session_id)
    .maybeSingle() as { data: { id: string; user_id: string } | null; error: unknown }

  if (sessionErr) {
    console.error('Error looking up session for activity token:', sessionErr)
    return new Response(
      JSON.stringify({ error: 'Failed to validate session' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  if (!session || session.user_id !== userId) {
    return new Response(
      JSON.stringify({ error: 'Session not found or not owned by caller' }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  // Upsert on (user_id, push_token). If iOS hands us a token we've seen before
  // for this user, refresh the session linkage and last-updated; otherwise
  // insert. The unique constraint is enforced at the DB level.
  const { data, error } = await supabase
    .from('activity_push_tokens')
    .upsert(
      {
        user_id: userId,
        session_id,
        push_token,
        is_active: true,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'user_id,push_token' },
    )
    .select('id')
    .single()

  if (error) {
    console.error('Error upserting activity push token:', error)
    return new Response(
      JSON.stringify({ error: 'Failed to register activity push token' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  console.log(`Activity push token registered: id=${data.id}, session=${session_id}`)

  return new Response(
    JSON.stringify({ success: true, id: data.id }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
}

async function handleUpdatePresence(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  body: UpdatePresenceRequest
): Promise<Response> {
  const { device_identifier } = body

  if (!device_identifier) {
    return new Response(
      JSON.stringify({ error: 'Missing required field: device_identifier' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  // Update last_used_at to indicate the app is actively connected
  // This is used by process-now-playing-event to decide whether to send push
  const { error } = await supabase
    .from('push_notification_tokens')
    .update({ last_used_at: new Date().toISOString() })
    .eq('user_id', userId)
    .eq('device_identifier', device_identifier)
    .eq('is_active', true)

  if (error) {
    console.error('Error updating presence:', error)
    return new Response(
      JSON.stringify({ error: 'Failed to update presence' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  return new Response(
    JSON.stringify({ success: true }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}

async function handleUnregisterToken(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  body: { device_identifier?: string; token?: string }
): Promise<Response> {
  const { device_identifier, token } = body

  if (!device_identifier && !token) {
    return new Response(
      JSON.stringify({ error: 'Missing required field: device_identifier or token' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  // Mark the token as inactive (soft delete)
  let query = supabase
    .from('push_notification_tokens')
    .update({ is_active: false, updated_at: new Date().toISOString() })
    .eq('user_id', userId)

  if (device_identifier) {
    query = query.eq('device_identifier', device_identifier)
  } else if (token) {
    query = query.eq('token', token)
  }

  const { error } = await query

  if (error) {
    console.error('Error unregistering token:', error)
    return new Response(
      JSON.stringify({ error: 'Failed to unregister token' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  return new Response(
    JSON.stringify({ success: true }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  )
}
