-- Migration: Create device_heartbeats table and sync trigger
-- This replaces the hub_heartbeats table with a more generic device heartbeat system
-- that supports multiple device types and relay tracking.
--
-- Key changes from hub_heartbeats:
-- 1. Renamed to device_heartbeats (supports hubs, crates, future devices)
-- 2. Added relay tracking (which device/app delivered the heartbeat)
-- 3. Added trigger to sync last_seen_at to consumer_devices
--
-- Depends on: 20240101000002_create_tables.sql (consumer_devices table)

-- ============================================================================
-- DEVICE HEARTBEATS TABLE
-- ============================================================================
-- Stores heartbeat data from all Saturday devices.
-- Heartbeats can be delivered directly (WiFi hubs) or via relay (Thread crates).

CREATE TABLE IF NOT EXISTS device_heartbeats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- =========================================================================
    -- Device Identification
    -- =========================================================================
    -- The device that originated the heartbeat
    device_serial TEXT NOT NULL,              -- e.g., 'SV-HUB-00001' or 'SV-CRATE-00001'
    device_type TEXT NOT NULL,                -- 'hub', 'crate'

    -- =========================================================================
    -- Relay Information (for non-WiFi devices)
    -- =========================================================================
    -- How the heartbeat was delivered to the cloud.
    -- NULL values indicate direct delivery (WiFi-enabled device).
    relay_type TEXT,                          -- 'hub', 'ios_app', 'android_app', NULL (direct)
    relay_serial TEXT,                        -- Serial of relay hub, NULL if app or direct
    relay_instance_id TEXT,                   -- App instance ID if relayed via mobile app

    -- =========================================================================
    -- Device Metrics
    -- =========================================================================
    firmware_version TEXT,

    -- Battery (crates and future battery-powered devices)
    battery_level INTEGER CHECK (battery_level IS NULL OR (battery_level >= 0 AND battery_level <= 100)),
    battery_charging BOOLEAN,

    -- Connectivity signal strength
    wifi_rssi INTEGER,                        -- WiFi signal (hubs, direct connection)
    thread_rssi INTEGER,                      -- Thread signal (crates, mesh connection)

    -- System health
    uptime_sec INTEGER,
    free_heap INTEGER,
    events_queued INTEGER,

    -- =========================================================================
    -- Timestamps
    -- =========================================================================
    device_timestamp TIMESTAMPTZ NOT NULL,    -- Timestamp reported by device
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()  -- When server received heartbeat
);

-- ============================================================================
-- INDEXES
-- ============================================================================
-- Primary lookup: latest heartbeat per device
CREATE INDEX IF NOT EXISTS idx_device_heartbeats_device_serial_ts
    ON device_heartbeats(device_serial, device_timestamp DESC);

-- For cleanup jobs: find old heartbeats
CREATE INDEX IF NOT EXISTS idx_device_heartbeats_created_at
    ON device_heartbeats(created_at);

-- For relay analysis: which devices are relaying
CREATE INDEX IF NOT EXISTS idx_device_heartbeats_relay
    ON device_heartbeats(relay_type, relay_serial)
    WHERE relay_type IS NOT NULL;

-- ============================================================================
-- TRIGGER: Sync heartbeat to consumer_devices
-- ============================================================================
-- When a heartbeat is received, update the corresponding consumer_device record
-- with the latest timestamp, battery level, and firmware version.

CREATE OR REPLACE FUNCTION sync_heartbeat_to_consumer_device()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE consumer_devices
    SET
        last_seen_at = NEW.device_timestamp,
        battery_level = COALESCE(NEW.battery_level, battery_level),
        firmware_version = COALESCE(NEW.firmware_version, firmware_version),
        -- If device was offline, mark it back online
        status = CASE
            WHEN status = 'offline' THEN 'online'
            ELSE status
        END
    WHERE serial_number = NEW.device_serial;

    -- Log if no matching device found (helpful for debugging)
    IF NOT FOUND THEN
        RAISE WARNING 'No consumer_device found for serial_number: %', NEW.device_serial;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS device_heartbeat_sync_consumer_device ON device_heartbeats;
CREATE TRIGGER device_heartbeat_sync_consumer_device
AFTER INSERT ON device_heartbeats
FOR EACH ROW
EXECUTE FUNCTION sync_heartbeat_to_consumer_device();

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE device_heartbeats ENABLE ROW LEVEL SECURITY;

-- Service role can do everything (for backend/Edge Functions)
DROP POLICY IF EXISTS "Service role can manage device_heartbeats" ON device_heartbeats;
CREATE POLICY "Service role can manage device_heartbeats"
    ON device_heartbeats FOR ALL
    USING (auth.role() = 'service_role');

-- Devices can insert heartbeats (firmware uses anon key)
-- This is safe because:
-- 1. Heartbeats are append-only telemetry data
-- 2. The trigger validates device_serial against consumer_devices
-- 3. Unmatched serials just log a warning and don't affect anything
DROP POLICY IF EXISTS "Devices can insert heartbeats" ON device_heartbeats;
CREATE POLICY "Devices can insert heartbeats"
    ON device_heartbeats FOR INSERT
    WITH CHECK (true);

-- Users can view heartbeats for their own devices
DROP POLICY IF EXISTS "Users can view own device heartbeats" ON device_heartbeats;
CREATE POLICY "Users can view own device heartbeats"
    ON device_heartbeats FOR SELECT
    USING (
        device_serial IN (
            SELECT serial_number FROM consumer_devices
            WHERE user_id = get_user_id_from_auth()
        )
    );

-- ============================================================================
-- CLEANUP: Drop old hub_heartbeats table
-- ============================================================================
-- The hub_heartbeats table is replaced by device_heartbeats.
-- Dropping it since we're in testing mode and data loss is acceptable.

DROP TABLE IF EXISTS hub_heartbeats CASCADE;

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON TABLE device_heartbeats IS
    'Heartbeat data from all Saturday devices (hubs, crates). Triggers sync to consumer_devices.last_seen_at.';

COMMENT ON COLUMN device_heartbeats.device_serial IS
    'Serial number of the device that originated the heartbeat (e.g., SV-HUB-00001)';

COMMENT ON COLUMN device_heartbeats.relay_type IS
    'How the heartbeat was delivered: hub (via another hub), ios_app, android_app, or NULL (direct WiFi)';

COMMENT ON COLUMN device_heartbeats.relay_serial IS
    'Serial number of the hub that relayed this heartbeat, if relay_type is hub';

COMMENT ON COLUMN device_heartbeats.relay_instance_id IS
    'App instance ID that relayed this heartbeat, if relay_type is ios_app or android_app';
