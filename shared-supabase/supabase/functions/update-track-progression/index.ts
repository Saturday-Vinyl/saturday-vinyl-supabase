/**
 * Edge Function: update-track-progression
 * Project: saturday-mobile-app
 * Description: Calculates current track for active playback sessions and updates
 *              the session row. Designed to be called by a cron job (~30s interval)
 *              so that iOS Live Activities stay current even when the app is backgrounded.
 */

// Triggered by cron job (every 30 seconds)
//
// This function:
// 1. Queries all playback_sessions with status = 'playing'
// 2. For each session, calculates the current track from side_started_at + tracks JSONB
// 3. If the track index changed since last check, updates the session row
// 4. Sends ActivityKit push notifications to update Live Activities on iOS devices

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { sendActivityPush } from '../_shared/send-activity-push.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface Track {
  position: string
  title: string
  duration_seconds: number | null
}

interface PlayingSession {
  id: string
  user_id: string
  current_side: string
  side_started_at: string
  tracks: Track[] | null
  current_track_index: number | null
}

/**
 * Calculate the current track index based on elapsed time and track durations.
 *
 * Mirrors the logic in lib/utils/track_position_calculator.dart:
 * - Filters tracks to the current side
 * - Walks through tracks using their durations
 * - Falls back to average duration for tracks with null durations
 * - Returns -1 if track position cannot be determined
 */
function calculateCurrentTrackIndex(
  session: PlayingSession,
): { trackIndex: number; trackTitle: string; trackPosition: string } | null {
  const tracks = session.tracks
  if (!tracks || tracks.length === 0) return null

  // Filter to current side
  const sidePrefix = session.current_side.toUpperCase()
  const sideTracks = tracks.filter(
    (t) => t.position.trim().toUpperCase().startsWith(sidePrefix)
  )

  if (sideTracks.length === 0) return null

  // Calculate elapsed seconds
  const sideStartedAt = new Date(session.side_started_at)
  const now = new Date()
  const elapsedSeconds = Math.floor((now.getTime() - sideStartedAt.getTime()) / 1000)

  if (elapsedSeconds < 0) return null

  // Calculate average duration from known tracks (for filling gaps)
  const knownDurations = sideTracks
    .map((t) => t.duration_seconds)
    .filter((d): d is number => d != null && d > 0)

  if (knownDurations.length === 0) {
    // No durations known — can't calculate position
    return null
  }

  const avgDuration =
    knownDurations.reduce((sum, d) => sum + d, 0) / knownDurations.length

  // Walk through tracks to find current one
  let accumulated = 0
  for (let i = 0; i < sideTracks.length; i++) {
    const trackDuration = sideTracks[i].duration_seconds ?? avgDuration
    accumulated += trackDuration

    if (elapsedSeconds < accumulated) {
      return {
        trackIndex: i,
        trackTitle: sideTracks[i].title,
        trackPosition: sideTracks[i].position,
      }
    }
  }

  // Past all tracks — overtime, return last track
  const lastIdx = sideTracks.length - 1
  return {
    trackIndex: lastIdx,
    trackTitle: sideTracks[lastIdx].title,
    trackPosition: sideTracks[lastIdx].position,
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
      auth: { persistSession: false },
    })

    console.log('Starting track progression check...')

    // Step 1: Get all playing sessions with tracks and side_started_at
    const { data: sessions, error } = await supabase
      .from('playback_sessions')
      .select(
        'id, user_id, current_side, side_started_at, tracks, current_track_index'
      )
      .eq('status', 'playing')
      .not('side_started_at', 'is', null)
      .not('tracks', 'is', null)

    if (error) {
      console.error('Error fetching playing sessions:', error)
      return new Response(
        JSON.stringify({ error: error.message }),
        {
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (!sessions || sessions.length === 0) {
      console.log('No active playing sessions')
      return new Response(
        JSON.stringify({ success: true, updated: 0, total: 0 }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Found ${sessions.length} active playing sessions`)

    // Step 2: Calculate current track for each session
    let updated = 0
    let pushed = 0
    for (const session of sessions as PlayingSession[]) {
      const result = calculateCurrentTrackIndex(session)
      if (result === null) continue

      // Only update if track index changed
      if (result.trackIndex === session.current_track_index) continue

      const { error: updateError } = await supabase
        .from('playback_sessions')
        .update({
          current_track_index: result.trackIndex,
        })
        .eq('id', session.id)

      if (updateError) {
        console.error(
          `Error updating session ${session.id}:`,
          updateError
        )
        continue
      }

      updated++
      console.log(
        `Session ${session.id}: track ${result.trackPosition} "${result.trackTitle}" (index ${result.trackIndex})`
      )

      // Send ActivityKit push to update Live Activity on iOS devices
      const sentCount = await sendActivityPushForSession(supabase, session.id)
      pushed += sentCount
    }

    console.log(
      `Track progression check complete: ${updated} updated out of ${sessions.length} sessions`
    )

    return new Response(
      JSON.stringify({ success: true, updated, pushed, total: sessions.length }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Error in track progression:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})

/**
 * Send ActivityKit push notifications for a session's active push tokens.
 * The push triggers a widget refresh on the user's iOS device.
 */
async function sendActivityPushForSession(
  supabase: SupabaseClient,
  sessionId: string
): Promise<number> {
  const { data: tokens, error } = await supabase
    .from('activity_push_tokens')
    .select('id, push_token')
    .eq('session_id', sessionId)
    .eq('is_active', true)

  if (error || !tokens || tokens.length === 0) {
    return 0
  }

  let sent = 0
  for (const token of tokens) {
    const result = await sendActivityPush(token.push_token, {
      appGroupId: 'group.com.saturdayvinyl.consumer',
    })

    if (result.success) {
      sent++
    } else if (result.error === 'invalid_token') {
      // Deactivate invalid tokens
      await supabase
        .from('activity_push_tokens')
        .update({ is_active: false, updated_at: new Date().toISOString() })
        .eq('id', token.id)
      console.log(`Deactivated invalid activity token: ${token.id}`)
    }
  }

  return sent
}
