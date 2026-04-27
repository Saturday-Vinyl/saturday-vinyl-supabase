/**
 * Edge Function: recommend-albums
 * Project: saturday-vinyl
 * Description: Returns personalized album recommendations from a user's library.
 *
 * Scoring algorithm (v1):
 *   - Genre/style affinity with current album: +3
 *   - Same artist as current album: +2
 *   - Staleness bonus (not played recently): +1 to +3
 *   - Recency penalty (played in last 24h): -2
 *   - Random jitter: +0 to +1 (avoids same recommendations every time)
 */

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RecommendRequest {
  current_album_id?: string // library_album_id of the album that just finished (optional)
  limit?: number
}

interface ScoredAlbum {
  library_album_id: string
  album_id: string
  title: string
  artist: string
  cover_image_url: string | null
  colors: Record<string, unknown> | null
  genres: string[]
  styles: string[]
  score: number
  reason: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Validate auth
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // Authenticate user
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false },
      global: { headers: { Authorization: authHeader } }
    })

    const { data: { user }, error: userError } = await userClient.auth.getUser()
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid authentication' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Service role client for queries (bypasses RLS for joins)
    const adminClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false }
    })

    // Resolve auth.uid() → users.id
    const { data: dbUser, error: dbUserError } = await adminClient
      .from('users')
      .select('id')
      .eq('auth_user_id', user.id)
      .maybeSingle()

    if (dbUserError || !dbUser) {
      return new Response(
        JSON.stringify({ error: 'User record not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const userId = dbUser.id

    // Parse request
    const body: RecommendRequest = await req.json().catch(() => ({}))
    const limit = Math.min(body.limit ?? 3, 10)
    const currentAlbumId = body.current_album_id ?? null

    console.log(`Recommending ${limit} albums for user ${userId}, current: ${currentAlbumId}`)

    // 1. Get user's library albums with full album metadata
    const { data: libraryMembers } = await adminClient
      .from('library_members')
      .select('library_id')
      .eq('user_id', userId)

    if (!libraryMembers || libraryMembers.length === 0) {
      return new Response(
        JSON.stringify({ recommendations: [] }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const libraryIds = libraryMembers.map((m: { library_id: string }) => m.library_id)

    const { data: libraryAlbums, error: albumsError } = await adminClient
      .from('library_albums')
      .select('id, album_id, albums(id, title, artist, cover_image_url, colors, genres, styles)')
      .in('library_id', libraryIds)

    if (albumsError || !libraryAlbums) {
      console.error('Error fetching library albums:', albumsError)
      return new Response(
        JSON.stringify({ recommendations: [] }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Get recent listening history
    const { data: recentHistory } = await adminClient
      .from('listening_history')
      .select('library_album_id, played_at')
      .eq('user_id', userId)
      .order('played_at', { ascending: false })
      .limit(20)

    const recentlyPlayedIds = new Set(
      (recentHistory ?? []).slice(0, 3).map((h: { library_album_id: string }) => h.library_album_id)
    )

    const playedInLast24h = new Set(
      (recentHistory ?? [])
        .filter((h: { played_at: string }) => {
          const playedAt = new Date(h.played_at)
          const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000)
          return playedAt > oneDayAgo
        })
        .map((h: { library_album_id: string }) => h.library_album_id)
    )

    // Build a map of library_album_id → last played date for staleness scoring
    const lastPlayedMap = new Map<string, Date>()
    for (const h of (recentHistory ?? [])) {
      if (!lastPlayedMap.has(h.library_album_id)) {
        lastPlayedMap.set(h.library_album_id, new Date(h.played_at))
      }
    }

    // 3. Get current album metadata for affinity scoring
    let currentAlbumGenres: string[] = []
    let currentAlbumStyles: string[] = []
    let currentAlbumArtist: string | null = null

    if (currentAlbumId) {
      const currentEntry = libraryAlbums.find(
        (la: { id: string }) => la.id === currentAlbumId
      )
      if (currentEntry?.albums) {
        const album = currentEntry.albums as {
          genres: string[] | null
          styles: string[] | null
          artist: string
        }
        currentAlbumGenres = album.genres ?? []
        currentAlbumStyles = album.styles ?? []
        currentAlbumArtist = album.artist
      }
    }

    // 4. Score each album
    const now = Date.now()
    const scored: ScoredAlbum[] = []

    for (const la of libraryAlbums) {
      // Skip the current album
      if (la.id === currentAlbumId) continue
      // Skip the 3 most recently played
      if (recentlyPlayedIds.has(la.id)) continue

      const album = la.albums as {
        id: string
        title: string
        artist: string
        cover_image_url: string | null
        colors: Record<string, unknown> | null
        genres: string[] | null
        styles: string[] | null
      } | null
      if (!album) continue

      let score = 0
      let reason = ''
      const albumGenres = album.genres ?? []
      const albumStyles = album.styles ?? []

      // Genre/style affinity (+3)
      if (currentAlbumId) {
        const sharedGenres = albumGenres.filter(g => currentAlbumGenres.includes(g))
        const sharedStyles = albumStyles.filter(s => currentAlbumStyles.includes(s))
        if (sharedGenres.length > 0 || sharedStyles.length > 0) {
          score += 3
          if (!reason) reason = `Similar ${sharedGenres.length > 0 ? 'genre' : 'style'}`
        }
      }

      // Same artist (+2)
      if (currentAlbumArtist && album.artist === currentAlbumArtist) {
        score += 2
        reason = 'Same artist'
      }

      // Staleness bonus (+1 to +3)
      const lastPlayed = lastPlayedMap.get(la.id)
      if (!lastPlayed) {
        // Never played — highest staleness bonus
        score += 3
        if (!reason) reason = "You haven't played this yet"
      } else {
        const daysSincePlayed = (now - lastPlayed.getTime()) / (1000 * 60 * 60 * 24)
        if (daysSincePlayed > 30) {
          score += 3
          if (!reason) reason = "You haven't played this in a while"
        } else if (daysSincePlayed > 7) {
          score += 2
          if (!reason) reason = 'Not played recently'
        } else if (daysSincePlayed > 1) {
          score += 1
        }
      }

      // Recency penalty (-2)
      if (playedInLast24h.has(la.id)) {
        score -= 2
      }

      // Random jitter (+0 to +1)
      score += Math.random()

      // Default reason
      if (!reason) reason = 'From your collection'

      scored.push({
        library_album_id: la.id,
        album_id: album.id,
        title: album.title,
        artist: album.artist,
        cover_image_url: album.cover_image_url,
        colors: album.colors,
        genres: albumGenres,
        styles: albumStyles,
        score,
        reason,
      })
    }

    // 5. Sort by score descending and take top N
    scored.sort((a, b) => b.score - a.score)
    const topAlbums = scored.slice(0, limit)

    // 6. Enrich with last known location
    const topAlbumIds = topAlbums.map(a => a.library_album_id)

    let locationMap = new Map<string, { device_name: string; device_id: string; detected_at: string }>()

    if (topAlbumIds.length > 0) {
      const { data: locations } = await adminClient
        .from('album_locations')
        .select('library_album_id, device_id, detected_at, units(id, consumer_name)')
        .in('library_album_id', topAlbumIds)
        .is('removed_at', null)
        .order('detected_at', { ascending: false })

      if (locations) {
        for (const loc of locations) {
          // Only keep the most recent location per album
          if (!locationMap.has(loc.library_album_id)) {
            const unit = loc.units as { id: string; consumer_name: string | null } | null
            locationMap.set(loc.library_album_id, {
              device_name: unit?.consumer_name ?? 'Unknown Crate',
              device_id: loc.device_id,
              detected_at: loc.detected_at,
            })
          }
        }
      }
    }

    // 7. Build response
    const recommendations = topAlbums.map(album => {
      const location = locationMap.get(album.library_album_id)
      return {
        library_album_id: album.library_album_id,
        album_id: album.album_id,
        title: album.title,
        artist: album.artist,
        cover_image_url: album.cover_image_url,
        colors: album.colors,
        reason: album.reason,
        last_location: location ?? null,
      }
    })

    console.log(`Returning ${recommendations.length} recommendations`)

    return new Response(
      JSON.stringify({ recommendations }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
