-- Migration: 019_remove_provisioning_manifest
-- Description: Remove provisioning_manifest columns from firmware_versions and production_steps
-- Reason: Provisioning manifests are now embedded in firmware binaries and retrieved
--         via the get_manifest command in Service Mode. The database no longer stores
--         manifest data - the firmware binary is the source of truth.

-- Remove provisioning_manifest column from firmware_versions
ALTER TABLE public.firmware_versions
  DROP COLUMN IF EXISTS provisioning_manifest;

-- Remove provisioning_manifest column from production_steps
ALTER TABLE public.production_steps
  DROP COLUMN IF EXISTS provisioning_manifest;

-- Update table comments
COMMENT ON TABLE public.firmware_versions IS
  'Firmware versions for device types. Provisioning manifests are now embedded in firmware binaries and retrieved via get_manifest command in Service Mode.';

COMMENT ON TABLE public.production_steps IS
  'Production workflow steps for products. Firmware provisioning steps reference firmware_versions but manifests are embedded in the firmware binary.';
