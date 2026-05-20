-- ============================================================================
-- Migration: 20260520120000_shared_listening_history_from_playback_events.sql
-- Project: shared
-- Description: Cloud-canonical attribution of listening_history from playback
--              events. A server-side trigger on playback_events INSERT creates
--              the listening_history row on playback_started and updates it
--              (duration, completed side) on playback_stopped. Producers
--              (app, hub, edge fns, future clients) no longer need to write
--              listening_history directly — they just emit canonical events.
--
--              Also backfills duration and session linkage for existing
--              stopped playback_sessions so the analytics dashboard catches
--              up with historical data.
-- Date: 2026-05-20
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Schema: link listening_history to playback_sessions
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'listening_history' AND column_name = 'session_id'
  ) THEN
    ALTER TABLE listening_history
      ADD COLUMN session_id UUID REFERENCES playback_sessions(id) ON DELETE SET NULL;
  END IF;
END $$;

-- Each session yields at most one history row. Pre-trigger rows keep NULL.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'idx_listening_history_session_id_unique'
  ) THEN
    CREATE UNIQUE INDEX idx_listening_history_session_id_unique
      ON listening_history (session_id)
      WHERE session_id IS NOT NULL;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2. Trigger function: attribute listening_history from playback_events
-- ----------------------------------------------------------------------------
--
-- Fires AFTER INSERT on playback_events. Handles two event types:
--   - playback_started: INSERT a listening_history row keyed by session_id.
--   - playback_stopped: UPDATE play_duration_seconds and completed_side
--                       on the row created at playback_started.
--
-- Duration is computed from NEW.created_at - playback_sessions.started_at
-- so we do not depend on the producer having updated playback_sessions.ended_at
-- before inserting the event.
--
-- SECURITY DEFINER + search_path: lets the trigger write listening_history
-- regardless of the producer's RLS context (e.g. hubs publishing via service
-- role, or future producers with limited grants).

CREATE OR REPLACE FUNCTION sync_listening_history_from_playback_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_session playback_sessions%ROWTYPE;
  v_duration INTEGER;
BEGIN
  IF NEW.event_type = 'playback_started' THEN
    SELECT * INTO v_session FROM playback_sessions WHERE id = NEW.session_id;

    -- Only attribute plays of real albums. A session without library_album_id
    -- is unusual but possible (deleted album); skip rather than fail.
    IF v_session.library_album_id IS NULL THEN
      RETURN NEW;
    END IF;

    INSERT INTO listening_history (
      user_id,
      library_album_id,
      played_at,
      session_id
    )
    VALUES (
      NEW.user_id,
      v_session.library_album_id,
      COALESCE(v_session.started_at, NEW.created_at),
      NEW.session_id
    )
    ON CONFLICT (session_id) WHERE session_id IS NOT NULL DO NOTHING;

  ELSIF NEW.event_type = 'playback_stopped' THEN
    SELECT * INTO v_session FROM playback_sessions WHERE id = NEW.session_id;

    IF v_session.started_at IS NULL THEN
      RETURN NEW;
    END IF;

    v_duration := GREATEST(
      0,
      EXTRACT(EPOCH FROM (NEW.created_at - v_session.started_at))::INTEGER
    );

    UPDATE listening_history
       SET play_duration_seconds = v_duration,
           completed_side = v_session.current_side::record_side
     WHERE session_id = NEW.session_id;
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION sync_listening_history_from_playback_event() IS
'Maintains listening_history from canonical playback_events: inserts on playback_started, updates duration and completed_side on playback_stopped. Producers should not write listening_history directly.';

DROP TRIGGER IF EXISTS on_playback_event_sync_listening_history ON playback_events;
CREATE TRIGGER on_playback_event_sync_listening_history
  AFTER INSERT ON playback_events
  FOR EACH ROW
  EXECUTE FUNCTION sync_listening_history_from_playback_event();

-- ----------------------------------------------------------------------------
-- 3. Backfill: attribute duration on existing stopped playback_sessions
-- ----------------------------------------------------------------------------
--
-- Until now the consumer app inserted a listening_history row on play-start
-- with NULL duration. For every stopped session with a started_at + ended_at,
-- we try to find the matching pre-existing listening_history row (same user
-- + album, played_at within 5 minutes of started_at, no session linkage yet)
-- and update it in place. Sessions with no matching history row get a fresh
-- listening_history row inserted.

-- 3a. Update matching pre-existing rows.
WITH stopped_sessions AS (
  SELECT ps.id            AS session_id,
         ps.user_id,
         ps.library_album_id,
         ps.started_at,
         ps.ended_at,
         ps.current_side,
         GREATEST(0, EXTRACT(EPOCH FROM (ps.ended_at - ps.started_at))::INTEGER) AS duration_seconds
    FROM playback_sessions ps
   WHERE ps.status = 'stopped'
     AND ps.library_album_id IS NOT NULL
     AND ps.started_at IS NOT NULL
     AND ps.ended_at   IS NOT NULL
),
matched AS (
  SELECT DISTINCT ON (ss.session_id)
         ss.session_id,
         ss.duration_seconds,
         ss.current_side,
         lh.id AS history_id
    FROM stopped_sessions ss
    JOIN listening_history lh
      ON lh.user_id          = ss.user_id
     AND lh.library_album_id = ss.library_album_id
     AND lh.session_id       IS NULL
     AND lh.played_at BETWEEN ss.started_at - INTERVAL '5 minutes'
                          AND ss.started_at + INTERVAL '5 minutes'
   ORDER BY ss.session_id,
            ABS(EXTRACT(EPOCH FROM (lh.played_at - ss.started_at)))
)
UPDATE listening_history lh
   SET session_id            = m.session_id,
       play_duration_seconds = m.duration_seconds,
       completed_side        = m.current_side::record_side
  FROM matched m
 WHERE lh.id = m.history_id;

-- 3b. Insert listening_history rows for stopped sessions that didn't match.
INSERT INTO listening_history (
  user_id,
  library_album_id,
  played_at,
  session_id,
  play_duration_seconds,
  completed_side
)
SELECT ps.user_id,
       ps.library_album_id,
       ps.started_at,
       ps.id,
       GREATEST(0, EXTRACT(EPOCH FROM (ps.ended_at - ps.started_at))::INTEGER),
       ps.current_side::record_side
  FROM playback_sessions ps
 WHERE ps.status            = 'stopped'
   AND ps.library_album_id IS NOT NULL
   AND ps.started_at       IS NOT NULL
   AND ps.ended_at         IS NOT NULL
   AND NOT EXISTS (
     SELECT 1 FROM listening_history lh WHERE lh.session_id = ps.id
   );
