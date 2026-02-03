-- ============================================================================
-- Migration: 20260130181155_replace_device_type_id_with_slug.sql
-- Description: Replace device_type_id (UUID) with device_type_slug (VARCHAR)
--              for simpler queries and better readability in the devices table
-- Date: 2026-01-30
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Step 1: Add device_type_slug column if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'devices' AND column_name = 'device_type_slug'
  ) THEN
    ALTER TABLE devices ADD COLUMN device_type_slug VARCHAR(100);
  END IF;
END $$;

COMMENT ON COLUMN devices.device_type_slug IS 'Device type slug (e.g., "hub", "crate"). References device_types.slug.';

-- Step 2: Migrate existing records from device_type_id to device_type_slug
UPDATE devices d SET device_type_slug = (
  SELECT dt.slug FROM device_types dt WHERE dt.id = d.device_type_id
)
WHERE d.device_type_id IS NOT NULL
  AND d.device_type_slug IS NULL;

-- Step 3: Add FK constraint to device_types.slug
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fk_devices_device_type_slug'
  ) THEN
    ALTER TABLE devices ADD CONSTRAINT fk_devices_device_type_slug
      FOREIGN KEY (device_type_slug) REFERENCES device_types(slug);
  END IF;
END $$;

-- Step 4: Create index on device_type_slug
CREATE INDEX IF NOT EXISTS idx_devices_device_type_slug ON devices(device_type_slug);

-- Step 5: Drop dependent views before dropping device_type_id column
DROP VIEW IF EXISTS units_with_devices;
DROP VIEW IF EXISTS units_dashboard;

-- Step 6: Drop old device_type_id column and its index
DROP INDEX IF EXISTS idx_devices_device_type_id;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'devices' AND column_name = 'device_type_id'
  ) THEN
    ALTER TABLE devices DROP COLUMN device_type_id;
  END IF;
END $$;

-- Step 7: Recreate units_with_devices view using device_type_slug
CREATE OR REPLACE VIEW units_with_devices AS
SELECT
  u.id as unit_id,
  u.serial_number,
  u.product_id,
  u.variant_id,
  u.status as unit_status,
  u.user_id,
  u.device_name,
  u.consumer_provisioned_at,
  u.factory_provisioned_at,
  u.is_completed,
  u.qr_code_url,
  d.id as device_id,
  d.mac_address,
  d.device_type_slug,
  d.firmware_version,
  d.firmware_id,
  d.last_seen_at,
  d.status as device_status,
  -- Online status based on last_seen_at (within last 60 seconds)
  CASE
    WHEN d.last_seen_at > NOW() - INTERVAL '60 seconds' THEN 'online'
    WHEN d.last_seen_at IS NOT NULL THEN 'offline'
    ELSE 'unknown'
  END as online_status,
  -- Product info
  p.name as product_name,
  pv.name as variant_name,
  -- Device type info
  dt.name as device_type_name
FROM units u
LEFT JOIN devices d ON d.unit_id = u.id
LEFT JOIN products p ON p.id = u.product_id
LEFT JOIN product_variants pv ON pv.id = u.variant_id
LEFT JOIN device_types dt ON dt.slug = d.device_type_slug;

COMMENT ON VIEW units_with_devices IS
  'Convenience view joining units with their devices, product info, and online status. '
  'Use for dashboard displays and unit detail views.';

-- Step 8: Recreate units_dashboard view using device_type_slug
CREATE OR REPLACE VIEW units_dashboard AS
SELECT
  u.id,
  u.serial_number,
  u.device_name,
  u.status,
  u.order_id,
  u.product_id,
  u.variant_id,
  u.user_id,
  u.factory_provisioned_at,
  u.consumer_provisioned_at,
  u.is_completed,
  u.created_at,
  u.updated_at,
  -- Primary device data (first device by created_at)
  d.id AS primary_device_id,
  d.mac_address AS primary_device_mac,
  d.device_type_slug,
  d.last_seen_at,
  d.latest_telemetry,
  d.firmware_version,
  -- Computed: connected if seen within last 5 minutes
  CASE
    WHEN d.last_seen_at > NOW() - INTERVAL '5 minutes' THEN true
    ELSE false
  END AS is_connected
FROM units u
LEFT JOIN LATERAL (
  SELECT *
  FROM devices
  WHERE unit_id = u.id
  ORDER BY created_at ASC
  LIMIT 1
) d ON true;

COMMENT ON VIEW units_dashboard IS
  'Optimized view for unit list display. Joins units with their primary device (first by created_at) for efficient dashboard queries.';

-- Step 9: Grant select on views to authenticated users
GRANT SELECT ON units_with_devices TO authenticated;
GRANT SELECT ON units_dashboard TO authenticated;
