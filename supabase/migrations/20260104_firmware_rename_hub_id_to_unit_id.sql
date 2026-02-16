-- Phase 6: Rename hub_id to unit_id for device-agnostic naming
-- Saturday Vinyl Firmware
--
-- This migration renames hub_id columns to unit_id across all tables
-- to support a device-agnostic provisioning protocol.
--
-- Run this migration in your Supabase SQL Editor:
-- https://supabase.com/dashboard/project/YOUR_PROJECT/sql/new

--------------------------------------------------------------------------------
-- Rename columns in now_playing_events table
--------------------------------------------------------------------------------

-- Rename the column
ALTER TABLE now_playing_events RENAME COLUMN hub_id TO unit_id;

-- Drop old indexes (they reference the old column name)
DROP INDEX IF EXISTS idx_now_playing_events_hub_id;
DROP INDEX IF EXISTS idx_now_playing_events_hub_timestamp;

-- Create new indexes with updated names
CREATE INDEX IF NOT EXISTS idx_now_playing_events_unit_id
    ON now_playing_events(unit_id);

CREATE INDEX IF NOT EXISTS idx_now_playing_events_unit_timestamp
    ON now_playing_events(unit_id, timestamp DESC);

-- Update column comment
COMMENT ON COLUMN now_playing_events.unit_id IS 'Unique unit identifier for the Saturday device';

--------------------------------------------------------------------------------
-- Rename columns in hub_heartbeats table
-- Note: Table name kept as hub_heartbeats for backwards compatibility,
-- but could be renamed to unit_heartbeats in a future migration
--------------------------------------------------------------------------------

-- Rename the column
ALTER TABLE hub_heartbeats RENAME COLUMN hub_id TO unit_id;

-- Drop old indexes
DROP INDEX IF EXISTS idx_hub_heartbeats_hub_id;
DROP INDEX IF EXISTS idx_hub_heartbeats_hub_timestamp;

-- Create new indexes
CREATE INDEX IF NOT EXISTS idx_hub_heartbeats_unit_id
    ON hub_heartbeats(unit_id);

CREATE INDEX IF NOT EXISTS idx_hub_heartbeats_unit_timestamp
    ON hub_heartbeats(unit_id, timestamp DESC);

-- Update column comment
COMMENT ON COLUMN hub_heartbeats.unit_id IS 'Unique unit identifier for the Saturday device';

--------------------------------------------------------------------------------
-- Update Views
--------------------------------------------------------------------------------

-- Drop and recreate current_now_playing view
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

-- Drop and recreate latest_hub_heartbeats view
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

--------------------------------------------------------------------------------
-- Done
--------------------------------------------------------------------------------
-- Note: This is a backwards-compatible change. The table names remain the same
-- but the column names are updated. If you need to rename the tables themselves
-- (hub_heartbeats -> unit_heartbeats), that should be done in a separate migration
-- with proper application coordination.
