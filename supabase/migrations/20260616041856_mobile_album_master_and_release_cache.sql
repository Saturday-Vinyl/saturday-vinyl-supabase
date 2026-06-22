-- ============================================================================
-- Migration: 20260616041856_mobile_album_master_and_release_cache.sql
-- Project: saturday-mobile-app
-- Description: Add Discogs master metadata to albums so we can display the
--              original release year (today every reissue is mislabelled with
--              its pressing year), keep richer styles, and stably join to
--              "other pressings". Also introduce a shared payload cache for
--              Discogs release responses so the new album content surface
--              works both for owned and not-yet-owned releases without
--              re-fetching every visit.
-- Date: 2026-06-16
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'albums' AND column_name = 'discogs_master_id'
  ) THEN
    ALTER TABLE albums ADD COLUMN discogs_master_id integer;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'albums' AND column_name = 'original_year'
  ) THEN
    ALTER TABLE albums ADD COLUMN original_year integer;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'albums' AND column_name = 'pressing_descriptors'
  ) THEN
    ALTER TABLE albums ADD COLUMN pressing_descriptors text[] DEFAULT '{}';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS albums_discogs_master_id_idx
  ON albums (discogs_master_id);

-- ----------------------------------------------------------------------------
-- discogs_release_cache: shared payload cache for /releases/:id responses.
-- Powers the album content surface for releases the user does not yet own
-- (search-side landing screen) and also avoids re-fetching for owned albums.
-- Payload is the raw Discogs JSON; clients reparse as schemas evolve.
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS discogs_release_cache (
  discogs_release_id integer PRIMARY KEY,
  payload jsonb NOT NULL,
  fetched_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS discogs_release_cache_fetched_at_idx
  ON discogs_release_cache (fetched_at);

ALTER TABLE discogs_release_cache ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read release cache"
  ON discogs_release_cache;
CREATE POLICY "Authenticated users can read release cache"
  ON discogs_release_cache FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert release cache"
  ON discogs_release_cache;
CREATE POLICY "Authenticated users can insert release cache"
  ON discogs_release_cache FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update release cache"
  ON discogs_release_cache;
CREATE POLICY "Authenticated users can update release cache"
  ON discogs_release_cache FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);
