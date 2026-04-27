-- ============================================================================
-- Migration: 20260427213553_admin_firmware_files_purpose.sql
-- Project: saturday-admin-app
-- Description: Add purpose column to firmware_files to distinguish factory
--              flashing binaries (merged: bootloader + partition table + ota_data
--              + app) from OTA binaries (app-only). Master SoCs need both;
--              secondary SoCs only need a factory binary.
-- Date: 2026-04-27
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Add purpose column with default 'factory' (matches existing merged binaries)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'firmware_files' AND column_name = 'purpose'
  ) THEN
    ALTER TABLE firmware_files
      ADD COLUMN purpose TEXT NOT NULL DEFAULT 'factory';
  END IF;
END $$;

-- Add CHECK constraint restricting valid purposes
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'firmware_files_purpose_check'
  ) THEN
    ALTER TABLE firmware_files
      ADD CONSTRAINT firmware_files_purpose_check
      CHECK (purpose IN ('factory', 'ota'));
  END IF;
END $$;

COMMENT ON COLUMN firmware_files.purpose IS
  'Binary purpose: factory (merged binary for esptool flashing) or ota (app-only binary for esp_https_ota). Master SoCs need both; secondary SoCs only need factory.';

-- Replace UNIQUE(firmware_id, soc_type) with UNIQUE(firmware_id, soc_type, purpose)
-- so a master SoC can have both a factory and an ota row.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'firmware_files_firmware_id_soc_type_key'
  ) THEN
    ALTER TABLE firmware_files
      DROP CONSTRAINT firmware_files_firmware_id_soc_type_key;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'firmware_files_firmware_id_soc_type_purpose_key'
  ) THEN
    ALTER TABLE firmware_files
      ADD CONSTRAINT firmware_files_firmware_id_soc_type_purpose_key
      UNIQUE (firmware_id, soc_type, purpose);
  END IF;
END $$;
