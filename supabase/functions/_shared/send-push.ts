// Shared FCM Push Notification Helper
// Used by multiple Edge Functions to send push notifications via Firebase Cloud Messaging

import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'

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

  // Send to all tokens
  for (const token of tokens) {
    try {
      await sendFirebasePush(token, notification)

      // Log success
      await supabase.from('notification_delivery_log').insert({
        user_id: userId,
        notification_type: notification.type,
        source_id: sourceId,
        token_id: token.id,
        status: 'sent',
        sent_at: new Date().toISOString(),
      })

      sentCount++
    } catch (error) {
      console.error(`Push failed for token ${token.id}:`, error)

      // Log failure
      await supabase.from('notification_delivery_log').insert({
        user_id: userId,
        notification_type: notification.type,
        source_id: sourceId,
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
    }
  }

  return { sent: sentCount }
}

/**
 * Send a push notification directly via Firebase Cloud Messaging v1 API.
 */
export async function sendFirebasePush(
  token: PushToken,
  notification: PushNotificationPayload
): Promise<void> {
  const projectId = Deno.env.get('FIREBASE_PROJECT_ID')
  const rawPrivateKey = Deno.env.get('FIREBASE_PRIVATE_KEY')
  const privateKey = rawPrivateKey?.replace(/\\n/g, '\n')
  const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL')

  if (!projectId || !privateKey || !clientEmail) {
    console.log('[send-push] Firebase not configured, skipping push')
    return
  }

  // Get OAuth2 access token for Firebase
  const accessToken = await getFirebaseAccessToken(privateKey, clientEmail)

  if (!accessToken) {
    throw new Error('Failed to obtain Firebase access token')
  }

  // Send via Firebase Cloud Messaging v1 API
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

  // Build data payload with type and any additional data
  const dataPayload: Record<string, string> = {
    type: notification.type,
    click_action: 'FLUTTER_NOTIFICATION_CLICK',
    ...notification.data,
  }

  const authHeader = `Bearer ${accessToken}`

  // Build message body
  const messageBody = {
    message: {
      token: token.token,
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: dataPayload,
      // Platform-specific options only for Android (iOS handled by notification object)
      ...(token.platform === 'android' && {
        android: {
          priority: 'high' as const,
          notification: {
            channel_id: notification.channelId || 'default',
            sound: 'default',
          },
        },
      }),
    },
  }

  const response = await fetch(fcmUrl, {
    method: 'POST',
    headers: {
      'Authorization': authHeader,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(messageBody),
  })

  if (!response.ok) {
    const errorBody = await response.text()
    throw new Error(`Firebase push failed: ${response.status} - ${errorBody}`)
  }
}

/**
 * Get OAuth2 access token for Firebase Cloud Messaging.
 */
export async function getFirebaseAccessToken(
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
  const keyBuffer = pemToArrayBuffer(privateKey)
  const key = await crypto.subtle.importKey(
    'pkcs8',
    keyBuffer,
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

  if (!tokenData.access_token) {
    throw new Error('OAuth response missing access_token')
  }

  return tokenData.access_token
}

/**
 * Convert PEM-encoded private key to ArrayBuffer.
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
