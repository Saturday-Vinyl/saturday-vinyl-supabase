-- ============================================================================
-- Migration: 20260309120000_shared_fix_heartbeat_telemetry_bidirectional.sql
-- Project: shared
-- Description: Fix device_heartbeats column population. Adds a BEFORE INSERT
--   trigger that bidirectionally syncs between the telemetry JSONB column and
--   individual typed columns. Also drops the stale consumer device sync trigger
--   that references non-existent columns, and backfills historical rows.
-- Date: 2026-03-09
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- PART 1: Bidirectional BEFORE INSERT trigger
-- ============================================================================
-- Handles two POST formats:
--   A) telemetry JSONB provided (relayed heartbeats) → extract known fields to columns
--   B) telemetry NULL (flat POST) → build telemetry JSONB from columns

CREATE OR REPLACE FUNCTION populate_heartbeat_telemetry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.telemetry IS NOT NULL THEN
    -- Case A: telemetry JSONB provided — extract known fields into typed columns
    -- COALESCE preserves any column value already set by the POST (column wins)
    NEW.firmware_version := COALESCE(NEW.firmware_version, NEW.telemetry->>'firmware_version');
    NEW.battery_level := COALESCE(NEW.battery_level, (NEW.telemetry->>'battery_level')::INTEGER);
    NEW.battery_charging := COALESCE(NEW.battery_charging, (NEW.telemetry->>'battery_charging')::BOOLEAN);
    NEW.wifi_rssi := COALESCE(NEW.wifi_rssi, (NEW.telemetry->>'wifi_rssi')::INTEGER);
    NEW.thread_rssi := COALESCE(NEW.thread_rssi, (NEW.telemetry->>'thread_rssi')::INTEGER);
    NEW.uptime_sec := COALESCE(NEW.uptime_sec, (NEW.telemetry->>'uptime_sec')::INTEGER);
    NEW.free_heap := COALESCE(NEW.free_heap, (NEW.telemetry->>'free_heap')::INTEGER);
    NEW.min_free_heap := COALESCE(NEW.min_free_heap, (NEW.telemetry->>'min_free_heap')::INTEGER);
    NEW.largest_free_block := COALESCE(NEW.largest_free_block, (NEW.telemetry->>'largest_free_block')::INTEGER);

    -- Enrich telemetry with routing fields so it's a complete record.
    -- Use routing_fields || telemetry so telemetry keys take priority on collision.
    NEW.telemetry := jsonb_strip_nulls(jsonb_build_object(
      'mac_address', NEW.mac_address,
      'unit_id', NEW.unit_id,
      'device_type', NEW.device_type,
      'type', NEW.type,
      'relay_device_type', NEW.relay_device_type,
      'relay_instance_id', NEW.relay_instance_id,
      'firmware_version', NEW.firmware_version
    )) || NEW.telemetry;
  ELSE
    -- Case B: No telemetry JSONB — build from individual columns (flat POST)
    NEW.telemetry := jsonb_strip_nulls(jsonb_build_object(
      'mac_address', NEW.mac_address,
      'unit_id', NEW.unit_id,
      'device_type', NEW.device_type,
      'type', NEW.type,
      'relay_device_type', NEW.relay_device_type,
      'relay_instance_id', NEW.relay_instance_id,
      'firmware_version', NEW.firmware_version,
      'battery_level', NEW.battery_level,
      'battery_charging', NEW.battery_charging,
      'wifi_rssi', NEW.wifi_rssi,
      'thread_rssi', NEW.thread_rssi,
      'uptime_sec', NEW.uptime_sec,
      'free_heap', NEW.free_heap,
      'min_free_heap', NEW.min_free_heap,
      'largest_free_block', NEW.largest_free_block,
      'command_id', NEW.command_id
    ));
  END IF;

  RETURN NEW;
END;
$$;

-- ============================================================================
-- PART 2: Drop stale trigger + create BEFORE INSERT trigger
-- ============================================================================

-- Drop stale trigger that references non-existent columns (device_timestamp, device_serial)
DROP TRIGGER IF EXISTS device_heartbeat_sync_consumer_device ON device_heartbeats;
DROP FUNCTION IF EXISTS sync_heartbeat_to_consumer_device();

-- Create (or replace) the BEFORE INSERT trigger
DROP TRIGGER IF EXISTS on_heartbeat_populate_telemetry ON device_heartbeats;
CREATE TRIGGER on_heartbeat_populate_telemetry
  BEFORE INSERT ON device_heartbeats
  FOR EACH ROW
  EXECUTE FUNCTION populate_heartbeat_telemetry();

-- ============================================================================
-- PART 3: Backfill existing rows
-- ============================================================================
-- Extract known fields from telemetry JSONB into typed columns for historical data.
-- COALESCE ensures we only fill NULL columns, never overwrite existing values.

UPDATE device_heartbeats
SET
  firmware_version = COALESCE(firmware_version, telemetry->>'firmware_version'),
  battery_level = COALESCE(battery_level, (telemetry->>'battery_level')::INTEGER),
  battery_charging = COALESCE(battery_charging, (telemetry->>'battery_charging')::BOOLEAN),
  wifi_rssi = COALESCE(wifi_rssi, (telemetry->>'wifi_rssi')::INTEGER),
  thread_rssi = COALESCE(thread_rssi, (telemetry->>'thread_rssi')::INTEGER),
  uptime_sec = COALESCE(uptime_sec, (telemetry->>'uptime_sec')::INTEGER),
  free_heap = COALESCE(free_heap, (telemetry->>'free_heap')::INTEGER),
  min_free_heap = COALESCE(min_free_heap, (telemetry->>'min_free_heap')::INTEGER),
  largest_free_block = COALESCE(largest_free_block, (telemetry->>'largest_free_block')::INTEGER)
WHERE telemetry IS NOT NULL
  AND (battery_level IS NULL OR uptime_sec IS NULL OR free_heap IS NULL);

-- ============================================================================
-- Verify triggers are in place
-- ============================================================================
DO $$
DECLARE
  trigger_count INTEGER;
BEGIN
  -- Verify the new BEFORE INSERT trigger exists
  SELECT COUNT(*) INTO trigger_count
  FROM pg_trigger
  WHERE tgrelid = 'device_heartbeats'::regclass
    AND tgname = 'on_heartbeat_populate_telemetry';

  IF trigger_count != 1 THEN
    RAISE EXCEPTION 'Expected on_heartbeat_populate_telemetry trigger, found %', trigger_count;
  END IF;

  -- Verify stale trigger is gone
  SELECT COUNT(*) INTO trigger_count
  FROM pg_trigger
  WHERE tgrelid = 'device_heartbeats'::regclass
    AND tgname = 'device_heartbeat_sync_consumer_device';

  IF trigger_count != 0 THEN
    RAISE EXCEPTION 'Stale trigger device_heartbeat_sync_consumer_device still exists';
  END IF;

  RAISE NOTICE 'Heartbeat telemetry trigger verified: on_heartbeat_populate_telemetry (BEFORE INSERT)';
  RAISE NOTICE 'Stale trigger device_heartbeat_sync_consumer_device removed';
END $$;
