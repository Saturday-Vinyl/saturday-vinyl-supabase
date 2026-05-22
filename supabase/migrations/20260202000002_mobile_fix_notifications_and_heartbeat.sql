-- Migration: Fix notifications, heartbeat trigger, and RLS for new schema
--
-- This migration handles three things:
-- 1. Rename device_status_notifications.device_id → unit_id with FK to units(id)
-- 2. Create sync_heartbeat_to_device() trigger to update devices table
-- 3. Update device_heartbeats RLS policy to reference units instead of consumer_devices
--
-- Note: device_heartbeats uses "unit_id" column to store the serial number
-- (e.g., 'SV-HUB-00001'), NOT a UUID. The join is:
--   device_heartbeats.unit_id → units.serial_number → devices.unit_id
--
-- Depends on: 20260202000000_consumer_provisioning_schema.sql

-- ============================================================================
-- PART 1: Rename device_status_notifications.device_id → unit_id
-- ============================================================================
-- The column references units(id), not devices(id), so "device_id" is misleading.
-- Made idempotent: skip rename if already done.

-- 1a. Drop existing constraints and indexes (safe to re-run)
ALTER TABLE device_status_notifications
  DROP CONSTRAINT IF EXISTS device_status_notifications_device_id_fkey;
ALTER TABLE device_status_notifications
  DROP CONSTRAINT IF EXISTS device_status_notifications_device_type_unique;
DROP INDEX IF EXISTS idx_device_status_notifications_device;

-- 1b. Rename column (skip if already renamed)
DO $$ BEGIN
  ALTER TABLE device_status_notifications RENAME COLUMN device_id TO unit_id;
EXCEPTION
  WHEN undefined_column THEN NULL;  -- device_id doesn't exist = already renamed
END $$;

-- 1c. Add FK constraint referencing units table (skip if exists)
DO $$ BEGIN
  ALTER TABLE device_status_notifications
    ADD CONSTRAINT device_status_notifications_unit_id_fkey
    FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- 1d. Recreate unique constraint and indexes (skip if exists)
DO $$ BEGIN
  ALTER TABLE device_status_notifications
    ADD CONSTRAINT device_status_notifications_unit_type_unique
    UNIQUE (unit_id, notification_type);
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_device_status_notifications_unit
  ON device_status_notifications(unit_id);

-- 1e. Clean up orphaned records from old consumer_devices references
DELETE FROM device_status_notifications
  WHERE unit_id NOT IN (SELECT id FROM units);

-- ============================================================================
-- PART 2: Create heartbeat → devices sync trigger
-- ============================================================================
-- The remote device_heartbeats table uses:
--   unit_id (text) = serial number (e.g., 'SV-HUB-00001')
--   mac_address (varchar) = device MAC
--
-- The join path is: device_heartbeats.unit_id → units.serial_number → devices.unit_id

CREATE OR REPLACE FUNCTION sync_heartbeat_to_device()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE devices d
    SET
        last_seen_at = NEW.created_at,
        latest_telemetry = jsonb_build_object(
            'unit_id', NEW.unit_id,
            'device_type', NEW.device_type,
            'battery_level', NEW.battery_level,
            'battery_charging', NEW.battery_charging,
            'wifi_rssi', NEW.wifi_rssi,
            'thread_rssi', NEW.thread_rssi,
            'uptime_sec', NEW.uptime_sec,
            'free_heap', NEW.free_heap,
            'min_free_heap', NEW.min_free_heap,
            'largest_free_block', NEW.largest_free_block
        ),
        firmware_version = COALESCE(NEW.firmware_version, d.firmware_version),
        status = CASE
            WHEN d.status = 'offline' THEN 'online'
            ELSE d.status
        END
    FROM units u
    WHERE u.serial_number = NEW.unit_id
      AND d.unit_id = u.id;

    IF NOT FOUND THEN
        RAISE WARNING 'No device found for unit_id (serial): %', NEW.unit_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS device_heartbeat_sync_device ON device_heartbeats;
CREATE TRIGGER device_heartbeat_sync_device
AFTER INSERT ON device_heartbeats
FOR EACH ROW
EXECUTE FUNCTION sync_heartbeat_to_device();

-- ============================================================================
-- PART 3: Update device_heartbeats RLS policy
-- ============================================================================
-- The existing policy (if any) references consumer_devices.
-- Update to use units table. The heartbeats.unit_id column stores the serial number.

DROP POLICY IF EXISTS "Users can view own device heartbeats" ON device_heartbeats;
CREATE POLICY "Users can view own device heartbeats"
    ON device_heartbeats FOR SELECT
    USING (
        unit_id IN (
            SELECT serial_number FROM units
            WHERE consumer_user_id IN (
                SELECT id FROM users WHERE auth_user_id = auth.uid()
            )
        )
    );
