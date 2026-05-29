/**
 * Edge Function: process-now-playing-event
 * Project: saturday-consumer-app
 * Description: Processes RFID now-playing events, resolves albums, and sends push notifications
 */

// Triggered by Database Webhook on now_playing_events INSERT
//
// This function:
// 1. Finds users who own the hub (via units.serial_number)
// 2. Resolves the EPC to album info
// 3. Inserts into user_now_playing_notifications
// 4. Sends push notifications via Firebase (for 'placed' events)

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendFcmPush } from '../_shared/send-fcm-push.ts'
import { buildNowPlayingPushArgs } from '../_shared/now-playing-push.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface WebhookPayload {
  type: 'INSERT' | 'UPDATE' | 'DELETE'
  table: string
  record: NowPlayingEventRecord
  schema: string
  old_record: null | NowPlayingEventRecord
}

interface NowPlayingEventRecord {
  id: string
  unit_id: string
  epc: string
  event_type: 'placed' | 'removed'
  rssi?: number
  duration_ms?: number
  timestamp: string
  created_at: string
}

interface DeviceInfo {
  id: string
  user_id: string
  name: string
}

interface AlbumInfo {
  library_album_id: string
  album_id: string
  title: string
  artist: string
  cover_image_url: string | null
  colors: Record<string, unknown> | null
  library_id: string
  library_name: string
}

interface PushToken {
  id: string
  user_id: string
  token: string
  platform: 'ios' | 'android'
  last_used_at: string | null
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
    console.log('Received webhook payload:', JSON.stringify(payload, null, 2))

    // Only process INSERT events
    if (payload.type !== 'INSERT') {
      return new Response(JSON.stringify({ skipped: true, reason: 'Not an INSERT' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const event = payload.record
    console.log('Processing event:', event)

    // Step 1: Find users who own this hub
    const devices = await findDevicesForHub(supabase, event.unit_id)

    if (devices.length === 0) {
      console.log('No devices found for hub:', event.unit_id)
      return new Response(JSON.stringify({ processed: 0, reason: 'No devices found' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    console.log('Found devices:', devices)

    // Step 1.5: Check for pending tag associations (hub-based tag identification)
    const userIds = [...new Set(devices.map(d => d.user_id))]
    await fulfillPendingAssociation(supabase, event.unit_id, event.epc, userIds)

    // Step 2: Resolve EPC to album info
    const albumInfo = await resolveEpcToAlbum(supabase, event.epc)
    console.log('Resolved album:', albumInfo)

    // Step 3: Create user notification records
    const notifications = await createUserNotifications(
      supabase,
      event,
      devices,
      albumInfo
    )
    console.log('Created notifications:', notifications.length)

    // Step 3.5: Update album location
    const hubUnitId = devices[0].id  // units.id from findDevicesForHub
    await updateAlbumLocation(supabase, event, hubUnitId, albumInfo)

    // Step 4: Send push notifications for placed events
    let pushResults: { user_id: string; success: boolean }[] = []
    if (event.event_type === 'placed') {
      pushResults = await sendPushNotifications(
        supabase,
        event,
        devices,
        albumInfo
      )
      console.log('Push results:', pushResults)
    }

    return new Response(
      JSON.stringify({
        processed: notifications.length,
        pushed: pushResults.length
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error processing event:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

async function findDevicesForHub(
  supabase: ReturnType<typeof createClient>,
  unitId: string
): Promise<DeviceInfo[]> {
  const { data, error } = await supabase
    .from('units')
    .select('id, consumer_user_id, consumer_name')
    .eq('serial_number', unitId)
    .not('consumer_user_id', 'is', null)

  if (error) throw error

  // Map units columns to DeviceInfo interface
  return (data || []).map((unit: { id: string; consumer_user_id: string; consumer_name: string }) => ({
    id: unit.id,
    user_id: unit.consumer_user_id,
    name: unit.consumer_name,
  }))
}

async function resolveEpcToAlbum(
  supabase: ReturnType<typeof createClient>,
  epc: string
): Promise<AlbumInfo | null> {
  // First, find the tag and its associated library album
  const { data: tag, error: tagError } = await supabase
    .from('rfid_tags')
    .select(`
      id,
      library_album_id,
      library_albums!inner (
        id,
        library_id,
        albums!inner (
          id,
          title,
          artist,
          cover_image_url,
          colors
        ),
        libraries!inner (
          id,
          name
        )
      )
    `)
    .eq('epc_identifier', epc)
    .single()

  if (tagError) {
    // Tag not found or not associated - this is expected for unknown tags
    if (tagError.code === 'PGRST116') {
      console.log('Tag not found for EPC:', epc)
      return null
    }
    throw tagError
  }

  if (!tag || !tag.library_album_id || !tag.library_albums) {
    console.log('Tag found but not associated with album:', epc)
    return null
  }

  const la = tag.library_albums as {
    id: string
    library_id: string
    albums: { id: string; title: string; artist: string; cover_image_url: string | null; colors: Record<string, unknown> | null }
    libraries: { id: string; name: string }
  }

  return {
    library_album_id: la.id,
    album_id: la.albums.id,
    title: la.albums.title,
    artist: la.albums.artist,
    cover_image_url: la.albums.cover_image_url,
    colors: la.albums.colors,
    library_id: la.library_id,
    library_name: la.libraries.name,
  }
}

async function createUserNotifications(
  supabase: ReturnType<typeof createClient>,
  event: NowPlayingEventRecord,
  devices: DeviceInfo[],
  albumInfo: AlbumInfo | null
): Promise<{ user_id: string }[]> {
  // Deduplicate users (in case same user has multiple hubs with same serial - unlikely but safe)
  const uniqueUsers = [...new Map(devices.map(d => [d.user_id, d])).values()]

  const notifications = uniqueUsers.map(device => ({
    user_id: device.user_id,
    source_event_id: event.id,
    unit_id: event.unit_id,
    epc: event.epc,
    event_type: event.event_type,
    library_album_id: albumInfo?.library_album_id || null,
    album_title: albumInfo?.title || null,
    album_artist: albumInfo?.artist || null,
    cover_image_url: albumInfo?.cover_image_url || null,
    album_colors: albumInfo?.colors || null,
    library_id: albumInfo?.library_id || null,
    library_name: albumInfo?.library_name || null,
    device_id: device.id,
    device_name: device.name,
    event_timestamp: event.timestamp,
  }))

  const { error } = await supabase
    .from('user_now_playing_notifications')
    .upsert(notifications, {
      onConflict: 'source_event_id,user_id',
      ignoreDuplicates: true
    })

  if (error) throw error

  return notifications.map(n => ({ user_id: n.user_id }))
}

async function updateAlbumLocation(
  supabase: ReturnType<typeof createClient>,
  event: NowPlayingEventRecord,
  unitId: string,
  albumInfo: AlbumInfo | null
): Promise<void> {
  if (!albumInfo) {
    console.log('No album info, skipping location update')
    return
  }

  try {
    if (event.event_type === 'placed') {
      // Close any existing open location for this album on this device (defensive)
      await supabase
        .from('album_locations')
        .update({ removed_at: event.timestamp })
        .eq('library_album_id', albumInfo.library_album_id)
        .eq('device_id', unitId)
        .is('removed_at', null)

      // Insert new location record
      const { error } = await supabase
        .from('album_locations')
        .insert({
          library_album_id: albumInfo.library_album_id,
          device_id: unitId,
          detected_at: event.timestamp,
        })

      if (error) {
        console.error('Error inserting album location:', error)
      } else {
        console.log('Album location created: placed on', unitId)
      }
    } else if (event.event_type === 'removed') {
      const { error } = await supabase
        .from('album_locations')
        .update({ removed_at: event.timestamp })
        .eq('library_album_id', albumInfo.library_album_id)
        .eq('device_id', unitId)
        .is('removed_at', null)

      if (error) {
        console.error('Error updating album location:', error)
      } else {
        console.log('Album location updated: removed from', unitId)
      }
    }
  } catch (error) {
    // Don't let location tracking failures block the main pipeline
    console.error('Album location update failed:', error)
  }
}

async function sendPushNotifications(
  supabase: ReturnType<typeof createClient>,
  event: NowPlayingEventRecord,
  devices: DeviceInfo[],
  albumInfo: AlbumInfo | null
): Promise<{ user_id: string; success: boolean }[]> {
  const results: { user_id: string; success: boolean }[] = []

  // Get unique user IDs
  const userIds = [...new Set(devices.map(d => d.user_id))]

  for (const userId of userIds) {
    const device = devices.find(d => d.user_id === userId)!

    // Get active push tokens for this user
    const { data: tokens } = await supabase
      .from('push_notification_tokens')
      .select('*')
      .eq('user_id', userId)
      .eq('is_active', true) as { data: PushToken[] | null }

    if (!tokens || tokens.length === 0) {
      console.log('No push tokens for user:', userId)
      continue
    }

    // Always send push notifications - the app handles foreground notifications gracefully
    // (Firebase delivers to onMessage handler without showing system notification when app is open)

    // Send push to all tokens for this user via the shared FCM primitive.
    for (const token of tokens) {
      const result = await sendFcmPush(
        buildNowPlayingPushArgs({
          tokenString: token.token,
          albumInfo,
          deviceName: device.name,
        }),
      )

      if (result.success) {
        await supabase.from('notification_delivery_log').insert({
          user_id: userId,
          notification_type: 'now_playing',
          source_id: event.id,
          token_id: token.id,
          status: 'sent',
          sent_at: new Date().toISOString(),
        })
        results.push({ user_id: userId, success: true })
      } else {
        console.error(
          `Push failed for token ${token.id} (${result.errorCategory}):`,
          result.error,
        )

        await supabase.from('notification_delivery_log').insert({
          user_id: userId,
          notification_type: 'now_playing',
          source_id: event.id,
          token_id: token.id,
          status: 'failed',
          error_message: result.error,
        })

        if (result.tokenShouldDeactivate) {
          await supabase
            .from('push_notification_tokens')
            .update({ is_active: false })
            .eq('id', token.id)
        }

        results.push({ user_id: userId, success: false })
      }
    }
  }

  return results
}

async function fulfillPendingAssociation(
  supabase: ReturnType<typeof createClient>,
  unitId: string,
  epc: string,
  userIds: string[]
): Promise<void> {
  if (userIds.length === 0) return

  try {
    // Find pending association requests for this hub from any of its owners
    const { data: pending, error: findError } = await supabase
      .from('pending_tag_associations')
      .select('id, user_id')
      .eq('unit_id', unitId)
      .eq('status', 'pending')
      .in('user_id', userIds)
      .limit(1)
      .maybeSingle()

    if (findError) {
      console.error('Error checking pending associations:', findError)
      return
    }

    if (!pending) {
      return
    }

    console.log('Fulfilling pending tag association:', pending.id, 'with EPC:', epc)

    const { error: updateError } = await supabase
      .from('pending_tag_associations')
      .update({
        status: 'fulfilled',
        detected_epc: epc,
        fulfilled_at: new Date().toISOString(),
      })
      .eq('id', pending.id)
      .eq('status', 'pending')  // guard against race condition

    if (updateError) {
      console.error('Error fulfilling pending association:', updateError)
    } else {
      console.log('Pending tag association fulfilled:', pending.id)
    }
  } catch (error) {
    // Don't let pending association failures block normal now-playing processing
    console.error('Pending association check failed:', error)
  }
}
