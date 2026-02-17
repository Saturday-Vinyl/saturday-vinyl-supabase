-- ============================================================================
-- Migration: 20260216172300_shared_rewrite_heartbeat_triggers.sql
-- Project: shared
-- Description: Consolidate and rewrite heartbeat triggers.
--   1. Replace overlapping update_device_last_seen() and sync_heartbeat_to_device()
--      with a single sync_heartbeat_to_device_and_unit() that updates both devices
--      and units tables.
--   2. Fix update_command_on_ack() which referenced nonexistent heartbeat_data column.
--   Backward compatible: handles both individual columns and new telemetry JSONB.
-- Date: 2026-02-16
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- PART 1: Unified heartbeat sync trigger
-- ============================================================================
-- Replaces: update_device_last_seen() and sync_heartbeat_to_device()
-- Previously two triggers both fired AFTER INSERT, causing duplicate UPDATEs
-- on the devices table. This consolidates into one trigger that also propagates
-- consumer-facing telemetry to the units table.

CREATE OR REPLACE FUNCTION sync_heartbeat_to_device_and_unit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_unit_id UUID;
  v_telemetry JSONB;
  v_battery_level INTEGER;
  v_is_charging BOOLEAN;
  v_wifi_rssi INTEGER;
  v_temperature_c NUMERIC;
  v_humidity_pct NUMERIC;
  v_firmware_version TEXT;
  v_heartbeat_ts TIMESTAMPTZ;
BEGIN
  v_heartbeat_ts := COALESCE(NEW.created_at, NOW());
  v_firmware_version := NEW.firmware_version;

  -- Build telemetry JSONB: prefer new telemetry column, fall back to individual columns
  IF NEW.telemetry IS NOT NULL THEN
    v_telemetry := NEW.telemetry;
  ELSE
    -- Build from individual columns (backward compatibility with current firmware)
    v_telemetry := jsonb_strip_nulls(jsonb_build_object(
      'unit_id', NEW.unit_id,
      'device_type', NEW.device_type,
      'uptime_sec', NEW.uptime_sec,
      'free_heap', NEW.free_heap,
      'min_free_heap', NEW.min_free_heap,
      'largest_free_block', NEW.largest_free_block,
      'wifi_rssi', NEW.wifi_rssi,
      'thread_rssi', NEW.thread_rssi,
      'battery_level', NEW.battery_level,
      'battery_charging', NEW.battery_charging
    ));
  END IF;

  -- Extract consumer-facing telemetry values
  -- COALESCE prefers telemetry JSONB, falls back to individual columns
  v_battery_level := COALESCE(
    (v_telemetry->>'battery_level')::INTEGER,
    NEW.battery_level
  );
  v_is_charging := COALESCE(
    (v_telemetry->>'battery_charging')::BOOLEAN,
    NEW.battery_charging
  );
  v_wifi_rssi := COALESCE(
    (v_telemetry->>'wifi_rssi')::INTEGER,
    NEW.wifi_rssi
  );
  v_temperature_c := (v_telemetry->>'temperature_c')::NUMERIC;
  v_humidity_pct := (v_telemetry->>'humidity_pct')::NUMERIC;

  -- Also extract firmware_version from telemetry if not set as column
  IF v_firmware_version IS NULL THEN
    v_firmware_version := v_telemetry->>'firmware_version';
  END IF;

  -- =========================================================================
  -- Update devices table (by mac_address)
  -- =========================================================================
  UPDATE devices
  SET
    last_seen_at = v_heartbeat_ts,
    firmware_version = COALESCE(v_firmware_version, firmware_version),
    latest_telemetry = v_telemetry,
    status = CASE WHEN status = 'offline' THEN 'online' ELSE status END
  WHERE mac_address = NEW.mac_address;

  -- =========================================================================
  -- Update units table (by serial number stored in heartbeats.unit_id)
  -- Only update fields that are present in this heartbeat's telemetry.
  -- This supports multi-device units where different devices report
  -- different capability data (e.g., main controller has wifi, RFID reader
  -- does not). COALESCE preserves existing values when this heartbeat
  -- doesn't include a particular field.
  -- =========================================================================
  IF NEW.unit_id IS NOT NULL THEN
    UPDATE units
    SET
      last_seen_at = GREATEST(last_seen_at, v_heartbeat_ts),
      is_online = true,
      firmware_version = COALESCE(v_firmware_version, firmware_version),
      battery_level = COALESCE(v_battery_level, battery_level),
      is_charging = COALESCE(v_is_charging, is_charging),
      wifi_rssi = COALESCE(v_wifi_rssi, wifi_rssi),
      temperature_c = COALESCE(v_temperature_c, temperature_c),
      humidity_pct = COALESCE(v_humidity_pct, humidity_pct)
    WHERE serial_number = NEW.unit_id
    RETURNING id INTO v_unit_id;

    IF v_unit_id IS NULL THEN
      RAISE LOG 'Heartbeat: no unit found for serial_number=%, mac=%',
        NEW.unit_id, NEW.mac_address;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- Drop all old triggers on device_heartbeats related to sync
DROP TRIGGER IF EXISTS on_heartbeat_received ON device_heartbeats;
DROP TRIGGER IF EXISTS device_heartbeat_sync_device ON device_heartbeats;

-- Create single unified trigger
DROP TRIGGER IF EXISTS on_heartbeat_sync ON device_heartbeats;
CREATE TRIGGER on_heartbeat_sync
  AFTER INSERT ON device_heartbeats
  FOR EACH ROW
  EXECUTE FUNCTION sync_heartbeat_to_device_and_unit();

-- Drop old functions that are no longer needed
DROP FUNCTION IF EXISTS update_device_last_seen();
DROP FUNCTION IF EXISTS sync_heartbeat_to_device();

-- ============================================================================
-- PART 2: Fixed command ack trigger
-- ============================================================================
-- The previous version referenced NEW.heartbeat_data which does not exist as a
-- column on device_heartbeats. Now reads from NEW.telemetry JSONB column.

CREATE OR REPLACE FUNCTION update_command_on_ack()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
  v_result JSONB;
  v_error_message TEXT;
BEGIN
  -- Handle command acknowledgement
  IF NEW.type = 'command_ack' AND NEW.command_id IS NOT NULL THEN
    UPDATE device_commands
    SET
      status = 'acknowledged',
      updated_at = NOW()
    WHERE id = NEW.command_id
      AND status IN ('pending', 'sent');

  -- Handle command result (completed or failed)
  ELSIF NEW.type = 'command_result' AND NEW.command_id IS NOT NULL THEN
    IF NEW.telemetry IS NOT NULL THEN
      v_status := COALESCE(NEW.telemetry->>'status', 'completed');
      v_result := NEW.telemetry->'result';
      v_error_message := NEW.telemetry->>'error_message';
    ELSE
      v_status := 'completed';
    END IF;

    UPDATE device_commands
    SET
      status = v_status,
      result = v_result,
      error_message = v_error_message,
      updated_at = NOW()
    WHERE id = NEW.command_id;
  END IF;

  RETURN NEW;
END;
$$;

-- Recreate the command ack trigger
DROP TRIGGER IF EXISTS on_command_ack_heartbeat ON device_heartbeats;
CREATE TRIGGER on_command_ack_heartbeat
  AFTER INSERT ON device_heartbeats
  FOR EACH ROW
  WHEN (NEW.type IN ('command_ack', 'command_result'))
  EXECUTE FUNCTION update_command_on_ack();

-- ============================================================================
-- Verify triggers are in place
-- ============================================================================
DO $$
DECLARE
  trigger_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO trigger_count
  FROM pg_trigger
  WHERE tgrelid = 'device_heartbeats'::regclass
    AND tgname IN ('on_heartbeat_sync', 'on_command_ack_heartbeat');

  IF trigger_count != 2 THEN
    RAISE EXCEPTION 'Expected 2 triggers on device_heartbeats, found %', trigger_count;
  END IF;
  RAISE NOTICE 'Heartbeat triggers verified: on_heartbeat_sync + on_command_ack_heartbeat';
END $$;
