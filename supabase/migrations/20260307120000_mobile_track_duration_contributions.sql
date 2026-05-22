-- ============================================================================
-- Migration: 20260307120000_mobile_track_duration_contributions.sql
-- Project: saturday-mobile-app
-- Description: Add table and RPC for community-contributed track durations.
--              When an album's track durations are unknown, users can manually
--              time tracks while listening and contribute those durations.
-- Date: 2026-03-07
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- TABLE: album_track_duration_contributions
-- Audit trail of user-contributed track durations.
-- ============================================================================
CREATE TABLE IF NOT EXISTS album_track_duration_contributions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  album_id uuid NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
  contributed_by uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  track_durations jsonb NOT NULL,  -- [{position, duration_seconds}, ...]
  side text,                        -- 'A', 'B', or null for full album
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for lookup by album
CREATE INDEX IF NOT EXISTS idx_album_track_duration_contributions_album_id
  ON album_track_duration_contributions(album_id);

-- Index for lookup by contributor
CREATE INDEX IF NOT EXISTS idx_album_track_duration_contributions_contributed_by
  ON album_track_duration_contributions(contributed_by);

-- ============================================================================
-- RLS POLICIES
-- ============================================================================
ALTER TABLE album_track_duration_contributions ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can view contributions (public data)
DROP POLICY IF EXISTS "Authenticated users can view track duration contributions"
  ON album_track_duration_contributions;
CREATE POLICY "Authenticated users can view track duration contributions"
  ON album_track_duration_contributions FOR SELECT
  USING (auth.role() = 'authenticated');

-- Users can insert their own contributions
DROP POLICY IF EXISTS "Users can contribute track durations"
  ON album_track_duration_contributions;
CREATE POLICY "Users can contribute track durations"
  ON album_track_duration_contributions FOR INSERT
  WITH CHECK (contributed_by = get_user_id_from_auth());

-- ============================================================================
-- RPC: contribute_track_durations
-- Atomically records a contribution and updates the canonical album tracks
-- JSONB, filling in duration_seconds only where it is currently null.
-- ============================================================================
CREATE OR REPLACE FUNCTION contribute_track_durations(
  p_album_id uuid,
  p_contributed_by uuid,
  p_track_durations jsonb,
  p_side text DEFAULT NULL
) RETURNS jsonb AS $$
DECLARE
  v_album_tracks jsonb;
  v_contribution jsonb;
  v_updated_tracks jsonb;
  v_i int;
  v_track jsonb;
  v_pos text;
  v_dur int;
BEGIN
  -- 1. Insert the contribution record
  INSERT INTO album_track_duration_contributions (album_id, contributed_by, track_durations, side)
  VALUES (p_album_id, p_contributed_by, p_track_durations, p_side);

  -- 2. Get the current tracks JSONB from the canonical album
  SELECT tracks INTO v_album_tracks
  FROM albums
  WHERE id = p_album_id;

  IF v_album_tracks IS NULL THEN
    RETURN '{"error": "album not found or has no tracks"}'::jsonb;
  END IF;

  -- 3. Build a lookup from the contributed durations
  --    and update tracks where duration_seconds is null
  v_updated_tracks := '[]'::jsonb;

  FOR v_i IN 0..jsonb_array_length(v_album_tracks) - 1 LOOP
    v_track := v_album_tracks->v_i;
    v_pos := v_track->>'position';

    -- Check if this track has no duration and we have a contribution for it
    IF (v_track->>'duration_seconds') IS NULL THEN
      -- Search the contributed durations for a matching position
      SELECT (elem->>'duration_seconds')::int INTO v_dur
      FROM jsonb_array_elements(p_track_durations) AS elem
      WHERE elem->>'position' = v_pos
      LIMIT 1;

      IF v_dur IS NOT NULL THEN
        v_track := jsonb_set(v_track, '{duration_seconds}', to_jsonb(v_dur));
      END IF;
    END IF;

    v_updated_tracks := v_updated_tracks || jsonb_build_array(v_track);
  END LOOP;

  -- 4. Update the canonical album with merged durations
  UPDATE albums
  SET tracks = v_updated_tracks,
      updated_at = now()
  WHERE id = p_album_id;

  RETURN v_updated_tracks;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
