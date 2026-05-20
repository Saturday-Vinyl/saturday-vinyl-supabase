-- ============================================================================
-- Migration: 20260427180000_firmware_firmware_files_anon_read.sql
-- Project: sv-hub-firmware
-- Description: Allow anon SELECT on firmware_files so devices can pull H2
--              secondary firmware URLs during ota_update bundles.
-- Date: 2026-04-27
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Devices authenticate to Supabase REST with the anon key (anon role).
-- The schema's intent (per firmware_files comment: "Master file is pushed via
-- OTA, secondary files are pulled by device after update") requires the device
-- to read firmware_files, but the existing read policy is TO authenticated only.
-- Add an anon-readable policy mirroring the public-read pattern used for
-- device-facing tables like device_heartbeats.

DROP POLICY IF EXISTS "Devices can read firmware_files" ON firmware_files;
CREATE POLICY "Devices can read firmware_files"
ON firmware_files FOR SELECT
TO anon
USING (true);
