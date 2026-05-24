-- Phase 2: Cloud Playback Sessions
-- Creates playback_sessions (state snapshot) and playback_events (append-only log)
-- for cloud-connected playback sync across devices.

-- =============================================================================
-- playback_sessions
-- =============================================================================

CREATE TABLE IF NOT EXISTS playback_sessions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  library_album_id    uuid REFERENCES library_albums(id) ON DELETE SET NULL,

  -- Album metadata (denormalized for widgets/notifications/hubs)
  album_title         text,
  album_artist        text,
  cover_image_url     text,

  -- Playback state
  status              text NOT NULL DEFAULT 'queued',
  current_side        text NOT NULL DEFAULT 'A',
  side_started_at     timestamptz,  -- NULL when queued, set when playing

  -- Current track (derived, updated periodically by app or cron)
  current_track_index    int,
  current_track_position text,   -- e.g. "A3"
  current_track_title    text,   -- e.g. "Blue in Green"

  -- Track data snapshot (JSONB array of current side's tracks)
  tracks              jsonb,
  side_a_duration_seconds int,
  side_b_duration_seconds int,

  -- Source tracking
  queued_by_source    text NOT NULL DEFAULT 'app',     -- app | hub | web | api
  queued_by_device_id uuid REFERENCES units(id) ON DELETE SET NULL,
  started_by_source   text,                             -- app | hub | web | api
  started_by_device_id uuid REFERENCES units(id) ON DELETE SET NULL,

  -- Timestamps
  started_at          timestamptz,  -- when playback_started (not when queued)
  ended_at            timestamptz,
  updated_at          timestamptz NOT NULL DEFAULT now(),
  created_at          timestamptz NOT NULL DEFAULT now(),

  -- Constraints
  CONSTRAINT valid_status CHECK (status IN ('queued', 'playing', 'stopped', 'cancelled')),
  CONSTRAINT valid_side CHECK (current_side IN ('A', 'B', 'C', 'D')),
  CONSTRAINT valid_queued_source CHECK (queued_by_source IN ('app', 'hub', 'web', 'api')),
  CONSTRAINT valid_started_source CHECK (started_by_source IS NULL OR started_by_source IN ('app', 'hub', 'web', 'api'))
);

-- Max 1 playing session per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_playback_sessions_active_playing
  ON playback_sessions (user_id) WHERE status = 'playing';

-- Max 1 queued session per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_playback_sessions_active_queued
  ON playback_sessions (user_id) WHERE status = 'queued';

-- Fast lookup by user + status
CREATE INDEX IF NOT EXISTS idx_playback_sessions_user_status
  ON playback_sessions (user_id, status);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_playback_session_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS playback_sessions_updated_at ON playback_sessions;
CREATE TRIGGER playback_sessions_updated_at
  BEFORE UPDATE ON playback_sessions
  FOR EACH ROW EXECUTE FUNCTION update_playback_session_timestamp();

-- RLS
ALTER TABLE playback_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "playback_sessions_select" ON playback_sessions;
CREATE POLICY "playback_sessions_select" ON playback_sessions
  FOR SELECT USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_sessions_insert" ON playback_sessions;
CREATE POLICY "playback_sessions_insert" ON playback_sessions
  FOR INSERT WITH CHECK (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_sessions_update" ON playback_sessions;
CREATE POLICY "playback_sessions_update" ON playback_sessions
  FOR UPDATE USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_sessions_delete" ON playback_sessions;
CREATE POLICY "playback_sessions_delete" ON playback_sessions
  FOR DELETE USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_sessions_service" ON playback_sessions;
CREATE POLICY "playback_sessions_service" ON playback_sessions
  FOR ALL USING (auth.role() = 'service_role');

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE playback_sessions;

-- =============================================================================
-- playback_events
-- =============================================================================

CREATE TABLE IF NOT EXISTS playback_events (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id        uuid NOT NULL REFERENCES playback_sessions(id) ON DELETE CASCADE,
  user_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  event_type        text NOT NULL,
  payload           jsonb DEFAULT '{}',

  source_type       text NOT NULL DEFAULT 'app',
  source_device_id  uuid REFERENCES units(id) ON DELETE SET NULL,

  created_at        timestamptz NOT NULL DEFAULT now(),

  -- Constraints
  CONSTRAINT valid_event_type CHECK (event_type IN (
    'session_queued', 'side_changed', 'playback_started',
    'playback_stopped', 'session_cancelled'
  )),
  CONSTRAINT valid_source_type CHECK (source_type IN ('app', 'hub', 'web', 'api'))
);

-- Query events by session
CREATE INDEX IF NOT EXISTS idx_playback_events_session
  ON playback_events (session_id, created_at);

-- Subscribe to events by user (for Realtime filtering)
CREATE INDEX IF NOT EXISTS idx_playback_events_user
  ON playback_events (user_id, created_at);

-- RLS
ALTER TABLE playback_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "playback_events_select" ON playback_events;
CREATE POLICY "playback_events_select" ON playback_events
  FOR SELECT USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_events_insert" ON playback_events;
CREATE POLICY "playback_events_insert" ON playback_events
  FOR INSERT WITH CHECK (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "playback_events_service" ON playback_events;
CREATE POLICY "playback_events_service" ON playback_events
  FOR ALL USING (auth.role() = 'service_role');

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE playback_events;

-- =============================================================================
-- Trigger: Broadcast playback events to user's hubs
-- =============================================================================

-- When a playback event is inserted, broadcast to all hub device channels
-- owned by the session's user, using the same pg_notify pattern as device_commands.
CREATE OR REPLACE FUNCTION broadcast_playback_event_to_hubs()
RETURNS TRIGGER AS $$
DECLARE
  device_record RECORD;
  channel_name TEXT;
BEGIN
  -- Find all devices belonging to units owned by this user
  FOR device_record IN
    SELECT d.mac_address
    FROM devices d
    JOIN units u ON d.unit_id = u.id
    WHERE u.consumer_user_id = NEW.user_id
      AND u.is_online = true
  LOOP
    channel_name := 'device:' || REPLACE(device_record.mac_address, ':', '-');

    PERFORM pg_notify(
      'realtime:broadcast',
      json_build_object(
        'topic', channel_name,
        'event', 'broadcast',
        'payload', json_build_object(
          'event', 'playback_event',
          'payload', json_build_object(
            'event_type', NEW.event_type,
            'session_id', NEW.session_id,
            'payload', NEW.payload,
            'source_type', NEW.source_type,
            'created_at', NEW.created_at
          )
        )
      )::text
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_playback_event_broadcast ON playback_events;
CREATE TRIGGER on_playback_event_broadcast
  AFTER INSERT ON playback_events
  FOR EACH ROW EXECUTE FUNCTION broadcast_playback_event_to_hubs();
