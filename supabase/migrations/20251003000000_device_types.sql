-- Migration 004: Device Types - Add current_firmware_version column
-- Created: 2025-10-09
-- Description: Adds current_firmware_version column to existing device_types table
-- Note: device_types table already exists from migration 001_products_schema.sql
-- Idempotent: Yes - safe to run multiple times

-- Add current_firmware_version column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'device_types'
    AND column_name = 'current_firmware_version'
  ) THEN
    ALTER TABLE device_types ADD COLUMN current_firmware_version VARCHAR(50);
    RAISE NOTICE 'Added current_firmware_version column to device_types';
  ELSE
    RAISE NOTICE 'Column current_firmware_version already exists';
  END IF;
END $$;

-- Ensure indexes exist (IF NOT EXISTS will skip if already present)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_device_types_active') THEN
    CREATE INDEX idx_device_types_active ON device_types(is_active);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_device_types_name') THEN
    CREATE INDEX idx_device_types_name ON device_types(name);
  END IF;
END $$;

-- RLS and policies already exist from migration 001
-- Just add delete policy if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
    AND tablename = 'device_types'
    AND policyname = 'Authenticated users can delete device types'
  ) THEN
    CREATE POLICY "Authenticated users can delete device types"
      ON device_types
      FOR DELETE
      TO authenticated
      USING (true);
    RAISE NOTICE 'Added delete policy for device_types';
  END IF;
END $$;

-- Comments for documentation (safe to re-run)
COMMENT ON COLUMN device_types.current_firmware_version IS 'Current/latest firmware version for this device type';
