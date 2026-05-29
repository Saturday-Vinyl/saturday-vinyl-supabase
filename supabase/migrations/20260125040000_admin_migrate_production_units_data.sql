-- ============================================================================
-- Migration: 20260125040000_migrate_production_units_data.sql
-- Description: Migrate existing production_units data to new units and devices tables
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Migrate production_units to units table
-- Maps existing fields to new schema
-- Note: order_id is set to NULL as it doesn't exist in production_units
INSERT INTO units (
  id,
  serial_number,
  product_id,
  variant_id,
  order_id,
  factory_provisioned_at,
  factory_provisioned_by,
  status,
  production_started_at,
  production_completed_at,
  is_completed,
  qr_code_url,
  created_at,
  updated_at,
  created_by
)
SELECT
  pu.id,
  pu.unit_id,  -- unit_id becomes serial_number
  pu.product_id,
  pu.variant_id,
  NULL,  -- order_id doesn't exist in production_units
  CASE
    WHEN pu.is_completed THEN COALESCE(pu.production_completed_at, pu.production_started_at)
    ELSE NULL
  END,
  pu.created_by,
  CASE
    WHEN pu.is_completed THEN 'factory_provisioned'
    ELSE 'unprovisioned'
  END,
  pu.production_started_at,
  pu.production_completed_at,
  pu.is_completed,
  pu.qr_code_url,
  pu.created_at,
  NOW(),
  pu.created_by
FROM production_units pu
WHERE NOT EXISTS (
  SELECT 1 FROM units u WHERE u.id = pu.id
);

-- Migrate MAC addresses to devices table
-- Each production_unit with a mac_address becomes a device instance
-- Use DISTINCT ON to handle duplicate MACs in production_units (takes most recent)
INSERT INTO devices (
  mac_address,
  unit_id,
  factory_provisioned_at,
  factory_provisioned_by,
  status,
  created_at,
  updated_at
)
SELECT DISTINCT ON (pu.mac_address)
  pu.mac_address,
  pu.id,  -- Link to the migrated unit
  CASE
    WHEN pu.is_completed THEN COALESCE(pu.production_completed_at, pu.production_started_at)
    ELSE NULL
  END,
  pu.created_by,
  CASE
    WHEN pu.is_completed THEN 'provisioned'
    ELSE 'unprovisioned'
  END,
  pu.created_at,
  NOW()
FROM production_units pu
WHERE pu.mac_address IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM devices d WHERE d.mac_address = pu.mac_address
  )
ORDER BY pu.mac_address, pu.created_at DESC;

-- Also migrate any firmware history device_type assignments to devices
-- This helps link devices to their device_types based on firmware provisioning
-- Only runs if unit_firmware_history table exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'unit_firmware_history'
  ) THEN
    -- Update device_type_id from firmware history
    UPDATE devices d
    SET device_type_id = (
      SELECT fv.device_type_id
      FROM unit_firmware_history ufh
      JOIN firmware_versions fv ON fv.id = ufh.firmware_version_id
      WHERE ufh.unit_id = d.unit_id
      ORDER BY ufh.installed_at DESC
      LIMIT 1
    )
    WHERE d.device_type_id IS NULL
      AND EXISTS (
        SELECT 1
        FROM unit_firmware_history ufh
        JOIN firmware_versions fv ON fv.id = ufh.firmware_version_id
        WHERE ufh.unit_id = d.unit_id
      );

    -- Update devices with latest firmware version from history
    UPDATE devices d
    SET
      firmware_version = ufh.firmware_version,
      firmware_id = ufh.firmware_version_id
    FROM (
      SELECT DISTINCT ON (ufh.unit_id)
        ufh.unit_id,
        fv.version as firmware_version,
        fv.id as firmware_version_id
      FROM unit_firmware_history ufh
      JOIN firmware_versions fv ON fv.id = ufh.firmware_version_id
      ORDER BY ufh.unit_id, ufh.installed_at DESC
    ) ufh
    WHERE d.unit_id = ufh.unit_id
      AND d.firmware_version IS NULL;
  END IF;
END $$;

-- Add comment noting the migration
COMMENT ON TABLE production_units IS 'DEPRECATED: Migrated to units table. Kept for rollback safety. See units table for current data.';
