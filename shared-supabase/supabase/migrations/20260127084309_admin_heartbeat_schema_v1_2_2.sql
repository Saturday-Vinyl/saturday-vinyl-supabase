-- ============================================================================
-- Migration: 20260127084309_heartbeat_schema_v1_2_2.sql
-- Description: Align device_heartbeats table with Device Command Protocol v1.2.2
-- Date: 2026-01-27
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- ADD NEW/MISSING COLUMNS
-- ============================================================================

-- Add unit_id column (protocol standard field - serial number from provisioning)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'unit_id'
  ) THEN
    ALTER TABLE device_heartbeats ADD COLUMN unit_id TEXT;
  END IF;
END $$;

-- Add mac_address column if not exists (protocol requires this as primary identifier)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'mac_address'
  ) THEN
    ALTER TABLE device_heartbeats ADD COLUMN mac_address VARCHAR(17);
  END IF;
END $$;

-- Add min_free_heap column (detects memory leaks - esp_get_minimum_free_heap_size())
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'min_free_heap'
  ) THEN
    ALTER TABLE device_heartbeats ADD COLUMN min_free_heap INTEGER;
  END IF;
END $$;

-- Add largest_free_block column (detects fragmentation - heap_caps_get_largest_free_block())
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'largest_free_block'
  ) THEN
    ALTER TABLE device_heartbeats ADD COLUMN largest_free_block INTEGER;
  END IF;
END $$;

-- ============================================================================
-- RENAME COLUMNS
-- ============================================================================

-- Rename relay_type to relay_device_type (device type slug of the relay providing the heartbeat)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'relay_type'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'relay_device_type'
  ) THEN
    ALTER TABLE device_heartbeats RENAME COLUMN relay_type TO relay_device_type;
  END IF;
END $$;

-- ============================================================================
-- DROP DEPRECATED COLUMNS
-- ============================================================================

-- Drop device_serial (replaced by unit_id - migrate data first, then drop policy, then column)
DO $$
BEGIN
  -- First migrate any data from device_serial to unit_id
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'device_serial'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'unit_id'
  ) THEN
    UPDATE device_heartbeats SET unit_id = device_serial WHERE unit_id IS NULL AND device_serial IS NOT NULL;
  END IF;
END $$;

-- Drop RLS policy that depends on device_serial before dropping column
DROP POLICY IF EXISTS "Users can view own device heartbeats" ON device_heartbeats;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'device_serial'
  ) THEN
    ALTER TABLE device_heartbeats DROP COLUMN device_serial;
  END IF;
END $$;

-- Drop relay_serial (not needed per protocol clarification)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'relay_serial'
  ) THEN
    ALTER TABLE device_heartbeats DROP COLUMN relay_serial;
  END IF;
END $$;

-- Drop events_queued (not in protocol standard fields)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'events_queued'
  ) THEN
    ALTER TABLE device_heartbeats DROP COLUMN events_queued;
  END IF;
END $$;

-- Drop uptime_ms (protocol v1.2.2 uses uptime_sec)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'uptime_ms'
  ) THEN
    ALTER TABLE device_heartbeats DROP COLUMN uptime_ms;
  END IF;
END $$;

-- ============================================================================
-- ADD COLUMN COMMENTS
-- ============================================================================

COMMENT ON COLUMN device_heartbeats.unit_id IS 'Device serial number from provisioning (e.g., SV-HUB-00001)';
COMMENT ON COLUMN device_heartbeats.mac_address IS 'Primary device identifier (AA:BB:CC:DD:EE:FF format)';
COMMENT ON COLUMN device_heartbeats.device_type IS 'Device type slug from firmware schema (e.g., hub, crate)';
COMMENT ON COLUMN device_heartbeats.firmware_version IS 'Current firmware version';
COMMENT ON COLUMN device_heartbeats.uptime_sec IS 'Device uptime in seconds since boot';
COMMENT ON COLUMN device_heartbeats.free_heap IS 'Current free heap memory in bytes';
COMMENT ON COLUMN device_heartbeats.min_free_heap IS 'Minimum free heap since boot in bytes (detects memory leaks)';
COMMENT ON COLUMN device_heartbeats.largest_free_block IS 'Largest contiguous free block in bytes (detects heap fragmentation)';
COMMENT ON COLUMN device_heartbeats.relay_device_type IS 'Slug of the relay device type providing this heartbeat (for devices without direct cloud access)';
COMMENT ON COLUMN device_heartbeats.relay_instance_id IS 'Instance ID of relay (future: for non-device relays like consumer phones)';
COMMENT ON COLUMN device_heartbeats.battery_level IS 'Battery level percentage (capability-specific)';
COMMENT ON COLUMN device_heartbeats.battery_charging IS 'Whether battery is currently charging (capability-specific)';
COMMENT ON COLUMN device_heartbeats.wifi_rssi IS 'WiFi signal strength in dBm (capability-specific)';
COMMENT ON COLUMN device_heartbeats.thread_rssi IS 'Thread signal strength in dBm (capability-specific)';

-- ============================================================================
-- CREATE INDEX ON unit_id
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_heartbeats_unit_id ON device_heartbeats(unit_id);
