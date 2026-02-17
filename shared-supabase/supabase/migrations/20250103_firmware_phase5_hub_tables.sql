-- Phase 5: Supabase Integration - Hub Tables
-- Saturday Vinyl Hub Firmware
--
-- Run this migration in your Supabase SQL Editor:
-- https://supabase.com/dashboard/project/YOUR_PROJECT/sql/new

--------------------------------------------------------------------------------
-- Now Playing Events Table
-- Records when tags are placed on or removed from the turntable
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS now_playing_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hub_id TEXT NOT NULL,
    epc TEXT NOT NULL,                          -- 24-char hex string (e.g., "5356A1B2C3D4E5F67890ABCD")
    event_type TEXT NOT NULL CHECK (event_type IN ('placed', 'removed')),
    rssi INTEGER,                               -- Signal strength in dBm
    duration_ms INTEGER,                        -- Play duration (only for 'removed' events)
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for querying by hub
CREATE INDEX IF NOT EXISTS idx_now_playing_events_hub_id
    ON now_playing_events(hub_id);

-- Index for querying by EPC (record identifier)
CREATE INDEX IF NOT EXISTS idx_now_playing_events_epc
    ON now_playing_events(epc);

-- Index for time-based queries
CREATE INDEX IF NOT EXISTS idx_now_playing_events_timestamp
    ON now_playing_events(timestamp DESC);

-- Composite index for common query pattern
CREATE INDEX IF NOT EXISTS idx_now_playing_events_hub_timestamp
    ON now_playing_events(hub_id, timestamp DESC);

COMMENT ON TABLE now_playing_events IS 'Records when vinyl records are placed on or removed from turntables';
COMMENT ON COLUMN now_playing_events.hub_id IS 'Unique identifier for the Saturday Hub device';
COMMENT ON COLUMN now_playing_events.epc IS 'EPC tag identifier (96-bit as 24 hex chars)';
COMMENT ON COLUMN now_playing_events.event_type IS 'placed = record put on turntable, removed = record taken off';
COMMENT ON COLUMN now_playing_events.rssi IS 'RFID signal strength at time of detection';
COMMENT ON COLUMN now_playing_events.duration_ms IS 'How long the record was playing (only set on removed events)';

--------------------------------------------------------------------------------
-- Hub Heartbeats Table
-- Periodic health check pings from hub devices
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hub_heartbeats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hub_id TEXT NOT NULL,
    firmware_version TEXT,
    wifi_rssi INTEGER,                          -- Wi-Fi signal strength in dBm
    uptime_sec INTEGER,                         -- Seconds since boot
    free_heap INTEGER,                          -- Free heap memory in bytes
    events_queued INTEGER,                      -- Events waiting to be synced
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for querying by hub
CREATE INDEX IF NOT EXISTS idx_hub_heartbeats_hub_id
    ON hub_heartbeats(hub_id);

-- Index for time-based queries (get latest heartbeat)
CREATE INDEX IF NOT EXISTS idx_hub_heartbeats_timestamp
    ON hub_heartbeats(timestamp DESC);

-- Composite index for getting latest heartbeat per hub
CREATE INDEX IF NOT EXISTS idx_hub_heartbeats_hub_timestamp
    ON hub_heartbeats(hub_id, timestamp DESC);

COMMENT ON TABLE hub_heartbeats IS 'Periodic health check pings from Saturday Hub devices';
COMMENT ON COLUMN hub_heartbeats.hub_id IS 'Unique identifier for the Saturday Hub device';
COMMENT ON COLUMN hub_heartbeats.firmware_version IS 'Current firmware version running on hub';
COMMENT ON COLUMN hub_heartbeats.wifi_rssi IS 'Wi-Fi signal strength in dBm';
COMMENT ON COLUMN hub_heartbeats.uptime_sec IS 'Seconds since the hub was last rebooted';
COMMENT ON COLUMN hub_heartbeats.free_heap IS 'Available heap memory in bytes';
COMMENT ON COLUMN hub_heartbeats.events_queued IS 'Number of events waiting in queue to be synced';

--------------------------------------------------------------------------------
-- Row Level Security (RLS)
-- Enable RLS but allow inserts with anon key for device authentication
--------------------------------------------------------------------------------

-- Enable RLS on both tables
ALTER TABLE now_playing_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE hub_heartbeats ENABLE ROW LEVEL SECURITY;

-- Policy: Allow anonymous inserts (hub devices use anon key)
-- In production, you'd want device-specific auth, but for Phase 5 testing this works
CREATE POLICY "Allow anonymous inserts" ON now_playing_events
    FOR INSERT
    TO anon
    WITH CHECK (true);

CREATE POLICY "Allow anonymous inserts" ON hub_heartbeats
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- Policy: Allow authenticated users to read all data (for dashboard/app)
CREATE POLICY "Allow authenticated reads" ON now_playing_events
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Allow authenticated reads" ON hub_heartbeats
    FOR SELECT
    TO authenticated
    USING (true);

-- Optional: Allow anon to read too (useful for testing)
CREATE POLICY "Allow anonymous reads" ON now_playing_events
    FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "Allow anonymous reads" ON hub_heartbeats
    FOR SELECT
    TO anon
    USING (true);

--------------------------------------------------------------------------------
-- Useful Views
--------------------------------------------------------------------------------

-- View: Current "Now Playing" status per hub
CREATE OR REPLACE VIEW current_now_playing AS
SELECT DISTINCT ON (hub_id)
    hub_id,
    epc,
    event_type,
    rssi,
    timestamp as last_event_time,
    CASE
        WHEN event_type = 'placed' THEN true
        ELSE false
    END as is_playing
FROM now_playing_events
ORDER BY hub_id, timestamp DESC;

COMMENT ON VIEW current_now_playing IS 'Shows the current playing status for each hub';

-- View: Latest heartbeat per hub
CREATE OR REPLACE VIEW latest_hub_heartbeats AS
SELECT DISTINCT ON (hub_id)
    hub_id,
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
ORDER BY hub_id, timestamp DESC;

COMMENT ON VIEW latest_hub_heartbeats IS 'Shows the latest heartbeat and online status for each hub';

--------------------------------------------------------------------------------
-- Sample Queries (for reference)
--------------------------------------------------------------------------------

-- Get recent events for a specific hub:
-- SELECT * FROM now_playing_events
-- WHERE hub_id = 'HUB-TEST-001'
-- ORDER BY timestamp DESC
-- LIMIT 50;

-- Get play history for a specific record (EPC):
-- SELECT * FROM now_playing_events
-- WHERE epc = '5356A1B2C3D4E5F67890ABCD'
-- ORDER BY timestamp DESC;

-- Get all online hubs:
-- SELECT * FROM latest_hub_heartbeats WHERE status = 'online';

-- Get current playing status:
-- SELECT * FROM current_now_playing WHERE is_playing = true;
