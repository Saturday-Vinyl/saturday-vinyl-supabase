-- ============================================================================
-- Migration: 20260125090000_consolidate_provision_data.sql
-- Description: Consolidate provisioning data into single flat provision_data column
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- This migration consolidates factory_attributes and consumer_attributes into
-- a single flat provision_data column on the devices table.
--
-- Previous architecture:
--   devices.factory_attributes  - Factory provisioning data
--   units.consumer_attributes   - Consumer provisioning data
--
-- New architecture:
--   devices.provision_data - Flat JSONB object with all provisioning data
--
-- The device firmware tracks which attributes are factory vs consumer in NVS.
-- The cloud stores a flat snapshot of current provisioned state.
-- Consumer reset is handled by the device; cloud updates based on reported state.

-- Step 1: Add provision_data column to devices (flat structure)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'devices' AND column_name = 'provision_data'
  ) THEN
    ALTER TABLE devices ADD COLUMN provision_data JSONB DEFAULT '{}';
  END IF;
END $$;

COMMENT ON COLUMN devices.provision_data IS 'Flat JSONB object containing all current provisioning data for this device.';

-- Step 2: Migrate existing factory_attributes to provision_data (merge at top level)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'devices' AND column_name = 'factory_attributes'
  ) THEN
    UPDATE devices
    SET provision_data = COALESCE(provision_data, '{}'::jsonb) || COALESCE(factory_attributes, '{}'::jsonb)
    WHERE factory_attributes IS NOT NULL
      AND factory_attributes != '{}'::jsonb;
  END IF;
END $$;

-- Step 3: Migrate units.consumer_attributes to devices.provision_data (merge at top level)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'units' AND column_name = 'consumer_attributes'
  ) THEN
    UPDATE devices d
    SET provision_data = COALESCE(d.provision_data, '{}'::jsonb) || COALESCE(u.consumer_attributes, '{}'::jsonb)
    FROM units u
    WHERE d.unit_id = u.id
      AND u.consumer_attributes IS NOT NULL
      AND u.consumer_attributes != '{}'::jsonb;
  END IF;
END $$;

-- Step 4: Create index on provision_data for queries
CREATE INDEX IF NOT EXISTS idx_devices_provision_data ON devices USING GIN (provision_data);

-- Step 5: Drop deprecated columns (clean break - no production data)
ALTER TABLE devices DROP COLUMN IF EXISTS factory_attributes;
ALTER TABLE units DROP COLUMN IF EXISTS consumer_attributes;
