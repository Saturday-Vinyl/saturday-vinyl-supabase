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
  body: RegisterTokenRequest
): Promise<Response> {
  const { token, platform, device_identifier, app_version } = body

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

  // Upsert the token - this handles both new registrations and token refreshes
  // The unique constraint on (user_id, device_identifier) ensures one token per device
  const { data, error } = await supabase
    .from('push_notification_tokens')
    .upsert({
      user_id: userId,
      token,
      platform,
      device_identifier,
      app_version: app_version || null,
      is_active: true,
      updated_at: new Date().toISOString(),
      last_used_at: new Date().toISOString(),
    }, {
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

  // If the token changed (refresh), mark the old token as inactive
  // This happens automatically via upsert, but we should also deactivate
  // any other tokens with the same FCM token (in case of device sharing)
  await supabase
    .from('push_notification_tokens')
    .update({ is_active: false })
    .eq('token', token)
    .neq('id', data.id)

  console.log(`Token registered successfully: ${data.id}`)

  return new Response(
    JSON.stringify({ success: true, token_id: data.id }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
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
