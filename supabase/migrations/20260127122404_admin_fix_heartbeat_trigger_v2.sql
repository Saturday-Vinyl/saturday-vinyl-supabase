-- ============================================================================
-- Migration: 20260127122404_fix_heartbeat_trigger_v2.sql
-- Description: Fix heartbeat trigger - use SECURITY DEFINER to bypass RLS
-- Date: 2026-01-27
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Drop and recreate the trigger function with SECURITY DEFINER
-- This is required because:
-- 1. Devices insert heartbeats via anon role
-- 2. The trigger runs in the security context of the inserting user
-- 3. RLS on the devices table blocks anon from updating
-- 4. SECURITY DEFINER makes the function run as the owner (postgres), bypassing RLS
CREATE OR REPLACE FUNCTION update_device_last_seen()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rows_updated INTEGER;
BEGIN
  -- Update the device record with heartbeat data
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

  -- Get number of rows updated for diagnostics
  GET DIAGNOSTICS rows_updated = ROW_COUNT;

  -- Log if no device was found (helpful for debugging)
  IF rows_updated = 0 THEN
    RAISE LOG 'Heartbeat received for unknown device: mac_address=%, unit_id=%',
      NEW.mac_address, NEW.unit_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Ensure the trigger is properly attached
-- Drop first to ensure clean state
DROP TRIGGER IF EXISTS on_heartbeat_received ON device_heartbeats;

-- Recreate the trigger
CREATE TRIGGER on_heartbeat_received
  AFTER INSERT ON device_heartbeats
  FOR EACH ROW
  EXECUTE FUNCTION update_device_last_seen();

-- Verify the trigger exists (this will show in migration output)
DO $$
DECLARE
  trigger_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'on_heartbeat_received'
    AND tgrelid = 'device_heartbeats'::regclass
  ) INTO trigger_exists;

  IF trigger_exists THEN
    RAISE NOTICE 'Trigger on_heartbeat_received is properly attached to device_heartbeats';
  ELSE
    RAISE EXCEPTION 'Failed to create trigger on_heartbeat_received';
  END IF;
END $$;

-- Ensure devices table is in the realtime publication
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE devices;
      RAISE NOTICE 'Added devices table to supabase_realtime publication';
    EXCEPTION
      WHEN duplicate_object THEN
        RAISE NOTICE 'devices table already in supabase_realtime publication';
    END;
  END IF;
END $$;
