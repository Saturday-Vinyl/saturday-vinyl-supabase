-- ============================================================================
-- Migration: 20260613120000_mobile_album_discogs_artist_ids.sql
-- Project: saturday-mobile-app
-- Description: Add Discogs artist ID/name arrays to albums for artist
--              disambiguation and multi-artist release support. Enables
--              artist landing pages routed by stable Discogs artist IDs
--              without normalizing artists into a separate table yet.
-- Date: 2026-06-13
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'albums' AND column_name = 'discogs_artist_ids'
  ) THEN
    ALTER TABLE albums ADD COLUMN discogs_artist_ids integer[];
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'albums' AND column_name = 'discogs_artist_names'
  ) THEN
    ALTER TABLE albums ADD COLUMN discogs_artist_names text[];
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS albums_discogs_artist_ids_idx
  ON albums USING gin (discogs_artist_ids);

CREATE INDEX IF NOT EXISTS albums_artist_name_lower_idx
  ON albums (lower(artist));
