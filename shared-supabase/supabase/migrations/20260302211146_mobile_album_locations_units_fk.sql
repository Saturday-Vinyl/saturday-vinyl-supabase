-- ============================================================================
-- Migration: 20260302211146_mobile_album_locations_units_fk.sql
-- Project: saturday-consumer-app
-- Description: Migrate album_locations.device_id FK from consumer_devices to
--              units, update RLS policies accordingly, add service_role policy
--              for edge functions, update get_library_albums_with_details to
--              join units, and add album_locations to realtime publication.
-- Date: 2026-03-02
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

--------------------------------------------------------------------------------
-- Step 1: Migrate FK from consumer_devices(id) to units(id)
--------------------------------------------------------------------------------

-- Drop old FK constraint
ALTER TABLE album_locations DROP CONSTRAINT IF EXISTS album_locations_device_id_fkey;

-- Add new FK constraint referencing units
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'album_locations_device_id_units_fkey'
    ) THEN
        ALTER TABLE album_locations
            ADD CONSTRAINT album_locations_device_id_units_fkey
            FOREIGN KEY (device_id) REFERENCES units(id) ON DELETE CASCADE;
    END IF;
END $$;

--------------------------------------------------------------------------------
-- Step 2: Update RLS policies to use units instead of consumer_devices
--------------------------------------------------------------------------------

-- Replace INSERT policy: check units.consumer_user_id
DROP POLICY IF EXISTS "Device owners can create album locations" ON album_locations;
CREATE POLICY "Device owners can create album locations"
    ON album_locations FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM units u
            WHERE u.id = device_id
            AND u.consumer_user_id = get_user_id_from_auth()
        )
    );

-- Replace UPDATE policy: check units.consumer_user_id
DROP POLICY IF EXISTS "Device owners can update album locations" ON album_locations;
CREATE POLICY "Device owners can update album locations"
    ON album_locations FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM units u
            WHERE u.id = album_locations.device_id
            AND u.consumer_user_id = get_user_id_from_auth()
        )
    );

-- Add service_role ALL policy for edge functions
DROP POLICY IF EXISTS "Service role can manage album locations" ON album_locations;
CREATE POLICY "Service role can manage album locations"
    ON album_locations FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

--------------------------------------------------------------------------------
-- Step 3: Update get_library_albums_with_details to join units
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION get_library_albums_with_details(
    p_library_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    library_album_id UUID,
    library_id UUID,
    album_id UUID,
    added_at TIMESTAMPTZ,
    added_by UUID,
    notes TEXT,
    is_favorite BOOLEAN,
    title TEXT,
    artist TEXT,
    year INTEGER,
    genres TEXT[],
    styles TEXT[],
    label TEXT,
    cover_image_url TEXT,
    tracks JSONB,
    current_device_id UUID,
    current_device_name TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        la.id AS library_album_id,
        la.library_id,
        la.album_id,
        la.added_at,
        la.added_by,
        la.notes,
        la.is_favorite,
        a.title,
        a.artist,
        a.year,
        a.genres,
        a.styles,
        a.label,
        a.cover_image_url,
        a.tracks,
        al.device_id AS current_device_id,
        u.consumer_name AS current_device_name
    FROM library_albums la
    JOIN albums a ON a.id = la.album_id
    LEFT JOIN LATERAL (
        SELECT alock.device_id
        FROM album_locations alock
        WHERE alock.library_album_id = la.id
        AND alock.removed_at IS NULL
        ORDER BY alock.detected_at DESC
        LIMIT 1
    ) al ON true
    LEFT JOIN units u ON u.id = al.device_id
    WHERE la.library_id = p_library_id
    ORDER BY la.added_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

--------------------------------------------------------------------------------
-- Step 4: Add album_locations to realtime publication
--------------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
            AND schemaname = 'public'
            AND tablename = 'album_locations'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE album_locations;
        END IF;
    END IF;
END $$;

--------------------------------------------------------------------------------
-- Step 5: Webhook trigger for process-crate-inventory edge function
--------------------------------------------------------------------------------

DROP TRIGGER IF EXISTS crate_inventory_events_webhook ON crate_inventory_events;

CREATE TRIGGER crate_inventory_events_webhook
    AFTER INSERT ON crate_inventory_events
    FOR EACH ROW
    EXECUTE FUNCTION supabase_functions.http_request(
        'https://ddhcmhbwppiqrqmefynv.supabase.co/functions/v1/process-crate-inventory',
        'POST',
        '{"Content-type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRkaGNtaGJ3cHBpcXJxbWVmeW52Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1OTk1MDA5MSwiZXhwIjoyMDc1NTI2MDkxfQ.KV7Ro37KMRr6D1zQEPd81hJMOTcLMO97oBbOVXnPPxc"}',
        '{}',
        '5000'
    );
