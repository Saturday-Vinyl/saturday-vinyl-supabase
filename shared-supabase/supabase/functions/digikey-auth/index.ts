/**
 * Edge Function: digikey-auth
 * Project: saturday-admin-app
 * Description: Handles DigiKey OAuth 2.0 Authorization Code flow.
 *
 * Endpoints:
 *   GET  /digikey-auth/initiate  — Redirects user to DigiKey login (requires auth)
 *   GET  /digikey-auth/callback  — DigiKey redirects here with auth code
 *   GET  /digikey-auth/status    — Check if current user has a valid token
 *   POST /digikey-auth/disconnect — Remove stored tokens
 *
 * Environment variables (set via Supabase dashboard > Edge Functions > Secrets):
 *   DIGIKEY_CLIENT_ID     — OAuth client ID from DigiKey developer portal
 *   DIGIKEY_CLIENT_SECRET — OAuth client secret
 *   DIGIKEY_REDIRECT_URI  — https://<project>.supabase.co/functions/v1/digikey-auth/callback
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const DIGIKEY_AUTH_URL = 'https://api.digikey.com/v1/oauth2/authorize'
const DIGIKEY_TOKEN_URL = 'https://api.digikey.com/v1/oauth2/token'

function getEnvOrThrow(name: string): string {
  const val = Deno.env.get(name)
  if (!val) throw new Error(`Missing environment variable: ${name}`)
  return val
}

function getSupabaseClient(serviceRole = false) {
  const url = Deno.env.get('SUPABASE_URL')!
  const key = serviceRole
    ? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    : Deno.env.get('SUPABASE_ANON_KEY')!
  return createClient(url, key)
}

function jsonResponse(body: object, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const url = new URL(req.url)
  // The path after /functions/v1/digikey-auth
  const pathSegments = url.pathname.split('/').filter(Boolean)
  const action = pathSegments[pathSegments.length - 1]

  try {
    switch (action) {
      case 'initiate':
        return handleInitiate(req, url)
      case 'callback':
        return handleCallback(req, url)
      case 'status':
        return handleStatus(req)
      case 'disconnect':
        return handleDisconnect(req)
      default:
        return jsonResponse({ error: 'Unknown action', valid: ['initiate', 'callback', 'status', 'disconnect'] }, 404)
    }
  } catch (err) {
    console.error('digikey-auth error:', err)
    return jsonResponse({ error: err.message || 'Internal error' }, 500)
  }
})

// ============================================================================
// INITIATE: Redirect user to DigiKey OAuth consent page
// ============================================================================
async function handleInitiate(req: Request, url: URL) {
  // Authenticate the user
  const userId = await getAuthenticatedUserId(req)
  if (!userId) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  const clientId = getEnvOrThrow('DIGIKEY_CLIENT_ID')
  const redirectUri = getEnvOrThrow('DIGIKEY_REDIRECT_URI')

  // Store user ID in state parameter so we can associate the callback
  const state = btoa(JSON.stringify({ userId }))

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: clientId,
    redirect_uri: redirectUri,
    state,
  })

  const authUrl = `${DIGIKEY_AUTH_URL}?${params.toString()}`

  // Return the URL for the client to open in a browser
  return jsonResponse({ auth_url: authUrl })
}

// ============================================================================
// CALLBACK: DigiKey redirects here after user consent
// ============================================================================
async function handleCallback(req: Request, url: URL) {
  const code = url.searchParams.get('code')
  const state = url.searchParams.get('state')
  const error = url.searchParams.get('error')

  if (error) {
    return htmlResponse(`
      <h1>DigiKey Connection Failed</h1>
      <p>Error: ${error}</p>
      <p>${url.searchParams.get('error_description') || ''}</p>
      <p>You can close this window.</p>
    `, 400)
  }

  if (!code || !state) {
    return htmlResponse('<h1>Invalid callback</h1><p>Missing code or state parameter.</p>', 400)
  }

  // Decode state to get user ID
  let userId: string
  try {
    const decoded = JSON.parse(atob(state))
    userId = decoded.userId
    if (!userId) throw new Error('no userId in state')
  } catch {
    return htmlResponse('<h1>Invalid state parameter</h1>', 400)
  }

  // Exchange authorization code for tokens
  const clientId = getEnvOrThrow('DIGIKEY_CLIENT_ID')
  const clientSecret = getEnvOrThrow('DIGIKEY_CLIENT_SECRET')
  const redirectUri = getEnvOrThrow('DIGIKEY_REDIRECT_URI')

  const tokenResponse = await fetch(DIGIKEY_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
    }),
  })

  if (!tokenResponse.ok) {
    const errBody = await tokenResponse.text()
    console.error('DigiKey token exchange failed:', errBody)
    return htmlResponse(`<h1>Token Exchange Failed</h1><p>${errBody}</p>`, 500)
  }

  const tokens = await tokenResponse.json()

  // Store tokens using service role (bypasses RLS)
  const supabase = getSupabaseClient(true)

  const expiresAt = tokens.expires_in
    ? new Date(Date.now() + tokens.expires_in * 1000).toISOString()
    : null

  const { error: upsertError } = await supabase
    .from('supplier_api_tokens')
    .upsert(
      {
        user_id: userId,
        provider: 'digikey',
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token || null,
        token_expires_at: expiresAt,
        scopes: tokens.scope || null,
        provider_metadata: { client_id: clientId },
      },
      { onConflict: 'user_id,provider' }
    )

  if (upsertError) {
    console.error('Failed to store tokens:', upsertError)
    return htmlResponse(`<h1>Failed to store credentials</h1><p>${upsertError.message}</p>`, 500)
  }

  // Return a nice HTML page that the user sees in their browser
  return htmlResponse(`
    <html>
    <head>
      <title>DigiKey Connected</title>
      <style>
        body { font-family: -apple-system, system-ui, sans-serif; text-align: center; padding: 60px 20px; background: #f8f9fa; }
        .card { background: white; border-radius: 16px; padding: 40px; max-width: 400px; margin: 0 auto; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .check { font-size: 64px; }
        h1 { color: #1a1a1a; margin: 16px 0 8px; }
        p { color: #666; }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="check">&#10004;</div>
        <h1>DigiKey Connected!</h1>
        <p>Your DigiKey account has been linked. You can close this window and return to the Saturday app.</p>
      </div>
    </body>
    </html>
  `)
}

// ============================================================================
// STATUS: Check if user has valid DigiKey tokens
// ============================================================================
async function handleStatus(req: Request) {
  const userId = await getAuthenticatedUserId(req)
  if (!userId) return jsonResponse({ error: 'Unauthorized' }, 401)

  const supabase = getSupabaseClient(true)
  const { data, error } = await supabase
    .from('supplier_api_tokens')
    .select('token_expires_at, scopes, created_at, updated_at')
    .eq('user_id', userId)
    .eq('provider', 'digikey')
    .maybeSingle()

  if (error) {
    return jsonResponse({ error: error.message }, 500)
  }

  if (!data) {
    return jsonResponse({ connected: false })
  }

  const isExpired = data.token_expires_at
    ? new Date(data.token_expires_at) < new Date()
    : false

  return jsonResponse({
    connected: true,
    token_expired: isExpired,
    connected_at: data.created_at,
    last_refreshed: data.updated_at,
  })
}

// ============================================================================
// DISCONNECT: Remove stored DigiKey tokens
// ============================================================================
async function handleDisconnect(req: Request) {
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  const userId = await getAuthenticatedUserId(req)
  if (!userId) return jsonResponse({ error: 'Unauthorized' }, 401)

  const supabase = getSupabaseClient(true)
  const { error } = await supabase
    .from('supplier_api_tokens')
    .delete()
    .eq('user_id', userId)
    .eq('provider', 'digikey')

  if (error) {
    return jsonResponse({ error: error.message }, 500)
  }

  return jsonResponse({ disconnected: true })
}

// ============================================================================
// HELPERS
// ============================================================================

async function getAuthenticatedUserId(req: Request): Promise<string | null> {
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return null

  const supabase = getSupabaseClient(false)
  // Override auth with the user's token
  const userClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  )

  const { data: { user }, error } = await userClient.auth.getUser()
  if (error || !user) return null

  // Look up the application user ID from auth_user_id
  const serviceClient = getSupabaseClient(true)
  const { data: appUser } = await serviceClient
    .from('users')
    .select('id')
    .eq('auth_user_id', user.id)
    .single()

  return appUser?.id || null
}

function htmlResponse(html: string, status = 200) {
  return new Response(html, {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'text/html; charset=utf-8' },
  })
}
