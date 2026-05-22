-- ============================================================================
-- Migration: 20260127111628_fix_heartbeat_trigger.sql
-- Description: Fix heartbeat trigger to use unit_id instead of device_serial
-- Date: 2026-01-27
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Recreate the update_device_last_seen function to use current column names
-- This fixes the "record new has no field device_serial" error
CREATE OR REPLACE FUNCTION update_device_last_seen()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE devices
  SET
    last_seen_at = COALESCE(NEW.created_at, NOW()),
    firmware_version = COALESCE(NEW.firmware_version, firmware_version),
    latest_telemetry = jsonb_build_object(
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
    )
  WHERE mac_address = NEW.mac_address;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Ensure the trigger exists and uses the updated function
DROP TRIGGER IF EXISTS on_heartbeat_received ON device_heartbeats;
CREATE TRIGGER on_heartbeat_received
  AFTER INSERT ON device_heartbeats
  FOR EACH ROW
  EXECUTE FUNCTION update_device_last_seen();
