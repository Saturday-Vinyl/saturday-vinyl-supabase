-- ============================================================================
-- Migration: 20260612120000_shared_event_driven_playback_sessions.sql
-- Project: shared
-- Description: Playback event protocol v2.
--
--              Sessions now live as long as the record is on the stand.
--              `playback_stopped` and `side_changed` both become non-terminal:
--              they transition the session from `playing` to `queued` and
--              accumulate the just-elapsed play window into a new
--              `play_seconds_total` column. `session_cancelled` is the
--              only terminal event.
--
--              Producers stop UPDATEing `playback_sessions` for state
--              transitions; they INSERT canonical events and the new
--              `apply_playback_event` trigger derives session state from
--              them. Track-progression columns and `queueSession`'s initial
--              INSERT are the only direct mutations producers still
--              perform.
--
--              The existing listening-history sync trigger is updated to
--              attribute duration on `session_cancelled` (using the
--              accumulated `play_seconds_total`) instead of
--              `playback_stopped`.
-- Date: 2026-06-12
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Schema: accumulated play time across multiple play windows
-- ----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'playback_sessions' AND column_name = 'play_seconds_total'
  ) THEN
    ALTER TABLE playback_sessions
      ADD COLUMN play_seconds_total integer NOT NULL DEFAULT 0;
  END IF;
END $$;

COMMENT ON COLUMN playback_sessions.play_seconds_total IS
'Sum of all play-window durations (in seconds) for this session. Accumulated by the apply_playback_event trigger on every side_changed, playback_stopped, and session_cancelled event that closes an open play window. Canonical "minutes listened" value — superior to ended_at - started_at, which over-counts pause gaps.';

-- ----------------------------------------------------------------------------
-- 2. Trigger function: derive session state from canonical events
-- ----------------------------------------------------------------------------
--
-- Fires AFTER INSERT on playback_events. The single source of truth for
-- status, side_started_at, started_at, ended_at, and play_seconds_total
-- transitions. Producers MUST NOT UPDATE these columns directly.
--
-- Event semantics:
--   session_queued     — session row is INSERTed by the producer in the
--                        same transaction; trigger is a no-op.
--   playback_started   — status: playing. started_at preserved on resume
--                        (COALESCE). side_started_at: now.
--   side_changed       — status: queued. current_side updated from
--                        payload. side_started_at: NULL. Accumulate any
--                        open window into play_seconds_total.
--   playback_stopped   — status: queued. Same current_side. side_started_at:
--                        NULL. Accumulate any open window.
--   session_cancelled  — status: cancelled. ended_at: now. side_started_at:
--                        NULL. Accumulate any open window (handles the
--                        "cancel arrives while playing" case in one pass).
--
-- SECURITY DEFINER + search_path: matches the pattern of the sibling
-- listening-history trigger so service-role and limited-grant producers
-- both have their events applied to the session row.

CREATE OR REPLACE FUNCTION apply_playback_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_window_seconds integer;
  v_payload_side   text;
BEGIN
  CASE NEW.event_type

    WHEN 'session_queued' THEN
      -- The session row is INSERTed by the producer in the same
      -- transaction. Nothing more to derive here.
      NULL;

    WHEN 'playback_started' THEN
      UPDATE playback_sessions
         SET status                = 'playing',
             started_at            = COALESCE(started_at, NEW.created_at),
             side_started_at       = NEW.created_at,
             started_by_source     = NEW.source_type,
             started_by_device_id  = NEW.source_device_id,
             updated_at            = now()
       WHERE id = NEW.session_id;

    WHEN 'side_changed' THEN
      v_payload_side := NEW.payload->>'side';
      UPDATE playback_sessions
         SET play_seconds_total = play_seconds_total + GREATEST(0,
               COALESCE(EXTRACT(EPOCH FROM (NEW.created_at - side_started_at))::integer, 0)),
             current_side       = COALESCE(v_payload_side, current_side),
             status             = 'queued',
             side_started_at    = NULL,
             updated_at         = now()
       WHERE id = NEW.session_id;

    WHEN 'playback_stopped' THEN
      UPDATE playback_sessions
         SET play_seconds_total = play_seconds_total + GREATEST(0,
               COALESCE(EXTRACT(EPOCH FROM (NEW.created_at - side_started_at))::integer, 0)),
             status             = 'queued',
             side_started_at    = NULL,
             updated_at         = now()
       WHERE id = NEW.session_id;

    WHEN 'session_cancelled' THEN
      UPDATE playback_sessions
         SET play_seconds_total = play_seconds_total + GREATEST(0,
               COALESCE(EXTRACT(EPOCH FROM (NEW.created_at - side_started_at))::integer, 0)),
             status             = 'cancelled',
             ended_at           = NEW.created_at,
             side_started_at    = NULL,
             updated_at         = now()
       WHERE id = NEW.session_id;

    ELSE
      -- Unknown event_type — the CHECK constraint should prevent this,
      -- but ignore rather than fail if a new event type is rolled out
      -- ahead of this trigger.
      NULL;
  END CASE;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION apply_playback_event() IS
'v2 protocol: derives playback_sessions state (status, started_at, side_started_at, ended_at, play_seconds_total, current_side) from canonical playback_events. Producers MUST NOT UPDATE these columns directly — emit events instead.';

-- Triggers fire AFTER INSERT in alphabetical order. The desired sequence is:
--   on_playback_event_apply                       (this — session state)
--   on_playback_event_broadcast                   (existing — hub fan-out)
--   on_playback_event_sync_listening_history      (existing — listening history)
-- The listening-history trigger reads playback_sessions, so it must run
-- after the apply trigger to see updated state. The alphabetical order
-- already gives us that ordering.

DROP TRIGGER IF EXISTS on_playback_event_apply ON playback_events;
CREATE TRIGGER on_playback_event_apply
  AFTER INSERT ON playback_events
  FOR EACH ROW
  EXECUTE FUNCTION apply_playback_event();

-- ----------------------------------------------------------------------------
-- 3. Listening-history sync trigger: attribute on session_cancelled
-- ----------------------------------------------------------------------------
--
-- Replaces the v1 behavior that attributed duration on `playback_stopped`.
-- Under v2:
--   playback_started  - first one for the session INSERTs the row.
--                       Subsequent resumes are no-ops via ON CONFLICT.
--   side_changed      - no-op (mid-session pause).
--   playback_stopped  - no-op (mid-session pause).
--   session_cancelled - UPDATE play_duration_seconds from session's
--                       accumulated play_seconds_total, plus completed_side.

CREATE OR REPLACE FUNCTION sync_listening_history_from_playback_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_session playback_sessions%ROWTYPE;
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

  ELSIF NEW.event_type = 'session_cancelled' THEN
    SELECT * INTO v_session FROM playback_sessions WHERE id = NEW.session_id;

    -- Sessions that were never started (queued → cancelled) have nothing
    -- to attribute; skip cleanly.
    IF v_session.started_at IS NULL THEN
      RETURN NEW;
    END IF;

    UPDATE listening_history
       SET play_duration_seconds = v_session.play_seconds_total,
           completed_side        = v_session.current_side::record_side
     WHERE session_id = NEW.session_id;
  END IF;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION sync_listening_history_from_playback_event() IS
'v2 protocol: maintains listening_history from canonical playback_events. Inserts on first playback_started, updates duration (from session.play_seconds_total) and completed_side on session_cancelled. Producers do not write listening_history directly.';

-- ----------------------------------------------------------------------------
-- 4. Notes on legacy `stopped` status
-- ----------------------------------------------------------------------------
--
-- The schema's valid_status CHECK constraint still allows 'stopped'. No
-- v2 producer or trigger ever writes it; pre-v2 rows retain their value
-- and their duration backfill from
-- 20260520120000_shared_listening_history_from_playback_events.sql.
--
-- Read-side consumers SHOULD treat 'stopped' as equivalent to 'cancelled'
-- (both indicate a terminated session).
