-- ============================================================================
-- Migration: 20260217180000_shared_auto_populate_heartbeat_telemetry.sql
-- Project: shared
-- Description: Add BEFORE INSERT trigger on device_heartbeats that auto-populates
--   the telemetry JSONB column from individual columns when not provided by the
--   firmware. This preserves the raw POST payload for debugging/auditing.
-- Date: 2026-02-17
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

CREATE OR REPLACE FUNCTION populate_heartbeat_telemetry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only populate if firmware didn't provide telemetry
  IF NEW.telemetry IS NULL THEN
    NEW.telemetry := jsonb_strip_nulls(jsonb_build_object(
      'unit_id', NEW.unit_id,
      'mac_address', NEW.mac_address,
      'device_type', NEW.device_type,
      'relay_device_type', NEW.relay_device_type,
      'relay_instance_id', NEW.relay_instance_id,
      'firmware_version', NEW.firmware_version,
      'type', NEW.type,
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

DROP TRIGGER IF EXISTS on_heartbeat_populate_telemetry ON device_heartbeats;
CREATE TRIGGER on_heartbeat_populate_telemetry
  BEFORE INSERT ON device_heartbeats
  FOR EACH ROW
  EXECUTE FUNCTION populate_heartbeat_telemetry();
