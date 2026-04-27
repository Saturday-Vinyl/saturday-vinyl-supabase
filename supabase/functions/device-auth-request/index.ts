/**
 * Edge Function: device-auth-request
 * Project: shared
 * Description: Generates a short pairing code for device authentication (e.g., Apple TV).
 *              The device displays this code and the user enters it on their phone/computer.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Characters that are unambiguous when displayed on a TV screen
// Excludes: 0/O, 1/I/L, 2/Z, 5/S, 8/B
const CODE_CHARS = 'ACDEFGHJKMNPQRTUVWXY34679'
const CODE_LENGTH = 6
const CODE_EXPIRY_SECONDS = 300 // 5 minutes

function generateCode(): string {
  const chars: string[] = []
  for (let i = 0; i < CODE_LENGTH; i++) {
    chars.push(CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)])
  }
  return chars.join('')
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

    // Generate a unique code (retry on collision)
    let code: string = ''
    let attempts = 0
    const maxAttempts = 5

    while (attempts < maxAttempts) {
      code = generateCode()

      // Clean up expired codes first
      await adminClient
        .from('device_auth_codes')
        .update({ status: 'expired' })
        .eq('status', 'pending')
        .lt('expires_at', new Date().toISOString())

      // Try to insert
      const { error } = await adminClient
        .from('device_auth_codes')
        .insert({
          device_code: code,
          user_code: code,
          status: 'pending',
          expires_at: new Date(Date.now() + CODE_EXPIRY_SECONDS * 1000).toISOString(),
        })

      if (!error) break
      attempts++
    }

    if (!code || attempts >= maxAttempts) {
      return new Response(
        JSON.stringify({ error: 'Failed to generate a unique code. Please try again.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Generated device code: ${code}`)

    return new Response(
      JSON.stringify({
        device_code: code,
        user_code: code,
        verification_url: 'https://saturday.vinyl/pair',
        expires_in: CODE_EXPIRY_SECONDS,
      }),
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
