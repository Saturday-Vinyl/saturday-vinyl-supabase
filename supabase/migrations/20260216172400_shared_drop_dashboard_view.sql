-- ============================================================================
-- Migration: 20260216172400_shared_drop_dashboard_view.sql
-- Project: shared
-- Description: Drop units_dashboard and units_with_devices views. With telemetry
--              columns now on units directly, these views are unnecessary.
--              Admin apps can query units with .select('*, devices(*)') instead.
-- Date: 2026-02-16
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DROP VIEW IF EXISTS units_dashboard;
DROP VIEW IF EXISTS units_with_devices;
