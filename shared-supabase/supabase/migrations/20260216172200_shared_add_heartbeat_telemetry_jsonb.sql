-- ============================================================================
-- Migration: 20260216172200_shared_add_heartbeat_telemetry_jsonb.sql
-- Project: shared
-- Description: Add telemetry JSONB column to device_heartbeats for non-blocking
--              heartbeat storage. Firmware can send arbitrary telemetry without
--              requiring schema migrations for new fields.
-- Date: 2026-02-16
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'telemetry'
  ) THEN
    ALTER TABLE device_heartbeats ADD COLUMN telemetry JSONB;
  END IF;
END $$;

COMMENT ON COLUMN device_heartbeats.telemetry IS
  'JSONB blob of all telemetry data from the heartbeat. Replaces individual typed columns. '
  'Structure varies by device type and capabilities. Standard fields: uptime_sec, free_heap, '
  'min_free_heap, largest_free_block. Capability fields: wifi_rssi, battery_level, temperature_c, etc.';

-- GIN index for telemetry queries (jsonb_path_ops is smaller and faster for containment queries)
CREATE INDEX IF NOT EXISTS idx_heartbeats_telemetry
  ON device_heartbeats USING GIN (telemetry jsonb_path_ops);
