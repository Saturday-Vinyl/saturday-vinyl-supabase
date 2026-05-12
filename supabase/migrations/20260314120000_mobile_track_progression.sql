-- ============================================================================
-- Migration: 20260314120000_mobile_track_progression.sql
-- Project: saturday-mobile-app
-- Description: Add current_track_index to playback_sessions for server-side
--              track progression tracking. Used by the update-track-progression
--              cron function to keep iOS Live Activities updated when the app
--              is backgrounded.
-- Date: 2026-03-14
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Add current_track_index column to playback_sessions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'playback_sessions' AND column_name = 'current_track_index'
  ) THEN
    ALTER TABLE playback_sessions ADD COLUMN current_track_index int;
  END IF;
END $$;

-- Add a comment for documentation
COMMENT ON COLUMN playback_sessions.current_track_index IS
  'Server-calculated 0-based index of the current track within the current side. Updated by the update-track-progression cron function.';
