# Push Notifications Setup Guide

This document explains how to configure push notifications for the Now Playing feature.

## Overview

The Now Playing push notification system allows users to receive notifications when a record is placed on their Saturday Hub, even when the app is closed. The architecture:

```
Hub POST → now_playing_events → Database Webhook → Edge Function
                                                       │
                                                       ├── Resolve EPC to album
                                                       ├── Insert to user_now_playing_notifications
                                                       └── Send FCM push if app not connected
```

## Prerequisites

1. **Supabase project** with the database migration applied
2. **Firebase project** with iOS and Android apps configured
3. **APNs key** (for iOS push notifications)

## Step 1: Apply Database Migration

Run the migration to create the required tables:

```bash
supabase db push
```

This creates:
- `push_notification_tokens` - FCM token storage
- `user_now_playing_notifications` - User-facing realtime table
- `notification_delivery_log` - Delivery tracking

## Step 2: Deploy Edge Functions

Deploy the Edge Functions to Supabase:

```bash
supabase functions deploy process-now-playing-event
supabase functions deploy register-push-token
```

## Step 3: Configure Firebase

### 3.1 Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or use an existing one
3. Add iOS and Android apps to the project

### 3.2 iOS Configuration

1. **Download `GoogleService-Info.plist`**
   - In Firebase Console → Project Settings → iOS app
   - Download the config file
   - Add to `ios/Runner/` directory

2. **Generate APNs Key**
   - Go to [Apple Developer Portal](https://developer.apple.com/)
   - Certificates, Identifiers & Profiles → Keys
   - Create a new key with "Apple Push Notifications service (APNs)" enabled
   - Download the `.p8` file

3. **Upload APNs Key to Firebase**
   - Firebase Console → Project Settings → Cloud Messaging
   - Under "Apple app configuration", upload the APNs key
   - Enter the Key ID and Team ID

4. **Enable Push Notification Capability**
   - Open `ios/Runner.xcworkspace` in Xcode
   - Select the Runner target → Signing & Capabilities
   - Add "Push Notifications" capability
   - Add "Background Modes" capability with "Remote notifications" checked

### 3.3 Android Configuration

1. **Download `google-services.json`**
   - In Firebase Console → Project Settings → Android app
   - Download the config file
   - Add to `android/app/` directory

2. **Add Firebase Gradle Plugins**

   In `android/build.gradle`:
   ```gradle
   buildscript {
       dependencies {
           classpath 'com.google.gms:google-services:4.4.0'
       }
   }
   ```

   In `android/app/build.gradle`:
   ```gradle
   apply plugin: 'com.google.gms.google-services'
   ```

## Step 4: Configure Edge Function Secrets

In Supabase Dashboard → Edge Functions → Secrets, add:

| Secret Name | Value |
|-------------|-------|
| `FIREBASE_PROJECT_ID` | Your Firebase project ID |
| `FIREBASE_PRIVATE_KEY` | Private key from service account JSON (with `\n` escaped as `\\n`) |
| `FIREBASE_CLIENT_EMAIL` | Client email from service account JSON |

To get the service account credentials:
1. Firebase Console → Project Settings → Service accounts
2. Click "Generate new private key"
3. Copy the values from the downloaded JSON

## Step 5: Configure Database Webhook

This is the critical step that connects hub events to push notifications.

1. Go to **Supabase Dashboard → Database → Webhooks**
2. Click **"Create a new hook"**
3. Configure:

| Field | Value |
|-------|-------|
| Name | `process-now-playing-event` |
| Table | `now_playing_events` |
| Events | `INSERT` |
| Type | `Supabase Edge Functions` |
| Edge Function | `process-now-playing-event` |

4. Click **"Create webhook"**

### Alternative: HTTP Webhook

If you prefer HTTP webhook over Edge Function integration:

| Field | Value |
|-------|-------|
| URL | `https://<project-ref>.supabase.co/functions/v1/process-now-playing-event` |
| Method | `POST` |
| Headers | `Authorization: Bearer <service_role_key>` |
| Headers | `Content-Type: application/json` |

## Step 6: Enable Realtime for Notifications Table

Ensure the `user_now_playing_notifications` table is added to the Supabase Realtime publication:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE user_now_playing_notifications;
```

This should be done automatically by the migration, but verify in:
**Supabase Dashboard → Database → Replication**

## Step 7: Request Permissions in App

The app automatically requests push notification permissions when the user logs in. You can also manually trigger this:

```dart
import 'package:saturday_consumer_app/services/push_token_service.dart';

// Request permissions and register token
final success = await PushTokenService.instance.requestPermissionsAndRegister();
```

## Testing

### Test Database Webhook

Insert a test row into `now_playing_events`:

```sql
INSERT INTO now_playing_events (unit_id, epc, event_type, timestamp)
VALUES ('YOUR_HUB_SERIAL', 'TEST_EPC_123', 'placed', NOW());
```

Then check:
1. `user_now_playing_notifications` table for the processed notification
2. Edge Function logs in Supabase Dashboard
3. Push notification on the device (if app is closed)

### Test Push Notifications

1. Close the app completely (not just backgrounded)
2. Insert a test row as above (with a real hub serial number linked to your user)
3. You should receive a push notification within a few seconds

## Troubleshooting

### No Push Notifications Received

1. **Check Edge Function logs** - Supabase Dashboard → Edge Functions → Logs
2. **Verify webhook is firing** - Check `notification_delivery_log` table
3. **Verify FCM token is registered** - Check `push_notification_tokens` table
4. **Check Firebase credentials** - Ensure secrets are set correctly

### Push Received But No Sound/Banner

1. Check iOS/Android notification settings for the app
2. Verify notification channel configuration (Android)
3. Check Do Not Disturb settings

### Realtime Updates Not Working

1. Verify RLS policies allow the user to read their notifications
2. Check that the table is in the realtime publication
3. Verify the user is authenticated

## Architecture Notes

### Why Two Tables?

- `now_playing_events` - Raw events from hubs (no user_id, just unit_id)
- `user_now_playing_notifications` - User-facing, RLS-protected, with resolved album info

This separation:
1. Keeps hub inserts fast (no joins or lookups)
2. Enables server-side filtering via RLS
3. Allows async processing without blocking hubs
4. Pre-resolves data so apps don't need extra queries

### Presence Tracking

The `last_used_at` field on `push_notification_tokens` is updated every 2 minutes while the app is connected. The Edge Function uses this to decide whether to send push:

- If `last_used_at` is within 5 minutes → App is connected, skip push (realtime will handle it)
- If `last_used_at` is older → App is closed, send push notification

This prevents duplicate notifications when the app is open.
