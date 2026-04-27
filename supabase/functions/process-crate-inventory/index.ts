/**
 * Edge Function: process-crate-inventory
 * Project: saturday-consumer-app
 * Description: Processes crate RFID inventory snapshots and updates album_locations.
 *              Compares current snapshot against tracked locations to detect
 *              arrivals (new albums in crate) and departures (albums removed).
 */

// Triggered by Database Webhook on crate_inventory_events INSERT
//
// This function:
// 1. Resolves the crate MAC address to a units.id via the devices table
// 2. Batch-resolves EPCs to library_album_ids via rfid_tags
// 3. Diffs against current album_locations for this crate
// 4. Inserts new locations for arrivals, closes locations for departures

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface WebhookPayload {
  type: 'INSERT' | 'UPDATE' | 'DELETE'
  table: string
  record: CrateInventoryEventRecord
  schema: string
  old_record: null | CrateInventoryEventRecord
}

interface CrateInventoryEventRecord {
  id: string
  unit_id: string        // Hub serial number that relayed the event
  mac_address: string    // Crate WiFi MAC (AA:BB:CC:DD:EE:FF)
  epcs: string[]         // Array of EPC strings currently in the crate
  epc_count: number
  timestamp: string
  created_at: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Verify service role authorization
    const authHeader = req.headers.get('Authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      throw new Error('Missing authorization')
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false }
    })

    // Parse webhook payload
    const payload: WebhookPayload = await req.json()
    console.log('Received crate inventory webhook:', JSON.stringify(payload, null, 2))

    // Only process INSERT events
    if (payload.type !== 'INSERT') {
      return new Response(JSON.stringify({ skipped: true, reason: 'Not an INSERT' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const event = payload.record
    console.log('Processing crate inventory:', event.mac_address, 'with', event.epc_count, 'EPCs')

    // Step 1: Resolve crate MAC to units.id
    const crateUnitId = await resolveCrateToUnitId(supabase, event.mac_address)

    if (!crateUnitId) {
      console.log('No device found for crate MAC:', event.mac_address)
      return new Response(JSON.stringify({ processed: 0, reason: 'Unknown crate' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    console.log('Resolved crate to unit:', crateUnitId)

    // Step 2: Batch resolve EPCs to library_album_ids
    const epcToAlbum = await batchResolveEpcs(supabase, event.epcs)
    console.log('Resolved', epcToAlbum.size, 'of', event.epcs.length, 'EPCs to albums')

    // Step 3: Get currently tracked albums in this crate
    const currentLocations = await getCurrentLocations(supabase, crateUnitId)
    const currentAlbumIds = new Set(currentLocations.map(l => l.library_album_id))
    console.log('Currently tracked albums in crate:', currentAlbumIds.size)

    // Step 4: Diff — determine arrivals and departures
    const snapshotAlbumIds = new Set(epcToAlbum.values())

    const arrivals = [...snapshotAlbumIds].filter(id => !currentAlbumIds.has(id))
    const departures = [...currentAlbumIds].filter(id => !snapshotAlbumIds.has(id))

    console.log('Arrivals:', arrivals.length, 'Departures:', departures.length)

    // Step 5: Insert new locations for arrivals
    if (arrivals.length > 0) {
      const { error } = await supabase
        .from('album_locations')
        .insert(arrivals.map(libraryAlbumId => ({
          library_album_id: libraryAlbumId,
          device_id: crateUnitId,
          detected_at: event.timestamp,
        })))

      if (error) {
        console.error('Error inserting arrival locations:', error)
      } else {
        console.log('Inserted', arrivals.length, 'arrival locations')
      }
    }

    // Step 6: Close locations for departures
    if (departures.length > 0) {
      const { error } = await supabase
        .from('album_locations')
        .update({ removed_at: event.timestamp })
        .eq('device_id', crateUnitId)
        .in('library_album_id', departures)
        .is('removed_at', null)

      if (error) {
        console.error('Error closing departure locations:', error)
      } else {
        console.log('Closed', departures.length, 'departure locations')
      }
    }

    return new Response(
      JSON.stringify({
        crate: event.mac_address,
        resolved_epcs: epcToAlbum.size,
        arrivals: arrivals.length,
        departures: departures.length,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error processing crate inventory:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

/**
 * Resolve a crate's MAC address to a units.id via the devices table.
 * Chain: devices.mac_address → devices.unit_id (which is units.id)
 */
async function resolveCrateToUnitId(
  supabase: ReturnType<typeof createClient>,
  macAddress: string
): Promise<string | null> {
  const { data, error } = await supabase
    .from('devices')
    .select('unit_id')
    .eq('mac_address', macAddress)
    .not('unit_id', 'is', null)
    .maybeSingle()

  if (error) {
    console.error('Error resolving crate MAC:', error)
    return null
  }

  return data?.unit_id ?? null
}

/**
 * Batch resolve EPCs to library_album_ids via rfid_tags.
 * Returns a Map<epc, library_album_id> for all resolved tags.
 */
async function batchResolveEpcs(
  supabase: ReturnType<typeof createClient>,
  epcs: string[]
): Promise<Map<string, string>> {
  if (epcs.length === 0) return new Map()

  const { data, error } = await supabase
    .from('rfid_tags')
    .select('epc_identifier, library_album_id')
    .in('epc_identifier', epcs)
    .not('library_album_id', 'is', null)

  if (error) {
    console.error('Error resolving EPCs:', error)
    return new Map()
  }

  const result = new Map<string, string>()
  for (const tag of data || []) {
    result.set(tag.epc_identifier, tag.library_album_id)
  }
  return result
}

/**
 * Get all currently-tracked album locations for a specific crate (device).
 * Returns records where removed_at IS NULL.
 */
async function getCurrentLocations(
  supabase: ReturnType<typeof createClient>,
  deviceId: string
): Promise<{ id: string; library_album_id: string }[]> {
  const { data, error } = await supabase
    .from('album_locations')
    .select('id, library_album_id')
    .eq('device_id', deviceId)
    .is('removed_at', null)

  if (error) {
    console.error('Error fetching current locations:', error)
    return []
  }

  return data || []
}
