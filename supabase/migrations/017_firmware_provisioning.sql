-- ============================================================================
-- Migration: 017_firmware_provisioning.sql
-- Description: Add firmware provisioning step type and related columns
-- Date: 2026-01-04
-- ============================================================================

-- ============================================================================
-- Extend Step Type Enum
-- ============================================================================

-- Add firmware_provisioning to step_type enum
ALTER TYPE public.step_type ADD VALUE 'firmware_provisioning';

COMMENT ON TYPE public.step_type IS
  'Type of production step: general (manual work), cnc_milling (CNC machine), laser_cutting (laser machine), or firmware_provisioning (ESP32 flashing and provisioning)';

-- ============================================================================
-- Modify Device Types Table
-- ============================================================================

-- Add chip_type column (the chip is a property of the device, not the step)
ALTER TABLE public.device_types
  ADD COLUMN chip_type VARCHAR(20);

-- Add constraint for valid chip types
ALTER TABLE public.device_types
  ADD CONSTRAINT valid_chip_type CHECK (
    chip_type IS NULL OR
    chip_type IN ('esp32', 'esp32s2', 'esp32s3', 'esp32c3')
  );

-- Add comment
COMMENT ON COLUMN public.device_types.chip_type IS
  'ESP32 chip type for firmware flashing (esp32, esp32s2, esp32s3, esp32c3)';

-- ============================================================================
-- Modify Firmware Versions Table
-- ============================================================================

-- Add provisioning manifest column
ALTER TABLE public.firmware_versions
  ADD COLUMN provisioning_manifest JSONB;

-- Add comment
COMMENT ON COLUMN public.firmware_versions.provisioning_manifest IS
  'Default provisioning manifest for this firmware version (JSON schema defining provisioning data, tests, etc.)';

-- ============================================================================
-- Modify Production Steps Table
-- ============================================================================

-- Add firmware provisioning columns
-- Note: chip_type comes from device_types via firmware_version -> device_type relationship
ALTER TABLE public.production_steps
  ADD COLUMN firmware_version_id UUID REFERENCES firmware_versions(id) ON DELETE SET NULL,
  ADD COLUMN provisioning_manifest JSONB;

-- Add comments
COMMENT ON COLUMN public.production_steps.firmware_version_id IS
  'Reference to firmware version for firmware_provisioning steps';

COMMENT ON COLUMN public.production_steps.provisioning_manifest IS
  'Provisioning manifest for this step (overrides firmware version default if set)';

-- Create index
CREATE INDEX idx_production_steps_firmware_version ON public.production_steps(firmware_version_id);

-- ============================================================================
-- Modify Production Units Table
-- ============================================================================

-- Add MAC address column
ALTER TABLE public.production_units
  ADD COLUMN mac_address VARCHAR(17);

-- Add constraint for MAC address format (XX:XX:XX:XX:XX:XX)
ALTER TABLE public.production_units
  ADD CONSTRAINT valid_mac_address_format CHECK (
    mac_address IS NULL OR
    mac_address ~ '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'
  );

-- Add comment
COMMENT ON COLUMN public.production_units.mac_address IS
  'MAC address captured during firmware provisioning (format: XX:XX:XX:XX:XX:XX)';

-- Create index for MAC address lookups
CREATE INDEX idx_production_units_mac_address ON public.production_units(mac_address);

-- ============================================================================
-- Completion Message
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 017_firmware_provisioning completed successfully!';
    RAISE NOTICE 'Changes:';
    RAISE NOTICE '  - Added firmware_provisioning to step_type enum';
    RAISE NOTICE '  - Added chip_type column to device_types';
    RAISE NOTICE '  - Added provisioning_manifest column to firmware_versions';
    RAISE NOTICE '  - Added firmware_version_id and provisioning_manifest columns to production_steps';
    RAISE NOTICE '  - Added mac_address column to production_units';
END $$;
