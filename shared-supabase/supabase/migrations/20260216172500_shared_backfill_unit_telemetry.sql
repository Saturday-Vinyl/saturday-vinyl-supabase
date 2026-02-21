-- ============================================================================
-- Migration: 20260216172500_shared_backfill_unit_telemetry.sql
-- Project: shared
-- Description: One-time backfill to populate units telemetry columns from
--              existing devices.latest_telemetry and devices.last_seen_at data.
--              Uses COALESCE to avoid overwriting any values that may have been
--              set by heartbeats that arrived between Migration 3 and this one.
-- Date: 2026-02-16
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Backfill from the primary device (first device by created_at per unit).
-- DISTINCT ON (unit_id) ensures one row per unit even for multi-device units.
UPDATE units u
SET
  last_seen_at = COALESCE(u.last_seen_at, d.last_seen_at),
  is_online = COALESCE(
    u.is_online,
    CASE
      WHEN d.last_seen_at > NOW() - INTERVAL '5 minutes' THEN true
      ELSE false
    END
  ),
  firmware_version = COALESCE(u.firmware_version, d.firmware_version),
  battery_level = COALESCE(
    u.battery_level,
    (d.latest_telemetry->>'battery_level')::INTEGER
  ),
  is_charging = COALESCE(
    u.is_charging,
    (d.latest_telemetry->>'battery_charging')::BOOLEAN
  ),
  wifi_rssi = COALESCE(
    u.wifi_rssi,
    (d.latest_telemetry->>'wifi_rssi')::INTEGER
  ),
  temperature_c = COALESCE(
    u.temperature_c,
    (d.latest_telemetry->>'temperature_c')::NUMERIC
  ),
  humidity_pct = COALESCE(
    u.humidity_pct,
    (d.latest_telemetry->>'humidity_pct')::NUMERIC
  )
FROM (
  SELECT DISTINCT ON (unit_id) *
  FROM devices
  WHERE unit_id IS NOT NULL
    AND last_seen_at IS NOT NULL
  ORDER BY unit_id, created_at ASC
) d
WHERE d.unit_id = u.id;
