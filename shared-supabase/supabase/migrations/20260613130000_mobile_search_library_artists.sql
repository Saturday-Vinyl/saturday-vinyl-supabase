-- ============================================================================
-- Migration: 20260613130000_mobile_search_library_artists.sql
-- Project: saturday-mobile-app
-- Description: RPC that returns distinct Discogs-identified artists in a
--              library matching a query string, with per-artist album
--              counts. Backs the "Artists" section of global search and
--              the artist landing page's library count.
-- Date: 2026-06-13
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

CREATE OR REPLACE FUNCTION public.search_library_artists(
  p_library_id uuid,
  p_query      text,
  p_limit      integer DEFAULT 10
)
RETURNS TABLE (
  discogs_artist_id integer,
  name              text,
  album_count       bigint
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH credited AS (
    SELECT
      la.album_id,
      a.discogs_artist_ids[i] AS aid,
      a.discogs_artist_names[i] AS aname
    FROM library_albums la
    JOIN albums a ON a.id = la.album_id
    CROSS JOIN LATERAL generate_subscripts(a.discogs_artist_ids, 1) AS i
    WHERE la.library_id = p_library_id
      AND a.discogs_artist_ids IS NOT NULL
  )
  SELECT
    aid                                  AS discogs_artist_id,
    MODE() WITHIN GROUP (ORDER BY aname) AS name,
    COUNT(DISTINCT album_id)             AS album_count
  FROM credited
  WHERE aname ILIKE '%' || p_query || '%'
  GROUP BY aid
  ORDER BY album_count DESC, name ASC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.search_library_artists(uuid, text, integer)
  TO authenticated;


-- Returns albums in a library credited to a given Discogs artist ID,
-- newest first. Backs the artist landing page's "In your library" section.
CREATE OR REPLACE FUNCTION public.get_library_albums_by_artist(
  p_library_id        uuid,
  p_discogs_artist_id integer
)
RETURNS TABLE (
  id          uuid,
  library_id  uuid,
  album_id    uuid,
  added_at    timestamptz,
  added_by    uuid,
  is_favorite boolean,
  notes       text,
  album       jsonb
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    la.id,
    la.library_id,
    la.album_id,
    la.added_at,
    la.added_by,
    la.is_favorite,
    la.notes,
    to_jsonb(a) AS album
  FROM library_albums la
  JOIN albums a ON a.id = la.album_id
  WHERE la.library_id = p_library_id
    AND p_discogs_artist_id = ANY(a.discogs_artist_ids)
  ORDER BY a.year DESC NULLS LAST, a.title ASC;
$$;

GRANT EXECUTE ON FUNCTION public.get_library_albums_by_artist(uuid, integer)
  TO authenticated;
