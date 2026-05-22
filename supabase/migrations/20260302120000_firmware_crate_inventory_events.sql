-- ============================================================================
-- Migration: 20260302120000_firmware_crate_inventory_events.sql
-- Project: sv-hub-firmware
-- Description: Create crate_inventory_events table for RFID inventory snapshots
--              relayed from Thread-connected crates via the Hub
-- Date: 2026-03-02
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

--------------------------------------------------------------------------------
-- Crate Inventory Events Table
-- Records RFID inventory snapshots from Thread-connected crates.
-- Each row is a point-in-time snapshot of all EPCs visible to a crate's reader.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS crate_inventory_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    unit_id TEXT NOT NULL,                         -- Hub serial number that relayed the event
    crate_id TEXT NOT NULL,                        -- 16-char hex extended MAC of the crate
    epcs TEXT[] NOT NULL,                          -- Array of 24-char hex EPC strings
    epc_count INTEGER NOT NULL,                    -- Number of EPCs in this snapshot
    timestamp TIMESTAMPTZ NOT NULL,                -- Firmware-reported scan time
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()  -- Server insertion time
);

-- Index for filtering by crate
CREATE INDEX IF NOT EXISTS idx_crate_inventory_events_crate_id
    ON crate_inventory_events(crate_id);

-- Index for filtering by hub
CREATE INDEX IF NOT EXISTS idx_crate_inventory_events_unit_id
    ON crate_inventory_events(unit_id);

-- Index for recent events
CREATE INDEX IF NOT EXISTS idx_crate_inventory_events_timestamp
    ON crate_inventory_events(timestamp DESC);

-- Composite index for latest inventory per crate (most common query)
CREATE INDEX IF NOT EXISTS idx_crate_inventory_events_crate_timestamp
    ON crate_inventory_events(crate_id, timestamp DESC);

-- GIN index for containment queries ("which crate has this EPC?")
CREATE INDEX IF NOT EXISTS idx_crate_inventory_events_epcs
    ON crate_inventory_events USING GIN (epcs);

COMMENT ON TABLE crate_inventory_events IS 'RFID inventory snapshots from Thread-connected crates, relayed via the Hub';
COMMENT ON COLUMN crate_inventory_events.unit_id IS 'Serial number of the Hub that relayed this event';
COMMENT ON COLUMN crate_inventory_events.crate_id IS 'Extended MAC address of the crate (16 hex chars)';
COMMENT ON COLUMN crate_inventory_events.epcs IS 'Array of EPC identifiers visible to the crate reader (96-bit as 24 hex chars each)';
COMMENT ON COLUMN crate_inventory_events.epc_count IS 'Number of EPCs in this snapshot';
COMMENT ON COLUMN crate_inventory_events.timestamp IS 'When the crate performed the RFID scan';

--------------------------------------------------------------------------------
-- Row Level Security (RLS)
-- Follows now_playing_events pattern: anon INSERT, anon + authenticated SELECT
--------------------------------------------------------------------------------

ALTER TABLE crate_inventory_events ENABLE ROW LEVEL SECURITY;

-- Policy: Allow anonymous inserts (hub devices use anon key)
DROP POLICY IF EXISTS "Allow anonymous inserts" ON crate_inventory_events;
CREATE POLICY "Allow anonymous inserts" ON crate_inventory_events
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- Policy: Allow authenticated users to read all data
DROP POLICY IF EXISTS "Allow authenticated reads" ON crate_inventory_events;
CREATE POLICY "Allow authenticated reads" ON crate_inventory_events
    FOR SELECT
    TO authenticated
    USING (true);

-- Policy: Allow anon reads (useful for testing)
DROP POLICY IF EXISTS "Allow anonymous reads" ON crate_inventory_events;
CREATE POLICY "Allow anonymous reads" ON crate_inventory_events
    FOR SELECT
    TO anon
    USING (true);

--------------------------------------------------------------------------------
-- View: Latest inventory snapshot per crate
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW latest_crate_inventory AS
SELECT DISTINCT ON (crate_id)
    crate_id,
    unit_id,
    epcs,
    epc_count,
    timestamp AS last_scan_time,
    created_at
FROM crate_inventory_events
ORDER BY crate_id, timestamp DESC;

COMMENT ON VIEW latest_crate_inventory IS 'Most recent RFID inventory snapshot per crate';
