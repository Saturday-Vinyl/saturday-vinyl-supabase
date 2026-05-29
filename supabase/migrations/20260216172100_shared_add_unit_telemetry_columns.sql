-- ============================================================================
-- Migration: 20260216172100_shared_add_unit_telemetry_columns.sql
-- Project: shared
-- Description: Add consumer-facing telemetry columns to units table for
--              simplified realtime subscriptions. These columns are updated
--              by the heartbeat trigger, not by application code.
-- Date: 2026-02-16
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- battery_level: 0-100 percentage from the power capability
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'units' AND column_name = 'battery_level'
  ) THEN
    ALTER TABLE units ADD COLUMN battery_level INTEGER;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'units_battery_level_check'
  ) THEN
    ALTER TABLE units ADD CONSTRAINT units_battery_level_check
      CHECK (battery_level IS NULL OR (battery_level >= 0 AND battery_level <= 100));
  END IF;
END $$;

-- is_charging: whether battery is currently charging
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'units' AND column_name = 'is_charging'
  ) THEN
    ALTER TABLE units ADD COLUMN is_charging BOOLEAN;
  END IF;
END $$;

-- last_seen_at: timestamp of most recent heartbeat from any device in this unit
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'units' AND column_name = 'last_seen_at'
  ) THEN
    ALTER TABLE units ADD COLUMN last_seen_at TIMESTAMPTZ;
  END IF;
END $$;

-- is_online: set true by heartbeat trigger, set false by check-device-status cron
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'units' AND column_name = 'is_online'
  ) THEN
    ALTER TABLE units ADD COLUMN is_online BOOLEAN DEFAULT false;
  END IF;
END $$;

-- wifi_rssi: WiFi signal strength in dBm
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'units' AND column_name = 'wifi_rssi'
  ) THEN
    ALTER TABLE units ADD COLUMN wifi_rssi INTEGER;
  END IF;
END $$;

-- temperature_c: ambient temperature from environment capability
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'units' AND column_name = 'temperature_c'
  ) THEN
    ALTER TABLE units ADD COLUMN temperature_c NUMERIC;
  END IF;
END $$;

-- humidity_pct: relative humidity percentage from environment capability
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'units' AND column_name = 'humidity_pct'
  ) THEN
    ALTER TABLE units ADD COLUMN humidity_pct NUMERIC;
  END IF;
END $$;

-- firmware_version: denormalized from primary device for consumer display
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'units' AND column_name = 'firmware_version'
  ) THEN
    ALTER TABLE units ADD COLUMN firmware_version TEXT;
  END IF;
END $$;

-- Column comments
COMMENT ON COLUMN units.battery_level IS 'Battery SOC percentage (0-100). Updated by heartbeat trigger from power-capable device.';
COMMENT ON COLUMN units.is_charging IS 'Whether battery is charging. Updated by heartbeat trigger.';
COMMENT ON COLUMN units.last_seen_at IS 'Timestamp of most recent heartbeat from any device in this unit. Updated by heartbeat trigger.';
COMMENT ON COLUMN units.is_online IS 'Whether any device in this unit has heartbeated within threshold. Set true by heartbeat trigger, false by check-device-status cron.';
COMMENT ON COLUMN units.wifi_rssi IS 'WiFi signal strength in dBm. Updated by heartbeat trigger from wifi-capable device.';
COMMENT ON COLUMN units.temperature_c IS 'Ambient temperature in Celsius. Updated by heartbeat trigger from environment-capable device.';
COMMENT ON COLUMN units.humidity_pct IS 'Relative humidity percentage. Updated by heartbeat trigger from environment-capable device.';
COMMENT ON COLUMN units.firmware_version IS 'Firmware version of the primary device. Denormalized for consumer display.';

-- Index for offline detection queries (only claimed units matter)
CREATE INDEX IF NOT EXISTS idx_units_last_seen_at
  ON units(last_seen_at)
  WHERE last_seen_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_units_is_online
  ON units(is_online)
  WHERE consumer_user_id IS NOT NULL;
