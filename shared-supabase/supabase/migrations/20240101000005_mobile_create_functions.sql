-- Migration: Create helper functions for Saturday Consumer App
-- This migration is idempotent - safe to run multiple times
-- Depends on: 20240101000002_create_tables.sql
--
-- NOTE: The admin app has its own handle_new_user function.
-- We create a consumer-specific one that works with auth_user_id.

-- ============================================================================
-- CONSUMER USER CREATION TRIGGER
-- ============================================================================
-- When a consumer signs up via Supabase Auth (email/password or social),
-- create or link a user record in the users table.

CREATE OR REPLACE FUNCTION handle_consumer_auth_signup()
RETURNS TRIGGER AS $$
DECLARE
    v_existing_user_id UUID;
BEGIN
    -- Check if a user with this email already exists (e.g., admin user)
    SELECT id INTO v_existing_user_id
    FROM public.users
    WHERE email = NEW.email;

    IF v_existing_user_id IS NOT NULL THEN
        -- Link existing user to auth.users via auth_user_id
        UPDATE public.users
        SET
            auth_user_id = NEW.id,
            avatar_url = COALESCE(users.avatar_url, NEW.raw_user_meta_data->>'avatar_url'),
            full_name = COALESCE(users.full_name, NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'),
            last_login = NOW()
        WHERE id = v_existing_user_id;
    ELSE
        -- Create new user for consumer
        INSERT INTO public.users (
            id,
            email,
            full_name,
            avatar_url,
            auth_user_id,
            created_at,
            last_login
        )
        VALUES (
            gen_random_uuid(),
            NEW.email,
            COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'),
            NEW.raw_user_meta_data->>'avatar_url',
            NEW.id,
            NOW(),
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop and recreate trigger
DROP TRIGGER IF EXISTS on_consumer_auth_signup ON auth.users;
CREATE TRIGGER on_consumer_auth_signup
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION handle_consumer_auth_signup();

-- ============================================================================
-- AUTO-CREATE OWNER MEMBERSHIP
-- ============================================================================
-- When a library is created, automatically add the creator as owner

CREATE OR REPLACE FUNCTION handle_new_library()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO library_members (library_id, user_id, role, joined_at)
    VALUES (NEW.id, NEW.created_by, 'owner', NOW())
    ON CONFLICT (library_id, user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_library_created ON libraries;
CREATE TRIGGER on_library_created
    AFTER INSERT ON libraries
    FOR EACH ROW
    EXECUTE FUNCTION handle_new_library();

-- ============================================================================
-- TAG ASSOCIATION HELPER
-- ============================================================================
-- Function to safely associate an existing rfid_tag with a library album
-- Uses the existing rfid_tags table from admin app

CREATE OR REPLACE FUNCTION associate_rfid_tag(
    p_epc TEXT,
    p_library_album_id UUID,
    p_user_id UUID
)
RETURNS rfid_tags AS $$
DECLARE
    v_tag rfid_tags;
BEGIN
    -- Update the existing tag with association info
    UPDATE rfid_tags
    SET
        library_album_id = p_library_album_id,
        associated_at = NOW(),
        associated_by = p_user_id,
        updated_at = NOW()
    WHERE epc_identifier = p_epc
    RETURNING * INTO v_tag;

    -- If tag doesn't exist, this is an error (tags must be created by admin app)
    IF v_tag IS NULL THEN
        RAISE EXCEPTION 'Tag with EPC % not found. Tags must be provisioned via admin app.', p_epc;
    END IF;

    RETURN v_tag;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- LISTENING HISTORY HELPER
-- ============================================================================
-- Function to record or update a listening session

CREATE OR REPLACE FUNCTION record_play(
    p_user_id UUID,
    p_library_album_id UUID,
    p_device_id UUID DEFAULT NULL
)
RETURNS listening_history AS $$
DECLARE
    v_history listening_history;
BEGIN
    INSERT INTO listening_history (user_id, library_album_id, played_at, device_id)
    VALUES (p_user_id, p_library_album_id, NOW(), p_device_id)
    RETURNING * INTO v_history;

    RETURN v_history;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- ALBUM SEARCH FUNCTION
-- ============================================================================
-- Full-text search function for albums

CREATE OR REPLACE FUNCTION search_albums(
    p_query TEXT,
    p_limit INTEGER DEFAULT 20,
    p_offset INTEGER DEFAULT 0
)
RETURNS SETOF albums AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM albums
    WHERE to_tsvector('english', title || ' ' || artist || ' ' || COALESCE(label, ''))
          @@ plainto_tsquery('english', p_query)
    ORDER BY ts_rank(
        to_tsvector('english', title || ' ' || artist || ' ' || COALESCE(label, '')),
        plainto_tsquery('english', p_query)
    ) DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- GET LIBRARY ALBUMS WITH DETAILS
-- ============================================================================
-- Function to get library albums with album details and current location

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
        d.name AS current_device_name
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
    LEFT JOIN consumer_devices d ON d.id = al.device_id
    WHERE la.library_id = p_library_id
    ORDER BY la.added_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- GET ALBUM PLAY COUNT
-- ============================================================================
-- Function to get play count for an album

CREATE OR REPLACE FUNCTION get_album_play_count(p_library_album_id UUID)
RETURNS INTEGER AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*)::INTEGER INTO v_count
    FROM listening_history
    WHERE library_album_id = p_library_album_id;

    RETURN v_count;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- GET RECENTLY PLAYED ALBUMS
-- ============================================================================
-- Function to get user's recently played albums

CREATE OR REPLACE FUNCTION get_recently_played(
    p_user_id UUID,
    p_limit INTEGER DEFAULT 10
)
RETURNS TABLE (
    library_album_id UUID,
    title TEXT,
    artist TEXT,
    cover_image_url TEXT,
    last_played_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (la.id)
        la.id AS library_album_id,
        a.title,
        a.artist,
        a.cover_image_url,
        lh.played_at AS last_played_at
    FROM listening_history lh
    JOIN library_albums la ON la.id = lh.library_album_id
    JOIN albums a ON a.id = la.album_id
    WHERE lh.user_id = p_user_id
    ORDER BY la.id, lh.played_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- RESOLVE TAG TO ALBUM
-- ============================================================================
-- Function to look up an EPC and return the associated album info

CREATE OR REPLACE FUNCTION resolve_tag_to_album(p_epc TEXT)
RETURNS TABLE (
    tag_id UUID,
    epc_identifier VARCHAR(24),
    library_album_id UUID,
    album_id UUID,
    title TEXT,
    artist TEXT,
    cover_image_url TEXT,
    library_id UUID,
    library_name TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id AS tag_id,
        t.epc_identifier,
        t.library_album_id,
        a.id AS album_id,
        a.title,
        a.artist,
        a.cover_image_url,
        l.id AS library_id,
        l.name AS library_name
    FROM rfid_tags t
    LEFT JOIN library_albums la ON la.id = t.library_album_id
    LEFT JOIN albums a ON a.id = la.album_id
    LEFT JOIN libraries l ON l.id = la.library_id
    WHERE t.epc_identifier = p_epc;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================================
-- GET OR CREATE USER FROM AUTH
-- ============================================================================
-- Helper function for repositories to get the users table record from auth

CREATE OR REPLACE FUNCTION get_or_create_consumer_user()
RETURNS users AS $$
DECLARE
    v_user users;
    v_auth_user_id UUID;
    v_email TEXT;
BEGIN
    v_auth_user_id := auth.uid();

    IF v_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Try to find existing user by auth_user_id
    SELECT * INTO v_user
    FROM users
    WHERE auth_user_id = v_auth_user_id;

    IF v_user IS NOT NULL THEN
        RETURN v_user;
    END IF;

    -- Get email from auth.users
    SELECT email INTO v_email
    FROM auth.users
    WHERE id = v_auth_user_id;

    -- Try to find by email (existing admin user)
    SELECT * INTO v_user
    FROM users
    WHERE email = v_email;

    IF v_user IS NOT NULL THEN
        -- Link to auth_user_id
        UPDATE users
        SET auth_user_id = v_auth_user_id, last_login = NOW()
        WHERE id = v_user.id
        RETURNING * INTO v_user;
        RETURN v_user;
    END IF;

    -- Create new user
    INSERT INTO users (id, email, auth_user_id, created_at, last_login)
    VALUES (gen_random_uuid(), v_email, v_auth_user_id, NOW(), NOW())
    RETURNING * INTO v_user;

    RETURN v_user;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
