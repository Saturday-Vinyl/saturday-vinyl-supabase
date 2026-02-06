-- ============================================================================
-- Migration: 20260126150000_add_device_telemetry_and_dashboard_view.sql
-- Description: Add latest_telemetry to devices, update heartbeat trigger,
--              create units_dashboard view, enable realtime
-- Date: 2026-01-26
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Step 1: Add latest_telemetry column to devices table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'devices' AND column_name = 'latest_telemetry'
  ) THEN
    ALTER TABLE devices ADD COLUMN latest_telemetry JSONB DEFAULT '{}';
  END IF;
END $$;

COMMENT ON COLUMN devices.latest_telemetry IS
  'Denormalized latest heartbeat telemetry data. Updated by heartbeat trigger. Schema: capability-scoped (e.g., {"power": {"battery_level": 85}, "wifi": {"rssi": -45}})';

-- Step 2: Create index for telemetry queries (GIN for JSONB)
CREATE INDEX IF NOT EXISTS idx_devices_latest_telemetry
ON devices USING GIN (latest_telemetry);

-- Step 3: Update the heartbeat trigger to also update latest_telemetry
-- This replaces the existing function from 20260125060000_device_commands_and_heartbeats.sql
CREATE OR REPLACE FUNCTION update_device_last_seen()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE devices
  SET
    last_seen_at = NEW.received_at,
    firmware_version = COALESCE(NEW.firmware_version, firmware_version),
    latest_telemetry = COALESCE(NEW.heartbeat_data, latest_telemetry)
  WHERE mac_address = NEW.mac_address;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 4: Create optimized view for unit list queries
-- Uses LATERAL join to efficiently get the primary (first) device per unit
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
  d.device_type_id,
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

-- Step 5: Enable Supabase Realtime for devices and units tables
-- Note: This may error if tables are already in the publication, which is fine
DO $$
BEGIN
  -- Check if publication exists
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    -- Try to add devices table
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE devices;
    EXCEPTION
      WHEN duplicate_object THEN
        -- Table already in publication, ignore
        NULL;
    END;

    -- Try to add units table
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE units;
    EXCEPTION
      WHEN duplicate_object THEN
        -- Table already in publication, ignore
        NULL;
    END;
  END IF;
END $$;

-- Step 6: Grant select on view to authenticated users
GRANT SELECT ON units_dashboard TO authenticated;
