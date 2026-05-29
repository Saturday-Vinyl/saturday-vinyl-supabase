// Shared push notification orchestration helpers.
//
// Higher-level orchestration: checks user preferences, fans out to all of a
// user's active tokens, logs delivery, and acts on the categorized result
// returned by the lower-level FCM primitive in `./send-fcm-push.ts`.
//
// Token deactivation is now driven by the FCM helper's `tokenShouldDeactivate`
// flag rather than ad-hoc string matching on the error message. This means
// server-wide auth/credential failures (THIRD_PARTY_AUTH_ERROR,
// BadEnvironmentKeyInToken at the project level, etc.) no longer silently
// disable tokens — they surface in admin_push_error_patterns instead.

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendFcmPush } from './send-fcm-push.ts'

export interface PushToken {
  id: string
  user_id: string
  token: string
  platform: 'ios' | 'android'
  last_used_at: string | null
}

export interface PushNotificationPayload {
  type: string
  title: string
  body: string
  data?: Record<string, string>
  channelId?: string // Android notification channel
}

export interface NotificationPreferences {
  now_playing_enabled: boolean
  flip_reminders_enabled: boolean
  device_offline_enabled: boolean
  device_online_enabled: boolean
  battery_low_enabled: boolean
}

// Map notification types to preference keys
const notificationTypeToPreferenceKey: Record<string, keyof NotificationPreferences> = {
  'now_playing': 'now_playing_enabled',
  'flip_reminder': 'flip_reminders_enabled',
  'device_offline': 'device_offline_enabled',
  'device_online': 'device_online_enabled',
  'battery_low': 'battery_low_enabled',
}

/**
 * Check if a user has a specific notification type enabled.
 * Returns true if preferences don't exist (default to enabled).
 */
export async function isNotificationEnabled(
  supabase: SupabaseClient,
  userId: string,
  notificationType: string
): Promise<boolean> {
  const prefKey = notificationTypeToPreferenceKey[notificationType]
  if (!prefKey) {
    // Unknown notification type, allow by default
    return true
  }

  const { data: prefs } = await supabase
    .from('notification_preferences')
    .select('*')
    .eq('user_id', userId)
    .single()

  // If no preferences exist, default to enabled
  if (!prefs) {
    return true
  }

  return prefs[prefKey] === true
}

/**
 * Get all active push tokens for a user.
 */
export async function getUserPushTokens(
  supabase: SupabaseClient,
  userId: string
): Promise<PushToken[]> {
  const { data: tokens } = await supabase
    .from('push_notification_tokens')
    .select('*')
    .eq('user_id', userId)
    .eq('is_active', true)

  return (tokens as PushToken[]) || []
}

/**
 * Send a push notification to a user.
 * Checks preferences, gets tokens, sends to all active tokens, and logs delivery.
 *
 * @returns Object with sent count and skipped reason (if any)
 */
export async function sendPushNotification(
  supabase: SupabaseClient,
  userId: string,
  notification: PushNotificationPayload,
  sourceId?: string
): Promise<{ sent: number; skipped?: string }> {
  // Check if this notification type is enabled for the user
  const enabled = await isNotificationEnabled(supabase, userId, notification.type)
  if (!enabled) {
    console.log(`Notification type ${notification.type} disabled for user ${userId}`)
    return { sent: 0, skipped: 'disabled_by_user' }
  }

  // Get user's active push tokens
  const tokens = await getUserPushTokens(supabase, userId)
  if (tokens.length === 0) {
    console.log(`No push tokens for user ${userId}`)
    return { sent: 0, skipped: 'no_tokens' }
  }

  let sentCount = 0

  // Send to all tokens via the shared FCM primitive.
  for (const token of tokens) {
    const result = await sendFcmPush({
      token: token.token,
      title: notification.title,
      body: notification.body,
      data: {
        type: notification.type,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        ...notification.data,
      },
      ...(token.platform === 'android' && {
        android: { channel_id: notification.channelId, priority: 'high' },
      }),
    })

    if (result.success) {
      await supabase.from('notification_delivery_log').insert({
        user_id: userId,
        notification_type: notification.type,
        source_id: sourceId,
        token_id: token.id,
        status: 'sent',
        sent_at: new Date().toISOString(),
      })
      sentCount++
    } else {
      console.error(
        `Push failed for token ${token.id} (${result.errorCategory}):`,
        result.error,
      )

      await supabase.from('notification_delivery_log').insert({
        user_id: userId,
        notification_type: notification.type,
        source_id: sourceId,
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
    }
  }

  return { sent: sentCount }
}

/**
 * Convert PEM-encoded private key to ArrayBuffer.
 *
 * Exported because `_shared/send-fcm-push.ts` and `_shared/send-activity-push.ts`
 * both reuse it for crypto.subtle.importKey().
 */
export function pemToArrayBuffer(pem: string): ArrayBuffer {
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
