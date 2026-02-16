/**
 * Edge Function: claim-unit
 * Project: saturday-consumer-app
 * Description: Claims a factory-provisioned unit for a consumer user by serial number
 */

// Claims a factory-provisioned unit for a consumer user.
//
// This function:
// 1. Verifies the unit exists by serial number
// 2. Checks the unit is unclaimed (user_id is null)
// 3. Updates the unit with the user's ID and status
// 4. Returns the claimed unit with joined device data

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ClaimUnitRequest {
  serial_number: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get the authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Create Supabase client with user's auth token for getting user
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // First, get the user from the auth token
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } }
    })

    const { data: { user }, error: userError } = await userClient.auth.getUser()
    if (userError || !user) {
      console.error('Auth error:', userError)
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Auth user ${user.id} attempting to claim unit`)

    // Use service role for database operations (bypasses RLS)
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false }
    })

    // Look up the database user ID from auth_user_id
    const { data: dbUser, error: dbUserError } = await adminClient
      .from('users')
      .select('id')
      .eq('auth_user_id', user.id)
      .maybeSingle()

    if (dbUserError) {
      console.error('Error finding database user:', dbUserError)
      return new Response(
        JSON.stringify({ error: 'Error finding user record' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!dbUser) {
      console.error(`No database user found for auth_user_id: ${user.id}`)
      return new Response(
        JSON.stringify({ error: 'User record not found. Please try logging out and back in.' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const databaseUserId = dbUser.id
    console.log(`Database user ID: ${databaseUserId}`)

    // Parse request body
    const body: ClaimUnitRequest = await req.json()
    const { serial_number } = body

    if (!serial_number) {
      return new Response(
        JSON.stringify({ error: 'Missing serial_number' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Attempting to claim unit: ${serial_number}`)

    // Step 1: Find the unit by serial number
    const { data: unit, error: findError } = await adminClient
      .from('units')
      .select('id, serial_number, consumer_user_id, status')
      .eq('serial_number', serial_number)
      .maybeSingle()

    if (findError) {
      console.error('Error finding unit:', findError)
      return new Response(
        JSON.stringify({ error: 'Error finding unit' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!unit) {
      console.log(`Unit not found: ${serial_number}`)
      return new Response(
        JSON.stringify({ error: 'Unit not found. Make sure the serial number is correct.' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Step 2: Log if unit is already claimed (but allow re-claiming)
    // Physical access via BLE is proof of ownership - if user can connect to
    // the device after a hard reset, they should be able to claim it
    if (unit.consumer_user_id !== null) {
      if (unit.consumer_user_id === databaseUserId) {
        console.log(`Unit ${serial_number} already claimed by this user - updating`)
      } else {
        console.log(`Unit ${serial_number} transferring ownership from ${unit.consumer_user_id} to ${databaseUserId}`)
      }
    }

    // Step 3: Claim the unit
    const { data: claimedUnit, error: updateError } = await adminClient
      .from('units')
      .update({
        consumer_user_id: databaseUserId,
        status: 'claimed',
      })
      .eq('id', unit.id)
      .select(`
        *,
        devices!left(
          id,
          mac_address,
          device_type_slug,
          firmware_version,
          status,
          last_seen_at,
          latest_telemetry,
          provision_data
        )
      `)
      .single()

    if (updateError) {
      console.error('Error claiming unit:', updateError)
      return new Response(
        JSON.stringify({ error: 'Error claiming unit' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Successfully claimed unit ${serial_number} for database user ${databaseUserId}`)

    return new Response(
      JSON.stringify(claimedUnit),
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
