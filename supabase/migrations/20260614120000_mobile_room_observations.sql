-- ============================================================================
-- Migration: 20260614120000_mobile_room_observations.sql
-- Project: saturday-mobile-app
-- Description: RPC that returns one "room observation" for the listening
--              room — a quiet, observational line in the witness register
--              (e.g. "Last week around this time, Sketches of Spain was on
--              the stand."). v1 covers three categories: temporal echo,
--              cratelist quiet, recurring record. See docs/ROOM_OBSERVATIONS.md.
-- Date: 2026-06-14
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- VOLATILE because of random() in the candidate picker. Returns at most
-- one row; returns zero rows when no category meets its threshold (the
-- room shows nothing, per the constitution's preference for absence).
CREATE OR REPLACE FUNCTION public.mobile_room_observation()
RETURNS TABLE (
  kind                 text,
  library_album_id     uuid,
  album_title          text,
  album_artist         text,
  cratelist_id         uuid,
  cratelist_name       text,
  days_ago             int,
  days_since_last_play int,
  play_count           int
)
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  -- Resolve auth.uid() to users.id (the application-level id used by
  -- listening_history.user_id, cratelists.created_by, etc.). Following
  -- the pattern documented in shared-supabase/CLAUDE.md.
  SELECT u.id INTO v_user_id
  FROM users u
  WHERE u.auth_user_id = auth.uid();

  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH
  -- ────────────────────────────────────────────────────────────────────
  -- 1. Temporal echo
  -- A previous play on the same weekday, within ±2 hours of now, at
  -- least 3 days ago. We bucket the age into three named windows
  -- (last week / a month ago / a year ago); rows outside those windows
  -- don't qualify.
  -- ────────────────────────────────────────────────────────────────────
  temporal_candidates AS (
    SELECT
      lh.library_album_id,
      a.title  AS album_title,
      a.artist AS album_artist,
      EXTRACT(DAY FROM (now() - lh.played_at))::int AS days_ago
    FROM listening_history lh
    JOIN library_albums la ON la.id = lh.library_album_id
    JOIN albums a          ON a.id  = la.album_id
    WHERE lh.user_id = v_user_id
      AND EXTRACT(DOW FROM lh.played_at) = EXTRACT(DOW FROM now())
      AND ABS(EXTRACT(HOUR FROM lh.played_at) - EXTRACT(HOUR FROM now())) <= 2
      AND lh.played_at < now() - interval '3 days'
      AND lh.played_at > now() - interval '400 days'
  ),
  temporal_qualified AS (
    SELECT * FROM temporal_candidates
    WHERE days_ago BETWEEN 7  AND 14
       OR days_ago BETWEEN 28 AND 35
       OR days_ago BETWEEN 360 AND 370
  ),
  temporal AS (
    SELECT
      'temporal_echo'::text AS kind,
      library_album_id,
      album_title,
      album_artist,
      NULL::uuid AS cratelist_id,
      NULL::text AS cratelist_name,
      days_ago,
      NULL::int  AS days_since_last_play,
      NULL::int  AS play_count
    FROM temporal_qualified
    ORDER BY random()
    LIMIT 1
  ),

  -- ────────────────────────────────────────────────────────────────────
  -- 4. Cratelist quiet
  -- Cratelists the listener owns, with at least three items, where no
  -- item has been played in the last 30 days.
  -- ────────────────────────────────────────────────────────────────────
  cratelist_candidates AS (
    SELECT
      cl.id   AS cratelist_id,
      cl.name AS cratelist_name,
      MAX(lh.played_at) AS last_play,
      COUNT(DISTINCT ci.library_album_id) AS size
    FROM cratelists cl
    JOIN cratelist_items ci ON ci.cratelist_id = cl.id
    LEFT JOIN listening_history lh
      ON lh.library_album_id = ci.library_album_id
     AND lh.user_id = v_user_id
    WHERE cl.created_by = v_user_id
    GROUP BY cl.id, cl.name
    HAVING COUNT(DISTINCT ci.library_album_id) >= 3
       AND (
            MAX(lh.played_at) IS NULL
         OR MAX(lh.played_at) < now() - interval '30 days'
       )
  ),
  cratelist AS (
    SELECT
      'cratelist_quiet'::text AS kind,
      NULL::uuid AS library_album_id,
      NULL::text AS album_title,
      NULL::text AS album_artist,
      cratelist_id,
      cratelist_name,
      NULL::int  AS days_ago,
      CASE
        WHEN last_play IS NULL THEN NULL
        ELSE EXTRACT(DAY FROM (now() - last_play))::int
      END AS days_since_last_play,
      NULL::int AS play_count
    FROM cratelist_candidates
    ORDER BY random()
    LIMIT 1
  ),

  -- ────────────────────────────────────────────────────────────────────
  -- 6. Recurring record
  -- Albums played five or more times in the last 90 days.
  -- ────────────────────────────────────────────────────────────────────
  recurring_candidates AS (
    SELECT
      lh.library_album_id,
      a.title  AS album_title,
      a.artist AS album_artist,
      COUNT(*)::int AS play_count
    FROM listening_history lh
    JOIN library_albums la ON la.id = lh.library_album_id
    JOIN albums a          ON a.id  = la.album_id
    WHERE lh.user_id = v_user_id
      AND lh.played_at > now() - interval '90 days'
    GROUP BY lh.library_album_id, a.title, a.artist
    HAVING COUNT(*) >= 5
  ),
  recurring AS (
    SELECT
      'recurring_record'::text AS kind,
      library_album_id,
      album_title,
      album_artist,
      NULL::uuid AS cratelist_id,
      NULL::text AS cratelist_name,
      NULL::int  AS days_ago,
      NULL::int  AS days_since_last_play,
      play_count
    FROM recurring_candidates
    ORDER BY random()
    LIMIT 1
  )

  -- One winner across all qualifying candidates, picked uniformly.
  SELECT * FROM (
    SELECT * FROM temporal
    UNION ALL
    SELECT * FROM cratelist
    UNION ALL
    SELECT * FROM recurring
  ) pool
  ORDER BY random()
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mobile_room_observation() TO authenticated;
