// Edge Function: check-device-status
// Triggered by cron job (every 1 minute)
//
// This function:
// 1. Finds devices that went offline (no heartbeat for 10 min)
// 2. Finds devices with low battery (<20%)
// 3. Finds devices that recovered (came back online)
// 4. Sends push notifications for each, respecting user preferences
//
// Note: devices.last_seen_at is kept in sync by a database trigger
// (sync_heartbeat_to_device) that fires on each insert to device_heartbeats.
// This allows efficient queries without needing to join the heartbeats table.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendPushNotification } from '../_shared/send-push.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Thresholds
const OFFLINE_THRESHOLD_MINUTES = 10
const BATTERY_LOW_THRESHOLD = 20
const BATTERY_RECOVERY_THRESHOLD = 30 // Must go above this to re-notify
const NOTIFICATION_COOLDOWN_HOURS = 24 // Don't re-notify for offline within this window
const BATTERY_NOTIFICATION_COOLDOWN_HOURS = 12

// Flattened view of a claimed unit with its linked device data.
// Built from: units LEFT JOIN devices
interface UnitWithDevice {
  id: string                    // unit.id (used as primary identifier)
  consumer_user_id: string      // unit.consumer_user_id (database user ID)
  consumer_name: string         // unit.consumer_name (user-assigned name)
  device_type: 'hub' | 'crate' // derived from serial_number prefix
  serial_number: string         // unit.serial_number
  status: string                // unit.status (unit_status enum)
  last_seen_at: string | null   // devices.last_seen_at (synced from heartbeats)
  battery_level: number | null  // devices.latest_telemetry.battery_level
}

/**
 * Transform a joined units+devices row into a flat UnitWithDevice.
 * The devices relation comes back as an array (even with !inner) from Supabase.
 */
function transformUnitRow(unit: any): UnitWithDevice {
  const device = Array.isArray(unit.devices) ? unit.devices[0] : unit.devices
  return {
    id: unit.id,
    consumer_user_id: unit.consumer_user_id,
    consumer_name: unit.consumer_name ?? unit.serial_number,
    serial_number: unit.serial_number,
    status: unit.status,
    device_type: unit.serial_number?.startsWith('SV-HUB') ? 'hub' : 'crate',
    last_seen_at: device?.last_seen_at ?? null,
    battery_level: device?.latest_telemetry?.battery_level ?? null,
  }
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false }
    })

    console.log('Starting device status check...')

    // Get counts for logging
    const results = {
      offline: { checked: 0, notified: 0 },
      battery_low: { checked: 0, notified: 0 },
      online: { checked: 0, notified: 0 },
    }

    // Step 1: Find and notify for newly offline devices
    const offlineDevices = await findNewlyOfflineDevices(supabase)
    results.offline.checked = offlineDevices.length
    console.log(`Found ${offlineDevices.length} newly offline devices`)

    for (const device of offlineDevices) {
      const sent = await sendDeviceOfflineNotification(supabase, device)
      if (sent) results.offline.notified++
    }

    // Step 2: Find and notify for low battery devices
    const lowBatteryDevices = await findNewlyLowBatteryDevices(supabase)
    results.battery_low.checked = lowBatteryDevices.length
    console.log(`Found ${lowBatteryDevices.length} low battery devices`)

    for (const device of lowBatteryDevices) {
      const sent = await sendBatteryLowNotification(supabase, device)
      if (sent) results.battery_low.notified++
    }

    // Step 3: Find and notify for recovered devices
    const recoveredDevices = await findRecoveredDevices(supabase)
    results.online.checked = recoveredDevices.length
    console.log(`Found ${recoveredDevices.length} recovered devices`)

    for (const device of recoveredDevices) {
      const sent = await sendDeviceOnlineNotification(supabase, device)
      if (sent) results.online.notified++
    }

    console.log('Device status check complete:', results)

    return new Response(
      JSON.stringify({ success: true, results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error checking device status:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

/**
 * Find units whose linked device has gone offline (no heartbeat for 10+ minutes)
 * and haven't been notified in the last 24 hours.
 */
async function findNewlyOfflineDevices(supabase: SupabaseClient): Promise<UnitWithDevice[]> {
  const offlineThreshold = new Date(Date.now() - OFFLINE_THRESHOLD_MINUTES * 60 * 1000)
  const cooldownThreshold = new Date(Date.now() - NOTIFICATION_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString()
  const offlineThresholdStr = offlineThreshold.toISOString()

  // Query claimed units with linked devices that:
  // 1. Have a last_seen_at (have sent at least one heartbeat)
  // 2. Last heartbeat is older than threshold (offline)
  // 3. Device is not already marked as offline
  const { data: units, error } = await supabase
    .from('units')
    .select(`
      id,
      consumer_user_id,
      consumer_name,
      serial_number,
      status,
      devices!inner (
        last_seen_at,
        status,
        latest_telemetry
      )
    `)
    .not('consumer_user_id', 'is', null)
    .not('devices.last_seen_at', 'is', null)
    .lt('devices.last_seen_at', offlineThresholdStr)
    .neq('devices.status', 'offline')

  if (error) {
    console.error('Error fetching offline devices:', error)
    return []
  }

  const transformed = (units || []).map(transformUnitRow)
  console.log(`Found ${transformed.length} units with stale heartbeats (threshold: ${offlineThresholdStr})`)

  if (transformed.length === 0) {
    return []
  }

  // Filter out units that were already notified recently
  const unitIds = transformed.map(d => d.id)
  const { data: recentNotifications } = await supabase
    .from('device_status_notifications')
    .select('unit_id')
    .in('unit_id', unitIds)
    .eq('notification_type', 'device_offline')
    .gt('last_sent_at', cooldownThreshold)

  const recentlyNotifiedIds = new Set((recentNotifications || []).map(n => n.unit_id))

  return transformed.filter(d => !recentlyNotifiedIds.has(d.id))
}

/**
 * Find units with linked devices that have low battery (<20%)
 * and haven't been notified recently.
 */
async function findNewlyLowBatteryDevices(supabase: SupabaseClient): Promise<UnitWithDevice[]> {
  const cooldownThreshold = new Date(Date.now() - BATTERY_NOTIFICATION_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString()

  // Query claimed units with linked devices
  // Battery level is in devices.latest_telemetry (JSONB), so we filter in application code
  const { data: units, error } = await supabase
    .from('units')
    .select(`
      id,
      consumer_user_id,
      consumer_name,
      serial_number,
      status,
      devices!inner (
        last_seen_at,
        latest_telemetry
      )
    `)
    .not('consumer_user_id', 'is', null)

  if (error) {
    console.error('Error finding low battery devices:', error)
    return []
  }

  // Transform and filter for low battery in application code
  const lowBattery = (units || [])
    .map(transformUnitRow)
    .filter(u => u.battery_level !== null && u.battery_level < BATTERY_LOW_THRESHOLD)

  if (lowBattery.length === 0) {
    return []
  }

  // Get recent battery notifications to check cooldown and recovery
  const unitIds = lowBattery.map(d => d.id)
  const { data: recentNotifications } = await supabase
    .from('device_status_notifications')
    .select('unit_id, last_sent_at, context_data')
    .in('unit_id', unitIds)
    .eq('notification_type', 'battery_low')

  const notificationMap = new Map(
    (recentNotifications || []).map(n => [n.unit_id, n])
  )

  // Filter based on cooldown and whether battery recovered since last notification
  return lowBattery.filter(device => {
    const lastNotif = notificationMap.get(device.id)
    if (!lastNotif) {
      // Never notified, should notify
      return true
    }

    // Check if within cooldown
    if (new Date(lastNotif.last_sent_at) > new Date(cooldownThreshold)) {
      // Within cooldown - only notify if battery went above recovery threshold since
      const lastNotifiedLevel = lastNotif.context_data?.battery_level as number | undefined
      if (lastNotifiedLevel !== undefined && lastNotifiedLevel < BATTERY_RECOVERY_THRESHOLD) {
        // Battery was low and hasn't recovered above threshold
        return false
      }
    }

    return true
  })
}

/**
 * Find units whose linked device has recovered (came back online after being offline).
 *
 * A device is considered "recovered" if:
 * 1. It has a recent heartbeat (within 2 minutes)
 * 2. We previously sent a device_offline notification for it (in the last 24h)
 * 3. We haven't already sent a device_online notification after that offline notification
 */
async function findRecoveredDevices(supabase: SupabaseClient): Promise<UnitWithDevice[]> {
  const recentThreshold = new Date(Date.now() - 2 * 60 * 1000)
  const recentThresholdStr = recentThreshold.toISOString()
  const cooldownThreshold = new Date(Date.now() - NOTIFICATION_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString()

  // Query claimed units with recent heartbeats
  const { data: units, error } = await supabase
    .from('units')
    .select(`
      id,
      consumer_user_id,
      consumer_name,
      serial_number,
      status,
      devices!inner (
        last_seen_at,
        latest_telemetry
      )
    `)
    .not('consumer_user_id', 'is', null)
    .not('devices.last_seen_at', 'is', null)
    .gt('devices.last_seen_at', recentThresholdStr)

  if (error) {
    console.error('Error fetching recently active devices:', error)
    return []
  }

  const transformed = (units || []).map(transformUnitRow)

  if (transformed.length === 0) {
    return []
  }

  // Find units that have an offline notification from the last 24h
  const unitIds = transformed.map(d => d.id)
  const { data: offlineNotifications } = await supabase
    .from('device_status_notifications')
    .select('unit_id, last_sent_at')
    .in('unit_id', unitIds)
    .eq('notification_type', 'device_offline')
    .gt('last_sent_at', cooldownThreshold)

  const offlineUnitIds = new Set((offlineNotifications || []).map(n => n.unit_id))

  if (offlineUnitIds.size === 0) {
    // No units had offline notifications, so no recoveries to report
    return []
  }

  // Also check we haven't already sent an online notification for this recovery
  const { data: onlineNotifications } = await supabase
    .from('device_status_notifications')
    .select('unit_id, last_sent_at')
    .in('unit_id', Array.from(offlineUnitIds))
    .eq('notification_type', 'device_online')

  // Build a map of online notification times
  const onlineNotifMap = new Map(
    (onlineNotifications || []).map(n => [n.unit_id, new Date(n.last_sent_at)])
  )

  // Only include units where offline notification is more recent than online notification
  return transformed.filter(device => {
    if (!offlineUnitIds.has(device.id)) {
      return false
    }

    const offlineNotif = offlineNotifications?.find(n => n.unit_id === device.id)
    const onlineNotifTime = onlineNotifMap.get(device.id)

    if (onlineNotifTime && offlineNotif) {
      // Only notify if we haven't already sent an online notification after the offline one
      return onlineNotifTime < new Date(offlineNotif.last_sent_at)
    }

    return true
  })
}

/**
 * Send device offline notification and track it.
 */
async function sendDeviceOfflineNotification(
  supabase: SupabaseClient,
  device: UnitWithDevice
): Promise<boolean> {
  const result = await sendPushNotification(
    supabase,
    device.consumer_user_id,
    {
      type: 'device_offline',
      title: `${device.consumer_name} is offline`,
      body: `Your ${device.device_type === 'hub' ? 'Saturday Hub' : 'Storage Crate'} hasn't been seen for a while. Check the connection.`,
      data: {
        device_id: device.id,
        device_name: device.consumer_name,
        device_type: device.device_type,
      },
      channelId: 'device_alerts',
    },
    device.id
  )

  if (result.sent > 0 || result.skipped === 'no_tokens') {
    // Track the notification (keyed by unit_id)
    await supabase
      .from('device_status_notifications')
      .upsert({
        unit_id: device.id,
        user_id: device.consumer_user_id,
        notification_type: 'device_offline',
        last_sent_at: new Date().toISOString(),
        context_data: { last_seen_at: device.last_seen_at },
      }, {
        onConflict: 'unit_id,notification_type',
      })
  }

  return result.sent > 0
}

/**
 * Send battery low notification and track it.
 */
async function sendBatteryLowNotification(
  supabase: SupabaseClient,
  device: UnitWithDevice
): Promise<boolean> {
  const result = await sendPushNotification(
    supabase,
    device.consumer_user_id,
    {
      type: 'battery_low',
      title: `${device.consumer_name} battery low`,
      body: `Battery is at ${device.battery_level}%. Charge your ${device.device_type === 'crate' ? 'Storage Crate' : 'device'} soon.`,
      data: {
        device_id: device.id,
        device_name: device.consumer_name,
        battery_level: String(device.battery_level),
      },
      channelId: 'device_alerts',
    },
    device.id
  )

  if (result.sent > 0 || result.skipped === 'no_tokens') {
    // Track the notification (keyed by unit_id)
    await supabase
      .from('device_status_notifications')
      .upsert({
        unit_id: device.id,
        user_id: device.consumer_user_id,
        notification_type: 'battery_low',
        last_sent_at: new Date().toISOString(),
        context_data: { battery_level: device.battery_level },
      }, {
        onConflict: 'unit_id,notification_type',
      })
  }

  return result.sent > 0
}

/**
 * Send device online (recovered) notification and track it.
 */
async function sendDeviceOnlineNotification(
  supabase: SupabaseClient,
  device: UnitWithDevice
): Promise<boolean> {
  const result = await sendPushNotification(
    supabase,
    device.consumer_user_id,
    {
      type: 'device_online',
      title: `${device.consumer_name} is back online`,
      body: `Your ${device.device_type === 'hub' ? 'Saturday Hub' : 'Storage Crate'} is connected again.`,
      data: {
        device_id: device.id,
        device_name: device.consumer_name,
        device_type: device.device_type,
      },
      channelId: 'device_alerts',
    },
    device.id
  )

  if (result.sent > 0 || result.skipped === 'no_tokens') {
    // Track the notification (keyed by unit_id)
    await supabase
      .from('device_status_notifications')
      .upsert({
        unit_id: device.id,
        user_id: device.consumer_user_id,
        notification_type: 'device_online',
        last_sent_at: new Date().toISOString(),
        context_data: { recovered_at: new Date().toISOString() },
      }, {
        onConflict: 'unit_id,notification_type',
      })
  }

  return result.sent > 0
}
