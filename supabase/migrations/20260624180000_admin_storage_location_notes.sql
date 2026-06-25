-- ============================================================================
-- Migration: 20260624180000_admin_storage_location_notes.sql
-- Project: saturday-admin-app
-- Description: Add a free-text `notes` column to storage_locations — the
--   "Contents" note shown in the UI and printed on the location label (e.g.
--   "Phono stage boards, sorted by rev"). Entered by hand or generated from the
--   bin's parts via the summarize-location-contents edge function.
-- Date: 2026-06-24
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'storage_locations' AND column_name = 'notes'
  ) THEN
    ALTER TABLE storage_locations ADD COLUMN notes TEXT;
  END IF;
END $$;

COMMENT ON COLUMN storage_locations.notes IS
  'Free-text contents note for the location, shown in the UI and printed on the label.';
