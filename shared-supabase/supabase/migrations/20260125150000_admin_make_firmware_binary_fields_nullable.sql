-- ============================================================================
-- Migration: 20260125150000_make_firmware_binary_fields_nullable.sql
-- Description: Make binary_url and binary_filename nullable since files are now in firmware_files table
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- With the multi-SoC firmware model, firmware files are stored in the firmware_files
-- junction table. The legacy binary_url/binary_filename columns on firmware are now
-- optional - they may exist for migrated data but new firmware entries don't need them.

-- Make binary_url nullable
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'firmware' AND column_name = 'binary_url'
    AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE firmware ALTER COLUMN binary_url DROP NOT NULL;
  END IF;
END $$;

-- Make binary_filename nullable
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'firmware' AND column_name = 'binary_filename'
    AND is_nullable = 'NO'
  ) THEN
    ALTER TABLE firmware ALTER COLUMN binary_filename DROP NOT NULL;
  END IF;
END $$;

-- Add comment explaining the deprecation
COMMENT ON COLUMN firmware.binary_url IS 'DEPRECATED: Legacy field for single-file firmware. New firmware uses firmware_files table for multi-SoC support.';
COMMENT ON COLUMN firmware.binary_filename IS 'DEPRECATED: Legacy field for single-file firmware. New firmware uses firmware_files table for multi-SoC support.';
