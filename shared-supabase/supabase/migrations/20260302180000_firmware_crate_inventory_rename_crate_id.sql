-- ============================================================================
-- Migration: 20260302180000_firmware_crate_inventory_rename_crate_id.sql
-- Project: sv-hub-firmware
-- Description: Rename crate_inventory_events.crate_id to mac_address and
--              change type to varchar(17) for consistency with devices table.
--              The original column stored a Thread extended address (16 hex chars)
--              but should store the WiFi MAC (AA:BB:CC:DD:EE:FF) so rows are
--              joinable to devices.mac_address.
-- Date: 2026-03-02
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

--------------------------------------------------------------------------------
-- Step 1: Drop the dependent view so we can alter the column
--------------------------------------------------------------------------------
DROP VIEW IF EXISTS latest_crate_inventory;

--------------------------------------------------------------------------------
-- Step 2: Rename column (idempotent — check existence first)
--------------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'crate_inventory_events' AND column_name = 'crate_id'
    ) THEN
        ALTER TABLE crate_inventory_events RENAME COLUMN crate_id TO mac_address;
    END IF;
END $$;

--------------------------------------------------------------------------------
-- Step 3: Change type to varchar(17) to match devices.mac_address
--------------------------------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'crate_inventory_events'
          AND column_name = 'mac_address'
          AND data_type = 'text'
    ) THEN
        ALTER TABLE crate_inventory_events
            ALTER COLUMN mac_address TYPE character varying(17);
    END IF;
END $$;

--------------------------------------------------------------------------------
-- Step 4: Drop old indexes that reference crate_id, create new ones
--------------------------------------------------------------------------------

-- Drop old crate_id-based indexes
DROP INDEX IF EXISTS idx_crate_inventory_events_crate_id;
DROP INDEX IF EXISTS idx_crate_inventory_events_crate_timestamp;

-- Create replacement indexes on mac_address
CREATE INDEX IF NOT EXISTS idx_crate_inventory_events_mac_address
    ON crate_inventory_events(mac_address);

CREATE INDEX IF NOT EXISTS idx_crate_inventory_events_mac_timestamp
    ON crate_inventory_events(mac_address, timestamp DESC);

--------------------------------------------------------------------------------
-- Step 5: Update column comment
--------------------------------------------------------------------------------
COMMENT ON COLUMN crate_inventory_events.mac_address IS 'WiFi MAC address of the crate (AA:BB:CC:DD:EE:FF format, matches devices.mac_address)';

--------------------------------------------------------------------------------
-- Step 6: Recreate view with new column name
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW latest_crate_inventory AS
SELECT DISTINCT ON (mac_address)
    mac_address,
    unit_id,
    epcs,
    epc_count,
    timestamp AS last_scan_time,
    created_at
FROM crate_inventory_events
ORDER BY mac_address, timestamp DESC;

COMMENT ON VIEW latest_crate_inventory IS 'Most recent RFID inventory snapshot per crate';

--------------------------------------------------------------------------------
-- Step 7: Delete any rows with old Thread extended address format (16 hex chars
-- with no colons). These are not joinable and were from the pre-fix firmware.
-- New rows will have colon-separated MAC format (AA:BB:CC:DD:EE:FF).
--------------------------------------------------------------------------------
DELETE FROM crate_inventory_events
WHERE mac_address !~ '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$';
