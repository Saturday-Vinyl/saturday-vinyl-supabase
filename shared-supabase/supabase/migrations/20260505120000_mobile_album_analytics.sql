-- ============================================================================
-- Migration: 20260505120000_mobile_album_analytics.sql
-- Project: saturday-mobile-app
-- Description: RPC that returns aggregated album analytics for the calling
--              user. Powers the Profile screen's analytics view in the
--              consumer app: totals, top albums/artists/genres, decade
--              distribution across the user's libraries, and a 30-day
--              daily play activity series.
--
--              Returns a single JSONB document so the mobile client only
--              needs one round-trip. Scope is the union of every library
--              the user is a member of (own + shared) for catalog metrics,
--              and listening_history filtered by the user for play metrics.
-- Date: 2026-05-05
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_user_album_analytics(
    p_top_limit INTEGER DEFAULT 5,
    p_activity_days INTEGER DEFAULT 30
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_user_id UUID := get_user_id_from_auth();
    v_result  JSONB;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    -- Clamp inputs to defensive ranges.
    p_top_limit     := GREATEST(1, LEAST(p_top_limit, 50));
    p_activity_days := GREATEST(1, LEAST(p_activity_days, 365));

    WITH user_libraries AS (
        SELECT library_id
          FROM library_members
         WHERE user_id = v_user_id
    ),
    user_library_albums AS (
        SELECT la.id          AS library_album_id,
               la.is_favorite,
               a.id            AS album_id,
               a.title,
               a.artist,
               a.year,
               a.genres,
               a.styles,
               a.cover_image_url
          FROM library_albums la
          JOIN albums a ON a.id = la.album_id
         WHERE la.library_id IN (SELECT library_id FROM user_libraries)
    ),
    plays AS (
        SELECT lh.id,
               lh.library_album_id,
               lh.played_at,
               lh.play_duration_seconds
          FROM listening_history lh
         WHERE lh.user_id = v_user_id
    ),
    play_album AS (
        SELECT p.id,
               p.played_at,
               p.play_duration_seconds,
               la.id    AS library_album_id,
               a.id     AS album_id,
               a.title,
               a.artist,
               a.year,
               a.genres,
               a.cover_image_url
          FROM plays p
          JOIN library_albums la ON la.id = p.library_album_id
          JOIN albums a          ON a.id = la.album_id
    ),
    top_albums AS (
        SELECT library_album_id,
               album_id,
               title,
               artist,
               year,
               cover_image_url,
               COUNT(*)::INTEGER AS play_count
          FROM play_album
         GROUP BY library_album_id, album_id, title, artist, year, cover_image_url
         ORDER BY play_count DESC, title ASC
         LIMIT p_top_limit
    ),
    top_artists AS (
        SELECT artist,
               COUNT(*)::INTEGER AS play_count
          FROM play_album
         WHERE artist IS NOT NULL AND length(trim(artist)) > 0
         GROUP BY artist
         ORDER BY play_count DESC, artist ASC
         LIMIT p_top_limit
    ),
    top_genres AS (
        SELECT genre,
               COUNT(*)::INTEGER AS play_count
          FROM play_album,
               LATERAL UNNEST(COALESCE(genres, ARRAY[]::TEXT[])) AS genre
         WHERE genre IS NOT NULL AND length(trim(genre)) > 0
         GROUP BY genre
         ORDER BY play_count DESC, genre ASC
         LIMIT p_top_limit
    ),
    decade_counts AS (
        SELECT ((year / 10) * 10)::INTEGER AS decade,
               COUNT(DISTINCT album_id)::INTEGER AS album_count
          FROM user_library_albums
         WHERE year IS NOT NULL AND year > 0
         GROUP BY ((year / 10) * 10)
         ORDER BY decade
    ),
    activity_range AS (
        SELECT generate_series(
                   (NOW() AT TIME ZONE 'UTC')::date - (p_activity_days - 1),
                   (NOW() AT TIME ZONE 'UTC')::date,
                   INTERVAL '1 day'
               )::date AS day
    ),
    daily_play_counts AS (
        SELECT (played_at AT TIME ZONE 'UTC')::date AS day,
               COUNT(*)::INTEGER                    AS play_count
          FROM plays
         WHERE played_at >= NOW() - make_interval(days => p_activity_days)
         GROUP BY 1
    ),
    daily_activity AS (
        SELECT ar.day,
               COALESCE(dpc.play_count, 0) AS play_count
          FROM activity_range ar
          LEFT JOIN daily_play_counts dpc ON dpc.day = ar.day
         ORDER BY ar.day
    ),
    totals AS (
        SELECT (SELECT COUNT(*)::INTEGER FROM plays)                                  AS total_plays,
               (SELECT COALESCE(SUM(play_duration_seconds), 0)::BIGINT FROM plays)    AS total_seconds,
               (SELECT COUNT(*)::INTEGER FROM user_library_albums)                    AS total_albums,
               (SELECT COUNT(*)::INTEGER FROM user_library_albums WHERE is_favorite)  AS total_favorites,
               (SELECT COUNT(DISTINCT artist)::INTEGER
                  FROM user_library_albums
                 WHERE artist IS NOT NULL AND length(trim(artist)) > 0)               AS total_artists
    )
    SELECT jsonb_build_object(
        'generated_at', to_jsonb(NOW()),
        'totals',       (SELECT to_jsonb(t.*) FROM totals t),
        'top_albums',   (SELECT COALESCE(jsonb_agg(to_jsonb(ta.*)), '[]'::jsonb) FROM top_albums ta),
        'top_artists',  (SELECT COALESCE(jsonb_agg(to_jsonb(ar.*)), '[]'::jsonb) FROM top_artists ar),
        'top_genres',   (SELECT COALESCE(jsonb_agg(to_jsonb(g.*)),  '[]'::jsonb) FROM top_genres g),
        'decades',      (SELECT COALESCE(jsonb_agg(to_jsonb(d.*)),  '[]'::jsonb) FROM decade_counts d),
        'daily_plays',  (SELECT COALESCE(jsonb_agg(to_jsonb(da.*)), '[]'::jsonb) FROM daily_activity da)
    )
      INTO v_result;

    RETURN v_result;
END;
$function$;

-- Authenticated users can call this function. It is SECURITY DEFINER and
-- always scopes to the calling user via get_user_id_from_auth(); never accept
-- a user id as input.
GRANT EXECUTE ON FUNCTION public.get_user_album_analytics(INTEGER, INTEGER)
    TO authenticated;

-- Helpful index for daily_play and totals aggregations on listening_history.
-- (user_id, played_at) supports both filtering by user and ordering/range
-- scans by played_at within a user.
CREATE INDEX IF NOT EXISTS idx_listening_history_user_played_at
    ON listening_history (user_id, played_at DESC);

COMMENT ON FUNCTION public.get_user_album_analytics(INTEGER, INTEGER) IS
'Returns aggregated album analytics for the authenticated user as a single JSONB document. Includes totals (plays, listening seconds, albums, artists, favorites), top albums/artists/genres by play count, album-count-by-decade across libraries the user is a member of, and a daily play activity series for the last p_activity_days days. Powers the Profile analytics screen in the consumer app.';
