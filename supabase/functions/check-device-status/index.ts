/**
 * Edge Function: check-device-status
 * Project: saturday-consumer-app
 * Description: Monitors unit connectivity and battery levels, sends push notifications for offline/low-battery/recovery events
 */

// Triggered by cron job (every 1 minute)
//
// This function:
// 1. Marks stale units as offline (updates units.is_online for realtime subscribers)
// 2. Finds units that need offline notifications (with 24h re-notification)
// 3. Finds units with low battery (<20%)
// 4. Finds units that recovered (came back online)
// 5. Sends push notifications for each, respecting user preferences
//
// Note: units.last_seen_at and units.is_online are kept in sync by a database
// trigger (sync_heartbeat_to_device_and_unit) that fires on each insert to
// device_heartbeats. The trigger sets is_online=true; this cron sets it false.

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

// Unit with telemetry data (all fields now directly on units table)
interface UnitWithTelemetry {
  id: string
  consumer_user_id: string
  consumer_name: string
  serial_number: string
  status: string
  last_seen_at: string | null
  battery_level: number | null
  is_online: boolean
}

/** Derive device type from serial number prefix */
function getDeviceType(serial_number: string): 'hub' | 'crate' {
  return serial_number?.startsWith('SV-HUB') ? 'hub' : 'crate'
}

/** Get display name for a unit, falling back to serial number */
function getDisplayName(unit: UnitWithTelemetry): string {
  return unit.consumer_name ?? unit.serial_number
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
      marked_offline: 0,
    }

    // Step 0: Mark stale units as offline (for realtime subscribers)
    results.marked_offline = await markStaleUnitsOffline(supabase)
    if (results.marked_offline > 0) {
      console.log(`Marked ${results.marked_offline} units as offline`)
    }

    // Step 1: Find and notify for offline units
    const offlineUnits = await findOfflineUnits(supabase)
    results.offline.checked = offlineUnits.length
    console.log(`Found ${offlineUnits.length} units needing offline notification`)

    for (const unit of offlineUnits) {
      const sent = await sendDeviceOfflineNotification(supabase, unit)
      if (sent) results.offline.notified++
    }

    // Step 2: Find and notify for low battery units
    const lowBatteryUnits = await findLowBatteryUnits(supabase)
    results.battery_low.checked = lowBatteryUnits.length
    console.log(`Found ${lowBatteryUnits.length} low battery units`)

    for (const unit of lowBatteryUnits) {
      const sent = await sendBatteryLowNotification(supabase, unit)
      if (sent) results.battery_low.notified++
    }

    // Step 3: Find and notify for recovered units
    const recoveredUnits = await findRecoveredUnits(supabase)
    results.online.checked = recoveredUnits.length
    console.log(`Found ${recoveredUnits.length} recovered units`)

    for (const unit of recoveredUnits) {
      const sent = await sendDeviceOnlineNotification(supabase, unit)
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
 * Mark units as offline if their last heartbeat exceeds the threshold.
 * This updates units.is_online which triggers realtime events for consumer apps.
 * Returns the number of units marked offline.
 */
async function markStaleUnitsOffline(supabase: SupabaseClient): Promise<number> {
  const offlineThreshold = new Date(Date.now() - OFFLINE_THRESHOLD_MINUTES * 60 * 1000).toISOString()

  const { data, error } = await supabase
    .from('units')
    .update({ is_online: false })
    .eq('is_online', true)
    .lt('last_seen_at', offlineThreshold)
    .select('id')

  if (error) {
    console.error('Error marking units offline:', error)
    return 0
  }

  return data?.length ?? 0
}

/**
 * Find claimed units that are offline and need a notification.
 * Queries ALL stale units (does NOT filter by is_online) so that the 24h
 * re-notification cycle works: cooldown is handled by device_status_notifications.
 */
async function findOfflineUnits(supabase: SupabaseClient): Promise<UnitWithTelemetry[]> {
  const offlineThreshold = new Date(Date.now() - OFFLINE_THRESHOLD_MINUTES * 60 * 1000)
  const cooldownThreshold = new Date(Date.now() - NOTIFICATION_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString()
  const offlineThresholdStr = offlineThreshold.toISOString()

  const { data: units, error } = await supabase
    .from('units')
    .select('id, consumer_user_id, consumer_name, serial_number, status, last_seen_at, battery_level, is_online')
    .not('consumer_user_id', 'is', null)
    .not('last_seen_at', 'is', null)
    .lt('last_seen_at', offlineThresholdStr)

  if (error) {
    console.error('Error fetching offline units:', error)
    return []
  }

  if (!units || units.length === 0) {
    return []
  }

  console.log(`Found ${units.length} units with stale heartbeats (threshold: ${offlineThresholdStr})`)

  // Filter out units that were already notified recently (24h cooldown)
  const unitIds = units.map(u => u.id)
  const { data: recentNotifications } = await supabase
    .from('device_status_notifications')
    .select('unit_id')
    .in('unit_id', unitIds)
    .eq('notification_type', 'device_offline')
    .gt('last_sent_at', cooldownThreshold)

  const recentlyNotifiedIds = new Set((recentNotifications || []).map(n => n.unit_id))

  return (units as UnitWithTelemetry[]).filter(u => !recentlyNotifiedIds.has(u.id))
}

/**
 * Find claimed units with low battery (<20%) that need a notification.
 * Battery filtering is done in the database query (not application code).
 */
async function findLowBatteryUnits(supabase: SupabaseClient): Promise<UnitWithTelemetry[]> {
  const cooldownThreshold = new Date(Date.now() - BATTERY_NOTIFICATION_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString()

  const { data: units, error } = await supabase
    .from('units')
    .select('id, consumer_user_id, consumer_name, serial_number, status, last_seen_at, battery_level, is_online')
    .not('consumer_user_id', 'is', null)
    .not('battery_level', 'is', null)
    .lt('battery_level', BATTERY_LOW_THRESHOLD)

  if (error) {
    console.error('Error finding low battery units:', error)
    return []
  }

  if (!units || units.length === 0) {
    return []
  }

  // Get recent battery notifications to check cooldown and recovery
  const unitIds = units.map(u => u.id)
  const { data: recentNotifications } = await supabase
    .from('device_status_notifications')
    .select('unit_id, last_sent_at, context_data')
    .in('unit_id', unitIds)
    .eq('notification_type', 'battery_low')

  const notificationMap = new Map(
    (recentNotifications || []).map(n => [n.unit_id, n])
  )

  // Filter based on cooldown and whether battery recovered since last notification
  return (units as UnitWithTelemetry[]).filter(unit => {
    const lastNotif = notificationMap.get(unit.id)
    if (!lastNotif) {
      return true // Never notified
    }

    // Check if within cooldown
    if (new Date(lastNotif.last_sent_at) > new Date(cooldownThreshold)) {
      // Within cooldown - only notify if battery went above recovery threshold since
      const lastNotifiedLevel = lastNotif.context_data?.battery_level as number | undefined
      if (lastNotifiedLevel !== undefined && lastNotifiedLevel < BATTERY_RECOVERY_THRESHOLD) {
        return false
      }
    }

    return true
  })
}

/**
 * Find units that recovered (came back online after being offline).
 *
 * A unit is considered "recovered" if:
 * 1. It has a recent heartbeat (within 2 minutes)
 * 2. We previously sent a device_offline notification for it (in the last 24h)
 * 3. We haven't already sent a device_online notification after that offline notification
 */
async function findRecoveredUnits(supabase: SupabaseClient): Promise<UnitWithTelemetry[]> {
  const recentThreshold = new Date(Date.now() - 2 * 60 * 1000)
  const recentThresholdStr = recentThreshold.toISOString()
  const cooldownThreshold = new Date(Date.now() - NOTIFICATION_COOLDOWN_HOURS * 60 * 60 * 1000).toISOString()

  const { data: units, error } = await supabase
    .from('units')
    .select('id, consumer_user_id, consumer_name, serial_number, status, last_seen_at, battery_level, is_online')
    .not('consumer_user_id', 'is', null)
    .not('last_seen_at', 'is', null)
    .gt('last_seen_at', recentThresholdStr)

  if (error) {
    console.error('Error fetching recently active units:', error)
    return []
  }

  if (!units || units.length === 0) {
    return []
  }

  // Find units that have an offline notification from the last 24h
  const unitIds = units.map(u => u.id)
  const { data: offlineNotifications } = await supabase
    .from('device_status_notifications')
    .select('unit_id, last_sent_at')
    .in('unit_id', unitIds)
    .eq('notification_type', 'device_offline')
    .gt('last_sent_at', cooldownThreshold)

  const offlineUnitIds = new Set((offlineNotifications || []).map(n => n.unit_id))

  if (offlineUnitIds.size === 0) {
    return []
  }

  // Also check we haven't already sent an online notification for this recovery
  const { data: onlineNotifications } = await supabase
    .from('device_status_notifications')
    .select('unit_id, last_sent_at')
    .in('unit_id', Array.from(offlineUnitIds))
    .eq('notification_type', 'device_online')

  const onlineNotifMap = new Map(
    (onlineNotifications || []).map(n => [n.unit_id, new Date(n.last_sent_at)])
  )

  // Only include units where offline notification is more recent than online notification
  return (units as UnitWithTelemetry[]).filter(unit => {
    if (!offlineUnitIds.has(unit.id)) {
      return false
    }

    const offlineNotif = offlineNotifications?.find(n => n.unit_id === unit.id)
    const onlineNotifTime = onlineNotifMap.get(unit.id)

    if (onlineNotifTime && offlineNotif) {
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
  unit: UnitWithTelemetry
): Promise<boolean> {
  const deviceType = getDeviceType(unit.serial_number)
  const displayName = getDisplayName(unit)

  const result = await sendPushNotification(
    supabase,
    unit.consumer_user_id,
    {
      type: 'device_offline',
      title: `${displayName} is offline`,
      body: `Your ${deviceType === 'hub' ? 'Saturday Hub' : 'Storage Crate'} hasn't been seen for a while. Check the connection.`,
      data: {
        device_id: unit.id,
        device_name: displayName,
        device_type: deviceType,
      },
      channelId: 'device_alerts',
    },
    unit.id
  )

  if (result.sent > 0 || result.skipped === 'no_tokens') {
    await supabase
      .from('device_status_notifications')
      .upsert({
        unit_id: unit.id,
        user_id: unit.consumer_user_id,
        notification_type: 'device_offline',
        last_sent_at: new Date().toISOString(),
        context_data: { last_seen_at: unit.last_seen_at },
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
  unit: UnitWithTelemetry
): Promise<boolean> {
  const deviceType = getDeviceType(unit.serial_number)
  const displayName = getDisplayName(unit)

  const result = await sendPushNotification(
    supabase,
    unit.consumer_user_id,
    {
      type: 'battery_low',
      title: `${displayName} battery low`,
      body: `Battery is at ${unit.battery_level}%. Charge your ${deviceType === 'crate' ? 'Storage Crate' : 'device'} soon.`,
      data: {
        device_id: unit.id,
        device_name: displayName,
        battery_level: String(unit.battery_level),
      },
      channelId: 'device_alerts',
    },
    unit.id
  )

  if (result.sent > 0 || result.skipped === 'no_tokens') {
    await supabase
      .from('device_status_notifications')
      .upsert({
        unit_id: unit.id,
        user_id: unit.consumer_user_id,
        notification_type: 'battery_low',
        last_sent_at: new Date().toISOString(),
        context_data: { battery_level: unit.battery_level },
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
  unit: UnitWithTelemetry
): Promise<boolean> {
  const deviceType = getDeviceType(unit.serial_number)
  const displayName = getDisplayName(unit)

  const result = await sendPushNotification(
    supabase,
    unit.consumer_user_id,
    {
      type: 'device_online',
      title: `${displayName} is back online`,
      body: `Your ${deviceType === 'hub' ? 'Saturday Hub' : 'Storage Crate'} is connected again.`,
      data: {
        device_id: unit.id,
        device_name: displayName,
        device_type: deviceType,
      },
      channelId: 'device_alerts',
    },
    unit.id
  )

  if (result.sent > 0 || result.skipped === 'no_tokens') {
    await supabase
      .from('device_status_notifications')
      .upsert({
        unit_id: unit.id,
        user_id: unit.consumer_user_id,
        notification_type: 'device_online',
        last_sent_at: new Date().toISOString(),
        context_data: { recovered_at: new Date().toISOString() },
      }, {
        onConflict: 'unit_id,notification_type',
      })
  }

  return result.sent > 0
}
