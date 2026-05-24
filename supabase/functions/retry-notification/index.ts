/**
 * Edge Function: retry-notification
 * Project: saturday-admin-app
 * Description: Admin-gated re-send of a previously-logged push delivery.
 *              Reconstructs the original FCM payload from the source record
 *              (user_now_playing_notifications for now_playing) and inserts a
 *              new notification_delivery_log row with sent_by_user_id set to
 *              the admin's user id — preserving the audit trail of the
 *              original failure.
 *
 * Body: { delivery_log_id: string }
 * Response: { success: boolean, delivery_log_id: string, error?: string }
 *
 * v1 supports retrying only `now_playing` notifications. Other types are
 * rejected with 400 — they need per-type payload reconstruction which is out
 * of scope for the first cut.
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders, jsonResponse } from '../_shared/cors.ts'
import { getAdminClient, resolveCaller } from '../_shared/auth.ts'
import { sendFcmPush } from '../_shared/send-fcm-push.ts'
import {
  buildNowPlayingPushArgs,
  type AlbumInfo,
} from '../_shared/now-playing-push.ts'

interface RetryRequest {
  delivery_log_id?: string
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405)
  }

  try {
    const admin = getAdminClient()

    const caller = await resolveCaller(req, admin)
    if (!caller || caller.kind !== 'user') {
      return jsonResponse({ error: 'Unauthorized' }, 401)
    }

    const { data: callerRow, error: callerErr } = await admin
      .from('users')
      .select('id, is_admin')
      .eq('id', caller.databaseUserId)
      .maybeSingle()
    if (callerErr || !callerRow || !callerRow.is_admin) {
      return jsonResponse({ error: 'Forbidden — admin required' }, 403)
    }

    const body = (await req.json().catch(() => null)) as RetryRequest | null
    const deliveryLogId = body?.delivery_log_id
    if (!deliveryLogId) {
      return jsonResponse({ error: 'Missing delivery_log_id' }, 400)
    }

    // 1. Load the original delivery log row.
    const { data: original, error: origErr } = await admin
      .from('notification_delivery_log')
      .select('id, user_id, notification_type, source_id, token_id')
      .eq('id', deliveryLogId)
      .maybeSingle()

    if (origErr) {
      console.error('[retry-notification] Failed to load delivery log:', origErr)
      return jsonResponse({ error: 'Database error' }, 500)
    }
    if (!original) {
      return jsonResponse({ error: 'Delivery log row not found' }, 404)
    }

    if (original.notification_type === 'admin_test') {
      return jsonResponse(
        { error: 'admin_test pushes are one-shot; send a new test instead' },
        400,
      )
    }
    if (original.notification_type !== 'now_playing') {
      return jsonResponse(
        {
          error: `Retry not supported for notification_type='${original.notification_type}' yet`,
        },
        400,
      )
    }

    // 2. Load the target token.
    if (!original.token_id) {
      return jsonResponse({ error: 'Original row has no token_id; cannot retry' }, 400)
    }
    const { data: token, error: tokenErr } = await admin
      .from('push_notification_tokens')
      .select('id, token, user_id, is_active')
      .eq('id', original.token_id)
      .maybeSingle()

    if (tokenErr) {
      console.error('[retry-notification] Failed to load token:', tokenErr)
      return jsonResponse({ error: 'Database error' }, 500)
    }
    if (!token) {
      return jsonResponse({ error: 'Token no longer exists' }, 400)
    }
    if (!token.is_active) {
      return jsonResponse({ error: 'Token is inactive — reactivate or use a different device' }, 400)
    }

    // 3. Reconstruct the FCM payload from user_now_playing_notifications.
    if (!original.source_id) {
      return jsonResponse(
        { error: 'Original row has no source_id; cannot reconstruct payload' },
        400,
      )
    }
    const { data: notif, error: notifErr } = await admin
      .from('user_now_playing_notifications')
      .select('album_title, album_artist, cover_image_url, library_album_id, library_id, library_name, device_name')
      .eq('source_event_id', original.source_id)
      .eq('user_id', original.user_id)
      .maybeSingle()

    if (notifErr) {
      console.error('[retry-notification] Failed to load source notification:', notifErr)
      return jsonResponse({ error: 'Database error' }, 500)
    }
    if (!notif) {
      return jsonResponse(
        { error: 'Original now_playing notification row not found — cannot reconstruct payload' },
        400,
      )
    }

    const albumInfo: AlbumInfo | null = notif.album_title
      ? {
          library_album_id: notif.library_album_id ?? '',
          title: notif.album_title,
          artist: notif.album_artist ?? '',
          cover_image_url: notif.cover_image_url,
          library_id: notif.library_id ?? undefined,
          library_name: notif.library_name ?? undefined,
        }
      : null

    // 4. Send.
    const result = await sendFcmPush(
      buildNowPlayingPushArgs({
        tokenString: token.token,
        albumInfo,
        deviceName: notif.device_name ?? 'your device',
      }),
    )

    // 5. Insert a NEW delivery_log row (preserving the original failure for audit).
    const insertRow = {
      user_id: original.user_id,
      notification_type: original.notification_type,
      source_id: original.source_id,
      token_id: original.token_id,
      status: result.success ? 'sent' : 'failed',
      error_message: result.error ?? null,
      sent_at: result.success ? new Date().toISOString() : null,
      sent_by_user_id: caller.databaseUserId,
    }
    const { data: inserted, error: insertErr } = await admin
      .from('notification_delivery_log')
      .insert(insertRow)
      .select('id')
      .single()

    if (insertErr) {
      console.error('[retry-notification] Failed to insert delivery log:', insertErr)
      return jsonResponse({ error: 'Failed to log retry attempt' }, 500)
    }

    // 6. Same deactivation behavior as the primary path.
    if (!result.success && result.tokenShouldDeactivate) {
      await admin
        .from('push_notification_tokens')
        .update({ is_active: false })
        .eq('id', token.id)
    }

    return jsonResponse({
      success: result.success,
      delivery_log_id: inserted.id,
      ...(result.error ? { error: result.error } : {}),
      ...(result.errorCategory ? { error_category: result.errorCategory } : {}),
    })
  } catch (err) {
    console.error('[retry-notification] Unhandled error:', err)
    return jsonResponse({ error: (err as Error).message }, 500)
  }
})
