// Edge Function: unclaim-unit
//
// Releases a unit back to factory state, removing user ownership.
//
// This function:
// 1. Verifies the user owns the unit
// 2. Clears user_id, device_name, consumer_provisioned_at on the unit
// 3. Clears provision_data on the linked device
// 4. Updates unit status to 'factory_provisioned'

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface UnclaimUnitRequest {
  unit_id: string
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

    console.log(`Auth user ${user.id} attempting to unclaim unit`)

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
        JSON.stringify({ error: 'User record not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const databaseUserId = dbUser.id
    console.log(`Database user ID: ${databaseUserId}`)

    // Parse request body
    const body: UnclaimUnitRequest = await req.json()
    const { unit_id } = body

    if (!unit_id) {
      return new Response(
        JSON.stringify({ error: 'Missing unit_id' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Attempting to unclaim unit: ${unit_id}`)

    // Step 1: Find the unit with its linked device and verify ownership
    const { data: unit, error: findError } = await adminClient
      .from('units')
      .select('id, serial_number, consumer_user_id, status, devices!left(id)')
      .eq('id', unit_id)
      .maybeSingle()

    if (findError) {
      console.error('Error finding unit:', findError)
      return new Response(
        JSON.stringify({ error: 'Error finding unit' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!unit) {
      console.log(`Unit not found: ${unit_id}`)
      return new Response(
        JSON.stringify({ error: 'Unit not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Step 2: Verify ownership
    if (unit.consumer_user_id !== databaseUserId) {
      console.log(`User ${databaseUserId} does not own unit ${unit_id}`)
      return new Response(
        JSON.stringify({ error: 'You do not own this device' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Step 3: Unclaim the unit (clear consumer-specific data)
    const { error: updateError } = await adminClient
      .from('units')
      .update({
        consumer_user_id: null,
        consumer_name: null,
        status: 'inventory',
      })
      .eq('id', unit.id)

    if (updateError) {
      console.error('Error unclaiming unit:', updateError)
      return new Response(
        JSON.stringify({ error: 'Error unclaiming unit' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Step 4: Clear consumer provisioning data on the linked device (if exists)
    const devices = unit.devices as { id: string }[] | null
    if (devices && devices.length > 0) {
      const deviceId = devices[0].id
      console.log(`Clearing consumer provisioning data on device: ${deviceId}`)

      const { error: deviceUpdateError } = await adminClient
        .from('devices')
        .update({
          provision_data: null,
          consumer_provisioned_at: null,
          consumer_provisioned_by: null,
        })
        .eq('id', deviceId)

      if (deviceUpdateError) {
        console.error('Error clearing device consumer data:', deviceUpdateError)
        // Don't fail the whole operation, just log the error
      }
    }

    console.log(`Successfully unclaimed unit ${unit.serial_number}`)

    // Clean up any device status notifications for this unit
    await adminClient
      .from('device_status_notifications')
      .delete()
      .eq('unit_id', unit.id)
      .eq('user_id', databaseUserId)

    return new Response(
      JSON.stringify({ success: true, serial_number: unit.serial_number }),
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
