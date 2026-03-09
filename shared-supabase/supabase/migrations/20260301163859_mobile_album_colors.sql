-- ============================================================================
-- Migration: 20260301163859_mobile_album_colors.sql
-- Project: mobile
-- Description: Add colors JSONB column to albums table for extracted
--              cover art color palettes (light/dark separation for LED vs UI).
--              Also adds album_colors to user_now_playing_notifications so the
--              device pipeline can access colors for LED patterns.
-- Date: 2026-03-01
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'albums'
      AND column_name = 'colors'
  ) THEN
    ALTER TABLE albums ADD COLUMN colors JSONB;
    RAISE NOTICE 'Added colors column to albums table';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_now_playing_notifications'
      AND column_name = 'album_colors'
  ) THEN
    ALTER TABLE user_now_playing_notifications ADD COLUMN album_colors JSONB;
    RAISE NOTICE 'Added album_colors column to user_now_playing_notifications table';
  END IF;
END $$;
