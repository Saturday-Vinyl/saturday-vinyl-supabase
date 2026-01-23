-- ============================================================================
-- Migration: 018_add_esp32_chip_types.sql
-- Description: Add ESP32-C6 and ESP32-H2 chip types
-- Date: 2026-01-04
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Drop and recreate the constraint to include new chip types
ALTER TABLE public.device_types
  DROP CONSTRAINT IF EXISTS valid_chip_type;

ALTER TABLE public.device_types
  ADD CONSTRAINT valid_chip_type CHECK (
    chip_type IS NULL OR
    chip_type IN ('esp32', 'esp32s2', 'esp32s3', 'esp32c3', 'esp32c6', 'esp32h2')
  );

-- Update comment to reflect new chip types
COMMENT ON COLUMN public.device_types.chip_type IS
  'ESP32 chip type for firmware flashing (esp32, esp32s2, esp32s3, esp32c3, esp32c6, esp32h2)';
