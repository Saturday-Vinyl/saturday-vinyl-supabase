-- ============================================================================
-- Migration: 20260423000354_admin_add_firmware_files_flash_offset.sql
-- Project: saturday-admin-app
-- Description: Add flash_offset column to firmware_files for dual-SoC flashing.
--              Master SoC uses offset 0, secondary SoCs use staging partition
--              offset (e.g., 0x400000 for h2_fw partition).
-- Date: 2026-04-23
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'firmware_files' AND column_name = 'flash_offset'
  ) THEN
    ALTER TABLE firmware_files ADD COLUMN flash_offset INTEGER DEFAULT 0;
  END IF;
END $$;

COMMENT ON COLUMN firmware_files.flash_offset IS 'Flash memory offset for esptool write_flash. Master SoC: 0, secondary SoCs: staging partition offset.';
