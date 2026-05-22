-- Migration: Fix user_now_playing_notifications.device_id FK
--
-- The device_id column references consumer_devices(id), which has been replaced
-- by the units table. Re-point the FK to units(id).
--
-- Idempotent: Yes - safe to run multiple times
-- Depends on: 20260125020000_admin_create_units_table.sql

-- 1. Drop the old FK constraint pointing to consumer_devices
ALTER TABLE user_now_playing_notifications
  DROP CONSTRAINT IF EXISTS user_now_playing_notifications_device_id_fkey;

-- 2. Clean up any orphaned device_id values that don't exist in units
UPDATE user_now_playing_notifications
SET device_id = NULL
WHERE device_id IS NOT NULL
  AND device_id NOT IN (SELECT id FROM units);

-- 3. Add new FK constraint pointing to units
DO $$ BEGIN
  ALTER TABLE user_now_playing_notifications
    ADD CONSTRAINT user_now_playing_notifications_device_id_fkey
    FOREIGN KEY (device_id) REFERENCES units(id) ON DELETE SET NULL;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
