# Push Notifications Development Guide

This document explains how to add new push notification types to the app. For initial setup, see `PUSH_NOTIFICATIONS_SETUP.md`.

## Architecture Overview

Push notifications flow through this pipeline:

```
Database Event → Database Webhook → Edge Function → FCM → Device
```

Key components:
- **Database Webhook**: Triggers on table INSERT/UPDATE
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

  // 1. Find the user(s) who should receive this notification
  const { data: device } = await supabase
    .from('consumer_devices')
    .select('user_id, name')
    .eq('id', record.device_id)
    .single()

  if (!device) return new Response(JSON.stringify({ skipped: true }))

  // 2. Get the user's push tokens
  const { data: tokens } = await supabase
    .from('push_notification_tokens')
    .select('*')
    .eq('user_id', device.user_id)
    .eq('is_active', true)

  // 3. Send push notification via FCM
  for (const token of tokens || []) {
    await sendFirebasePush(token, {
      title: `Alert: ${device.name}`,
      body: record.message,
      data: {
        type: 'device_alert',  // <-- This identifies the notification type
        device_id: record.device_id,
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

The `process-now-playing-event` Edge Function contains helper functions for sending FCM pushes. You can copy or import these:

- `sendFirebasePush()` - Sends a push via FCM v1 API
- `getFirebaseAccessToken()` - Gets OAuth2 token for FCM
- `pemToArrayBuffer()` - Converts PEM key to ArrayBuffer for signing

Required environment variables (already configured):
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

## Existing Notification Types

| Type | Trigger | Description |
|------|---------|-------------|
| `now_playing` | `now_playing_events` INSERT | Record placed/removed on hub |
| `device_offline` | (not yet implemented) | Device goes offline |
| `flip_reminder` | (not yet implemented) | Reminder to flip the record |

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
