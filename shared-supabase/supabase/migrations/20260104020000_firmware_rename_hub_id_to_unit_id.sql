-- Phase 6: Rename hub_id to unit_id for device-agnostic naming
-- Saturday Vinyl Firmware
--
-- This migration renames hub_id columns to unit_id across all tables
-- to support a device-agnostic provisioning protocol.
--
-- Idempotent: Yes - safe to run multiple times, handles missing tables/columns

--------------------------------------------------------------------------------
-- Rename columns in now_playing_events table
--------------------------------------------------------------------------------
DO $$
BEGIN
  -- Rename hub_id -> unit_id if the old column still exists
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'now_playing_events' AND column_name = 'hub_id'
  ) THEN
    ALTER TABLE now_playing_events RENAME COLUMN hub_id TO unit_id;
  END IF;

  -- Only create indexes/comments if the table exists
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'now_playing_events'
  ) THEN
    -- Drop old indexes
    DROP INDEX IF EXISTS idx_now_playing_events_hub_id;
    DROP INDEX IF EXISTS idx_now_playing_events_hub_timestamp;

    -- Create new indexes
    CREATE INDEX IF NOT EXISTS idx_now_playing_events_unit_id
        ON now_playing_events(unit_id);
    CREATE INDEX IF NOT EXISTS idx_now_playing_events_unit_timestamp
        ON now_playing_events(unit_id, timestamp DESC);

    COMMENT ON COLUMN now_playing_events.unit_id IS 'Unique unit identifier for the Saturday device';
  END IF;
END $$;

--------------------------------------------------------------------------------
-- Rename columns in hub_heartbeats table (may have been dropped)
--------------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'hub_heartbeats'
  ) THEN
    -- Rename hub_id -> unit_id if the old column still exists
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_name = 'hub_heartbeats' AND column_name = 'hub_id'
    ) THEN
      ALTER TABLE hub_heartbeats RENAME COLUMN hub_id TO unit_id;
    END IF;

    -- Drop old indexes
    DROP INDEX IF EXISTS idx_hub_heartbeats_hub_id;
    DROP INDEX IF EXISTS idx_hub_heartbeats_hub_timestamp;

    -- Create new indexes
    CREATE INDEX IF NOT EXISTS idx_hub_heartbeats_unit_id
        ON hub_heartbeats(unit_id);
    CREATE INDEX IF NOT EXISTS idx_hub_heartbeats_unit_timestamp
        ON hub_heartbeats(unit_id, timestamp DESC);

    COMMENT ON COLUMN hub_heartbeats.unit_id IS 'Unique unit identifier for the Saturday device';
  END IF;
END $$;

--------------------------------------------------------------------------------
-- Update Views (only if underlying tables exist)
--------------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'now_playing_events'
  ) THEN
    DROP VIEW IF EXISTS current_now_playing;

    CREATE OR REPLACE VIEW current_now_playing AS
    SELECT DISTINCT ON (unit_id)
        unit_id,
        epc,
        event_type,
        rssi,
        timestamp as last_event_time,
        CASE
            WHEN event_type = 'placed' THEN true
            ELSE false
        END as is_playing
    FROM now_playing_events
    ORDER BY unit_id, timestamp DESC;

    COMMENT ON VIEW current_now_playing IS 'Shows the current playing status for each unit';
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'hub_heartbeats'
  ) THEN
    DROP VIEW IF EXISTS latest_hub_heartbeats;

    CREATE OR REPLACE VIEW latest_hub_heartbeats AS
    SELECT DISTINCT ON (unit_id)
        unit_id,
        firmware_version,
        wifi_rssi,
        uptime_sec,
        free_heap,
        events_queued,
        timestamp as last_seen,
        CASE
            WHEN timestamp > NOW() - INTERVAL '10 minutes' THEN 'online'
            WHEN timestamp > NOW() - INTERVAL '1 hour' THEN 'stale'
            ELSE 'offline'
        END as status
    FROM hub_heartbeats
    ORDER BY unit_id, timestamp DESC;

    COMMENT ON VIEW latest_hub_heartbeats IS 'Shows the latest heartbeat and online status for each unit';
  END IF;
END $$;
