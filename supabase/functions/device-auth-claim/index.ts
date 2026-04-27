/**
 * Edge Function: device-auth-claim
 * Project: shared
 * Description: Claims a device pairing code on behalf of an authenticated user.
 *              Called from the user's phone/browser after they enter the code shown on TV.
 *              Stores the caller's session tokens so the TV can pick them up via polling.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ClaimRequest {
  user_code: string
  // The Flutter app sends its refresh_token so the TV gets an independent session
  refresh_token?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // This endpoint requires authentication — the user must be logged in
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // Verify the caller is authenticated
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } }
    })

    const { data: { user }, error: userError } = await userClient.auth.getUser()
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false }
    })

    // Parse request
    const body: ClaimRequest = await req.json()
    const { user_code, refresh_token } = body

    if (!user_code) {
      return new Response(
        JSON.stringify({ error: 'Missing user_code' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const normalizedCode = user_code.toUpperCase().trim()
    console.log(`User ${user.id} attempting to claim code: ${normalizedCode}`)

    // Find the pending code
    const { data: codeRecord, error: findError } = await adminClient
      .from('device_auth_codes')
      .select('*')
      .eq('user_code', normalizedCode)
      .eq('status', 'pending')
      .maybeSingle()

    if (findError || !codeRecord) {
      return new Response(
        JSON.stringify({ error: 'Invalid or expired code. Please check the code on your TV and try again.' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check expiry
    if (new Date(codeRecord.expires_at) < new Date()) {
      await adminClient
        .from('device_auth_codes')
        .update({ status: 'expired' })
        .eq('id', codeRecord.id)

      return new Response(
        JSON.stringify({ error: 'This code has expired. Please request a new code on your TV.' }),
        { status: 410, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Extract the access token from the Authorization header
    const accessToken = authHeader.replace('Bearer ', '')

    // Try to generate a dedicated session for the TV via refresh token.
    // If the caller provided their refresh_token, use it to mint a fresh session
    // so the TV gets its own independent token pair.
    let tvAccessToken = accessToken
    let tvRefreshToken = refresh_token || ''

    if (refresh_token) {
      try {
        const { data: refreshData, error: refreshError } = await adminClient.auth.admin.generateLink({
          type: 'magiclink',
          email: user.email!,
        })

        // If magic link works (email/password users), use it
        if (!refreshError && refreshData?.properties?.action_link) {
          const linkUrl = new URL(refreshData.properties.action_link)
          const token = linkUrl.searchParams.get('token')
          if (token) {
            const { data: verifyData, error: verifyError } = await adminClient.auth.verifyOtp({
              token_hash: token,
              type: 'magiclink',
            })
            if (!verifyError && verifyData.session) {
              tvAccessToken = verifyData.session.access_token
              tvRefreshToken = verifyData.session.refresh_token
              console.log(`Generated dedicated session for TV via magic link`)
            }
          }
        }
      } catch (e) {
        // Magic link approach failed (common for OAuth users) — fall through
        // and use the caller's tokens directly
        console.log(`Magic link generation failed (expected for OAuth users), using caller tokens`)
      }
    }

    // Update the code record with tokens
    const { error: updateError } = await adminClient
      .from('device_auth_codes')
      .update({
        status: 'claimed',
        auth_user_id: user.id,
        access_token: tvAccessToken,
        refresh_token: tvRefreshToken,
      })
      .eq('id', codeRecord.id)

    if (updateError) {
      console.error('Error updating code record:', updateError)
      return new Response(
        JSON.stringify({ error: 'Failed to complete pairing' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Code ${normalizedCode} claimed by ${user.id}`)

    return new Response(
      JSON.stringify({ success: true, message: 'TV paired successfully' }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
