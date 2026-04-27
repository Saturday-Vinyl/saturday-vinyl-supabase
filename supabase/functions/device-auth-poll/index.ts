/**
 * Edge Function: device-auth-poll
 * Project: shared
 * Description: Polls the status of a device pairing code.
 *              Returns 'pending', 'complete' (with tokens), or 'expired'.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface PollRequest {
  device_code: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false }
    })

    const body: PollRequest = await req.json()
    const { device_code } = body

    if (!device_code) {
      return new Response(
        JSON.stringify({ error: 'Missing device_code' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Look up the code
    const { data: codeRecord, error } = await adminClient
      .from('device_auth_codes')
      .select('*')
      .eq('device_code', device_code)
      .maybeSingle()

    if (error || !codeRecord) {
      return new Response(
        JSON.stringify({ status: 'expired' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check expiry
    if (new Date(codeRecord.expires_at) < new Date()) {
      // Mark as expired
      await adminClient
        .from('device_auth_codes')
        .update({ status: 'expired' })
        .eq('id', codeRecord.id)

      return new Response(
        JSON.stringify({ status: 'expired' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Check if claimed
    if (codeRecord.status === 'claimed' && codeRecord.access_token) {
      return new Response(
        JSON.stringify({
          status: 'complete',
          access_token: codeRecord.access_token,
          refresh_token: codeRecord.refresh_token,
        }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Still pending
    return new Response(
      JSON.stringify({ status: 'pending' }),
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
