/**
 * Edge Function: process-now-playing-event
 * Project: saturday-consumer-app
 * Description: Processes RFID now-playing events, resolves albums, and sends push notifications
 */

// Triggered by Database Webhook on now_playing_events INSERT
//
// This function:
// 1. Finds users who own the hub (via consumer_devices.serial_number)
// 2. Resolves the EPC to album info
// 3. Inserts into user_now_playing_notifications
// 4. Sends push notifications via Firebase (for 'placed' events)

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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
    .from('consumer_devices')
    .select('id, user_id, name')
    .eq('serial_number', unitId)
    .eq('device_type', 'hub')

  if (error) throw error
  return data || []
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
          cover_image_url
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
    albums: { id: string; title: string; artist: string; cover_image_url: string | null }
    libraries: { id: string; name: string }
  }

  return {
    library_album_id: la.id,
    album_id: la.albums.id,
    title: la.albums.title,
    artist: la.albums.artist,
    cover_image_url: la.albums.cover_image_url,
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

    // Send push to all tokens for this user
    for (const token of tokens) {
      try {
        await sendFirebasePush(token, albumInfo, device.name)

        // Log success
        await supabase.from('notification_delivery_log').insert({
          user_id: userId,
          notification_type: 'now_playing',
          source_id: event.id,
          token_id: token.id,
          status: 'sent',
          sent_at: new Date().toISOString(),
        })

        results.push({ user_id: userId, success: true })
      } catch (error) {
        console.error('Push failed for token:', token.id, error)

        // Log failure
        await supabase.from('notification_delivery_log').insert({
          user_id: userId,
          notification_type: 'now_playing',
          source_id: event.id,
          token_id: token.id,
          status: 'failed',
          error_message: (error as Error).message,
        })

        // Mark token as inactive if it's invalid
        const errorMsg = (error as Error).message.toLowerCase()
        if (errorMsg.includes('invalid') || errorMsg.includes('unregistered')) {
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

async function sendFirebasePush(
  token: PushToken,
  albumInfo: AlbumInfo | null,
  deviceName: string
): Promise<void> {
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID')
  const rawPrivateKey = Deno.env.get('FIREBASE_PRIVATE_KEY')
  const privateKey = rawPrivateKey?.replace(/\\n/g, '\n')
  const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL')

  if (!projectId || !privateKey || !clientEmail) {
    console.log('Firebase not configured, skipping push')
    return
  }

  // Build notification content
  const title = albumInfo?.title
    ? `Now Playing: ${albumInfo.title}`
    : 'Record Detected'

  const body = albumInfo?.artist
    ? `${albumInfo.artist} on ${deviceName}`
    : `A record was placed on ${deviceName}`

  // Get OAuth2 access token for Firebase
  const accessToken = await getFirebaseAccessToken(privateKey, clientEmail)

  // Send via Firebase Cloud Messaging v1 API
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  const response = await fetch(
    fcmUrl,
    {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: token.token,
          notification: {
            title,
            body,
          },
          data: {
            type: 'now_playing',
            library_album_id: albumInfo?.library_album_id || '',
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
          },
          android: {
            priority: 'high',
            notification: {
              channel_id: 'now_playing',
              sound: 'default',
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
                badge: 1,
              },
            },
          },
        },
      }),
    }
  )

  if (!response.ok) {
    const errorBody = await response.text()
    throw new Error(`Firebase push failed: ${response.status} - ${errorBody}`)
  }
}

async function getFirebaseAccessToken(
  privateKey: string,
  clientEmail: string
): Promise<string> {
  // Create JWT for service account authentication
  const now = Math.floor(Date.now() / 1000)
  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: clientEmail,
    sub: clientEmail,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }

  // Encode header and payload
  const encodedHeader = btoa(JSON.stringify(header))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')
  const encodedPayload = btoa(JSON.stringify(payload))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')

  // Sign with private key
  const signatureInput = `${encodedHeader}.${encodedPayload}`
  const encoder = new TextEncoder()
  const data = encoder.encode(signatureInput)

  // Import private key and sign
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, data)
  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')

  const jwt = `${signatureInput}.${encodedSignature}`

  // Exchange JWT for access token
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  if (!tokenResponse.ok) {
    const errorText = await tokenResponse.text()
    throw new Error(`Failed to get Firebase access token: ${tokenResponse.status} - ${errorText}`)
  }

  const tokenData = await tokenResponse.json()
  return tokenData.access_token
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')

  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes.buffer
}
