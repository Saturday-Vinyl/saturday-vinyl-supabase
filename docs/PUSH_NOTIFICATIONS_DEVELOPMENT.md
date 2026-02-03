# Push Notifications Development Guide

This document explains how to add new push notification types to the app. For initial setup, see `PUSH_NOTIFICATIONS_SETUP.md`.

## Architecture Overview

Push notifications flow through two pipelines:

### Event-Driven Pipeline
```
Database Event → Database Webhook → Edge Function → FCM → Device
```

### Scheduled Pipeline (for absence-of-event detection)
```
pg_cron → pg_net HTTP Request → Edge Function → FCM → Device
```

Key components:
- **Database Webhook**: Triggers on table INSERT/UPDATE (for event-driven notifications)
- **pg_cron + pg_net**: Scheduled invocation of Edge Functions (for polling-based detection like "device offline")
- **Edge Function**: Processes the event, resolves user data, sends FCM push
- **Flutter Handler**: Receives push and handles navigation/display

## Adding a New Push Notification Type

### Step 1: Decide on the Trigger

Push notifications are triggered by database events. Determine:
- Which table should trigger the notification?
- Which event type (INSERT, UPDATE, DELETE)?
- What conditions must be met to send the notification?

### Step 2: Create or Update the Edge Function

For a new notification type, you can either:
- **Create a new Edge Function** (if the logic is complex or unrelated to existing functions)
- **Extend an existing Edge Function** (if it's a variation of existing logic)

Example: Creating a new `send-device-alert` Edge Function:

```typescript
// supabase/functions/send-device-alert/index.ts

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false }
  })

  const payload = await req.json()
  const record = payload.record

  // 1. Find the unit and its owner
  const { data: unit } = await supabase
    .from('units')
    .select('id, consumer_user_id, consumer_name')
    .eq('id', record.unit_id)
    .single()

  if (!unit) return new Response(JSON.stringify({ skipped: true }))

  // 2. Get the user's push tokens
  const { data: tokens } = await supabase
    .from('push_notification_tokens')
    .select('*')
    .eq('user_id', unit.consumer_user_id)
    .eq('is_active', true)

  // 3. Send push notification via FCM
  for (const token of tokens || []) {
    await sendFirebasePush(token, {
      title: `Alert: ${unit.consumer_name}`,
      body: record.message,
      data: {
        type: 'device_alert',  // <-- This identifies the notification type
        device_id: unit.id,    // unit.id is the app's device identifier
      }
    })
  }

  return new Response(JSON.stringify({ success: true }))
})
```

### Step 3: Configure Database Webhook

In Supabase Dashboard → Database → Webhooks:

1. Create a new webhook
2. Select the triggering table and event type
3. Point to your Edge Function

### Step 4: Handle in Flutter App

Update `lib/services/push_notification_handler.dart` to handle the new notification type:

```dart
void _handleForegroundMessage(RemoteMessage message) {
  final notificationType = message.data['type'] as String?;

  switch (notificationType) {
    case 'now_playing':
      // Handled by realtime when app is open
      break;
    case 'device_alert':  // <-- Add new case
      _showLocalNotificationForMessage(message);
      break;
    // ... other cases
  }
}

void _handleNotificationTap(RemoteMessage message) {
  final notificationType = message.data['type'] as String?;

  switch (notificationType) {
    case 'now_playing':
      _navigateTo(RoutePaths.nowPlaying);
      break;
    case 'device_alert':  // <-- Add new case
      final deviceId = message.data['device_id'] as String?;
      if (deviceId != null) {
        _navigateTo('/account/device/$deviceId');
      }
      break;
    // ... other cases
  }
}
```

### Step 5: Log Delivery (Optional but Recommended)

Use the `notification_delivery_log` table to track delivery:

```typescript
await supabase.from('notification_delivery_log').insert({
  user_id: userId,
  notification_type: 'device_alert',  // Your notification type
  source_id: record.id,
  token_id: token.id,
  status: 'sent',
  sent_at: new Date().toISOString(),
})
```

## FCM Push Helper

A shared FCM helper module is available at `supabase/functions/_shared/send-push.ts`. Import it in your Edge Functions:

```typescript
import { sendPushNotification, isNotificationEnabled } from '../_shared/send-push.ts'
```

### Available Functions

**`sendPushNotification()`** - Sends a push notification via FCM v1 API
```typescript
await sendPushNotification(supabase, userId, {
  type: 'device_offline',
  title: 'Device Offline',
  body: 'Your Saturday Hub has been offline for 10 minutes',
  data: { device_id: deviceId },
})
```

**`isNotificationEnabled()`** - Checks if a notification type is enabled in user preferences
```typescript
const enabled = await isNotificationEnabled(supabase, userId, 'device_offline')
if (!enabled) return
```

**`getFirebaseAccessToken()`** - Gets OAuth2 token for FCM API
**`pemToArrayBuffer()`** - Converts PEM key to ArrayBuffer for JWT signing

### Required Environment Variables

These are already configured in Supabase secrets:
- `FIREBASE_PROJECT_ID`
- `FIREBASE_PRIVATE_KEY`
- `FIREBASE_CLIENT_EMAIL`

## FCM Message Structure

```typescript
const message = {
  message: {
    token: fcmToken,
    notification: {
      title: 'Notification Title',
      body: 'Notification body text',
    },
    data: {
      type: 'your_notification_type',  // Required: identifies the type
      // Add any custom data the app needs
      some_id: 'value',
    },
    android: {
      priority: 'high',
      notification: {
        channel_id: 'your_channel',  // Must match Android channel setup
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
}
```

## Notification Preferences

User notification preferences are stored server-side in the `notification_preferences` table. This allows Edge Functions to check preferences before sending notifications.

### Server-Side (Edge Functions)

Use the `isNotificationEnabled()` helper to check preferences:

```typescript
import { isNotificationEnabled } from '../_shared/send-push.ts'

// Check if user has enabled this notification type
const enabled = await isNotificationEnabled(supabase, userId, 'device_offline')
if (!enabled) {
  console.log('User has disabled device_offline notifications')
  return
}
```

Preference field mapping:
| Notification Type | Preference Field |
|-------------------|------------------|
| `now_playing` | `now_playing_enabled` |
| `flip_reminder` | `flip_reminders_enabled` |
| `device_offline` | `device_offline_enabled` |
| `device_online` | `device_online_enabled` |
| `battery_low` | `battery_low_enabled` |

### Client-Side (Flutter)

Use the `notificationPreferencesProvider` to read/write preferences:

```dart
// Read current preferences
final prefs = ref.watch(notificationPreferencesProvider);
if (prefs.deviceOfflineEnabled) { ... }

// Update a preference
ref.read(notificationPreferencesProvider.notifier).setDeviceOfflineEnabled(false);
```

The provider automatically syncs changes to the server.

## Existing Notification Types

| Type | Trigger | Description |
|------|---------|-------------|
| `now_playing` | `now_playing_events` INSERT | Record placed/removed on hub |
| `device_offline` | `check-device-status` cron (1 min) | Device hasn't sent heartbeat in 10 minutes |
| `device_online` | `check-device-status` cron (1 min) | Device comes back online after being offline |
| `battery_low` | `check-device-status` cron (1 min) | Device battery drops below 20% |
| `flip_reminder` | Local notification scheduled in app | Reminder to flip the record |

## Device Heartbeats & Presence Detection

Device status notifications rely on heartbeat data to determine whether a device is online or offline. This section explains the architecture.

### Unified Device Architecture

The device management uses a unified architecture with the following tables:

- **`units`** - Product units owned by consumers (serial_number, consumer_user_id, consumer_name)
- **`devices`** - Hardware instances identified by MAC address (telemetry, last_seen_at)
- **`device_heartbeats`** - Raw heartbeat data keyed by MAC address

### Heartbeat Data Flow

```
Device → HTTP POST → device_heartbeats table (keyed by MAC)
                           ↓
              Postgres Trigger (on INSERT)
                           ↓
              devices.last_seen_at + latest_telemetry updated
                           ↓
              check-device-status cron job queries devices table
                           ↓
              Push notification sent if device is stale/recovered
```

### devices.latest_telemetry Format

The telemetry format is **flattened** (not capability-scoped). Example from a live hub:

```json
{
  "unit_id": "SV-HUB-00001",
  "device_type": "hub-prototype",
  "battery_level": null,
  "battery_charging": null,
  "wifi_rssi": -66,
  "thread_rssi": null,
  "uptime_sec": 5522,
  "free_heap": 57052,
  "min_free_heap": 2692,
  "largest_free_block": 31744
}
```

### Automatic Sync to devices Table

A database trigger automatically updates `devices.last_seen_at` and `devices.latest_telemetry` whenever a heartbeat is inserted:

```sql
CREATE TRIGGER device_heartbeat_sync_device
AFTER INSERT ON device_heartbeats
FOR EACH ROW
EXECUTE FUNCTION sync_heartbeat_to_device();
```

The trigger also:
- Updates `latest_telemetry` with the full flattened telemetry object
- Sets `status='online'` if the device was marked offline

### Determining Device Presence

**Server-side (Edge Functions):**
The `check-device-status` function queries `devices.last_seen_at` via JOIN:

```typescript
// Find claimed units with offline devices (no heartbeat for 10+ minutes)
const { data: offlineUnits } = await supabase
  .from('units')
  .select('id, consumer_user_id, consumer_name, serial_number, status, devices!inner(last_seen_at, status, latest_telemetry)')
  .not('consumer_user_id', 'is', null)
  .lt('devices.last_seen_at', offlineThreshold)
  .neq('devices.status', 'offline')
```

**Client-side (Flutter):**
Use the `isEffectivelyOnline` getter on the Device model, which checks heartbeat staleness:

```dart
// In Device model
bool get isEffectivelyOnline {
  if (lastSeenAt == null) return false;
  final staleness = DateTime.now().difference(lastSeenAt!);
  return staleness < const Duration(minutes: 10);
}

// Usage in screens
final onlineCount = devices.where((d) => d.isEffectivelyOnline).length;
```

**Important:** Do not rely on `status` fields alone. These can become stale. Always use `isEffectivelyOnline` in the Flutter app or check `last_seen_at` directly in Edge Functions.

## Scheduled Edge Functions (pg_cron Setup)

Some notifications cannot be triggered by database events because they detect the **absence** of an event (e.g., "device offline" means no heartbeat received in 10 minutes). For these, we use scheduled Edge Functions invoked via pg_cron.

### Prerequisites

Enable the required Postgres extensions in Supabase Dashboard → Database → Extensions:
- `pg_cron` - Scheduling cron jobs in Postgres
- `pg_net` - Making HTTP requests from Postgres

### Setting Up a Scheduled Edge Function

1. **Deploy the Edge Function first:**
   ```bash
   supabase functions deploy check-device-status
   ```

2. **Open Supabase Dashboard → SQL Editor**

3. **Schedule the function using pg_cron:**

   ```sql
   -- Schedule check-device-status to run every minute
   SELECT cron.schedule(
     'check-device-status',  -- Job name (must be unique)
     '* * * * *',            -- Cron expression (every minute)
     $$
     SELECT net.http_post(
       url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/check-device-status',
       headers := jsonb_build_object(
         'Content-Type', 'application/json',
         'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY'
       ),
       body := '{}'::jsonb
     ) AS request_id;
     $$
   );
   ```

   **Important:** Replace `YOUR_PROJECT_REF` with your Supabase project reference and `YOUR_SERVICE_ROLE_KEY` with your actual service role key. The service role key must be hardcoded in the SQL because `current_setting('app.settings.service_role_key')` is not available in the cron context.

### Managing Cron Jobs

**List all scheduled jobs:**
```sql
SELECT * FROM cron.job;
```

**View job run history:**
```sql
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 20;
```

**Unschedule a job:**
```sql
SELECT cron.unschedule('check-device-status');
```

**Update a job schedule:**
```sql
-- First unschedule, then reschedule with new parameters
SELECT cron.unschedule('check-device-status');
SELECT cron.schedule('check-device-status', '*/5 * * * *', $$ ... $$);
```

### Cron Expression Reference

| Expression | Meaning |
|------------|---------|
| `* * * * *` | Every minute |
| `*/5 * * * *` | Every 5 minutes |
| `0 * * * *` | Every hour (at minute 0) |
| `0 0 * * *` | Every day at midnight |
| `0 9 * * 1` | Every Monday at 9 AM |

### Troubleshooting Cron Jobs

**Job not running:**
1. Check that `pg_cron` and `pg_net` extensions are enabled
2. Verify the job exists: `SELECT * FROM cron.job WHERE jobname = 'check-device-status';`
3. Check job history for errors: `SELECT * FROM cron.job_run_details WHERE jobid = X ORDER BY start_time DESC;`

**HTTP request failing:**
1. Check Edge Function logs in Supabase Dashboard → Edge Functions → Logs
2. Verify the function URL is correct
3. Ensure the service role key is valid and has not been regenerated

**"unrecognized configuration parameter" error:**
If you see `ERROR: unrecognized configuration parameter "app.settings.service_role_key"`, you cannot use `current_setting()` in cron jobs. Hardcode the service role key directly in the SQL instead.

## Testing

1. Deploy your Edge Function:
   ```bash
   supabase functions deploy your-function-name
   ```

2. Configure the database webhook in Supabase Dashboard

3. Insert a test row to trigger the webhook:
   ```sql
   INSERT INTO your_table (column1, column2) VALUES ('value1', 'value2');
   ```

4. Check Edge Function logs in Supabase Dashboard

5. Verify push received on device (with app closed for system notification)

## Troubleshooting

### Push not received
1. Check Edge Function logs for errors
2. Verify webhook is configured and enabled
3. Check `push_notification_tokens` table for active tokens
4. Check `notification_delivery_log` for delivery status

### Wrong navigation on tap
1. Verify the `type` field in FCM data matches the switch case
2. Check that route paths are correct
3. Test with app in background (not terminated) first

### Foreground notifications not showing
1. By default, FCM doesn't show banners when app is in foreground
2. Use `flutter_local_notifications` to show local notifications
3. Or handle silently and update UI via state management

### 401 THIRD_PARTY_AUTH_ERROR when sending to real FCM tokens

**Symptoms:**
- Test with fake FCM token returns 400 (auth works)
- Test with real FCM token returns 401 with `THIRD_PARTY_AUTH_ERROR`
- OAuth token exchange succeeds, but FCM call fails

**Root Cause:** Missing or misconfigured APNs credentials in Firebase Console.

For iOS push notifications, Firebase needs to forward pushes to Apple's APNs servers. If the APNs authentication key is missing or only configured for one environment (development vs production), you'll get this error.

**Solution:**

1. **Check Firebase Console → Project Settings → Cloud Messaging → Apple app configuration**

2. **Ensure APNs Authentication Key is uploaded for BOTH environments:**
   - Development APNs auth key (for debug builds / `flutter run`)
   - Production APNs auth key (for release builds / TestFlight / App Store)

   Note: The same `.p8` key file works for both - just upload it in both slots.

3. **After adding/updating APNs keys:**
   - Wait 5 minutes for Firebase to sync
   - Delete stale FCM tokens from `push_notification_tokens` table
   - Reinstall the app (delete and reinstall, not just restart)
   - The app will register a fresh FCM token on launch

4. **Verify the fix:**
   ```sql
   -- Check token was recently created
   SELECT token, created_at FROM push_notification_tokens ORDER BY created_at DESC;
   ```

**Common scenarios that cause this:**
- Initially configured only development APNs key, then started testing with TestFlight
- Switching between `flutter run` (debug) and TestFlight (release) builds
- FCM tokens registered before APNs key was properly configured become "stale"

**Getting APNs Authentication Key:**
1. Go to [Apple Developer Portal → Keys](https://developer.apple.com/account/resources/authkeys/list)
2. Create or use existing APNs key
3. Download the `.p8` file (Apple only allows one download!)
4. Upload to Firebase Console for both development and production
