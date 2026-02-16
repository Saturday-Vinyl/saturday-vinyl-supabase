-- ============================================================================
-- Migration: 20260125070000_deprecate_old_tables.sql
-- Description: Add deprecation comments to old tables, kept for rollback safety
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Add deprecation comments to production_units
-- Table is kept for rollback safety but new code should use units table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'production_units'
  ) THEN
    COMMENT ON TABLE production_units IS
      'DEPRECATED (2026-01-25): This table has been replaced by the unified "units" table. '
      'Data has been migrated. This table is kept for rollback safety. '
      'New code should use: '
      '  - units: for product instances (serial numbers, status, consumer data) '
      '  - devices: for hardware instances (MAC addresses, firmware) '
      'See migration 20260125040000_migrate_production_units_data.sql for details.';
  END IF;
END $$;

-- Add deprecation comment to firmware_versions if it still exists
-- (should have been renamed to firmware in migration 20260125050000)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'firmware_versions'
  ) THEN
    COMMENT ON TABLE firmware_versions IS
      'DEPRECATED (2026-01-25): This table should have been renamed to "firmware". '
      'If this comment is visible, check migration 20260125050000_rename_and_extend_firmware.sql.';
  END IF;
END $$;

-- Add view for backwards compatibility with production_units queries
-- This allows gradual migration of code that reads from production_units
CREATE OR REPLACE VIEW production_units_compat AS
SELECT
  u.id,
  u.serial_number as unit_id,
  u.product_id,
  u.variant_id,
  u.order_id,
  d.mac_address,
  u.qr_code_url,
  u.production_started_at,
  u.production_completed_at,
  u.is_completed,
  u.created_at,
  u.created_by
FROM units u
LEFT JOIN devices d ON d.unit_id = u.id;

COMMENT ON VIEW production_units_compat IS
  'Backwards compatibility view for code that queries production_units. '
  'Maps new units + devices tables to old production_units schema. '
  'DEPRECATED: Update code to query units and devices tables directly.';

-- Create view to simplify unit + device queries
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
  d.device_type_id,
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
LEFT JOIN device_types dt ON dt.id = d.device_type_id;

COMMENT ON VIEW units_with_devices IS
  'Convenience view joining units with their devices, product info, and online status. '
  'Use for dashboard displays and unit detail views.';

-- Create function to check online devices count
CREATE OR REPLACE FUNCTION get_online_device_count()
RETURNS INTEGER AS $$
BEGIN
  RETURN (
    SELECT COUNT(*)
    FROM devices
    WHERE last_seen_at > NOW() - INTERVAL '60 seconds'
  );
END;
$$ LANGUAGE plpgsql;

-- Create function to get device status summary
CREATE OR REPLACE FUNCTION get_device_status_summary()
RETURNS TABLE (
  status TEXT,
  count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    CASE
      WHEN d.last_seen_at > NOW() - INTERVAL '60 seconds' THEN 'online'
      WHEN d.last_seen_at IS NOT NULL THEN 'offline'
      ELSE 'never_connected'
    END as status,
    COUNT(*) as count
  FROM devices d
  GROUP BY 1
  ORDER BY 1;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_device_status_summary IS
  'Returns count of devices by online status (online, offline, never_connected).';
