-- Migration: Create Row Level Security (RLS) policies for Saturday Consumer App
-- This migration is idempotent - safe to run multiple times
-- Depends on: 20240101000002_create_tables.sql
--
-- NOTE: This migration adds RLS policies for consumer app tables.
-- The existing users and rfid_tags tables already have RLS from the admin app.

-- ============================================================================
-- ENABLE RLS ON NEW TABLES
-- ============================================================================
-- Note: users and rfid_tags already have RLS enabled from admin app
ALTER TABLE libraries ENABLE ROW LEVEL SECURITY;
ALTER TABLE library_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE albums ENABLE ROW LEVEL SECURITY;
ALTER TABLE library_albums ENABLE ROW LEVEL SECURITY;
ALTER TABLE consumer_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE listening_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE album_locations ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- HELPER FUNCTIONS FOR CONSUMER APP
-- ============================================================================

-- Function to get user_id from auth.uid() via auth_user_id column
-- This bridges Supabase Auth with our users table
CREATE OR REPLACE FUNCTION get_user_id_from_auth()
RETURNS UUID AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- First try to find user by auth_user_id (consumer auth flow)
    SELECT id INTO v_user_id
    FROM users
    WHERE auth_user_id = auth.uid();

    -- If not found, try direct id match (for compatibility)
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id
        FROM users
        WHERE id = auth.uid();
    END IF;

    RETURN v_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Function to check if user is a member of a library
CREATE OR REPLACE FUNCTION is_library_member(lib_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM library_members
        WHERE library_id = lib_id
        AND user_id = get_user_id_from_auth()
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Function to check if user can edit a library (owner or editor)
CREATE OR REPLACE FUNCTION can_edit_library(lib_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM library_members
        WHERE library_id = lib_id
        AND user_id = get_user_id_from_auth()
        AND role IN ('owner', 'editor')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Function to check if user is library owner
CREATE OR REPLACE FUNCTION is_library_owner(lib_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM library_members
        WHERE library_id = lib_id
        AND user_id = get_user_id_from_auth()
        AND role = 'owner'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================================
-- ADDITIONAL USER POLICIES FOR CONSUMER APP
-- ============================================================================
-- The admin app has its own user policies. We add consumer-specific ones.

-- Allow users to view their profile via auth_user_id
DROP POLICY IF EXISTS "Consumer users can view own profile" ON users;
CREATE POLICY "Consumer users can view own profile"
    ON users FOR SELECT
    USING (auth_user_id = auth.uid());

-- Allow users to update their profile via auth_user_id
DROP POLICY IF EXISTS "Consumer users can update own profile" ON users;
CREATE POLICY "Consumer users can update own profile"
    ON users FOR UPDATE
    USING (auth_user_id = auth.uid());

-- Allow users to see other users they share a library with
DROP POLICY IF EXISTS "Users can view library co-members" ON users;
CREATE POLICY "Users can view library co-members"
    ON users FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM library_members lm1
            JOIN library_members lm2 ON lm1.library_id = lm2.library_id
            WHERE lm1.user_id = get_user_id_from_auth()
            AND lm2.user_id = users.id
        )
    );

-- ============================================================================
-- LIBRARIES POLICIES
-- ============================================================================
DROP POLICY IF EXISTS "Users can view libraries they are members of" ON libraries;
CREATE POLICY "Users can view libraries they are members of"
    ON libraries FOR SELECT
    USING (is_library_member(id));

DROP POLICY IF EXISTS "Users can create libraries" ON libraries;
CREATE POLICY "Users can create libraries"
    ON libraries FOR INSERT
    WITH CHECK (get_user_id_from_auth() = created_by);

DROP POLICY IF EXISTS "Library owners can update libraries" ON libraries;
CREATE POLICY "Library owners can update libraries"
    ON libraries FOR UPDATE
    USING (is_library_owner(id));

DROP POLICY IF EXISTS "Library owners can delete libraries" ON libraries;
CREATE POLICY "Library owners can delete libraries"
    ON libraries FOR DELETE
    USING (is_library_owner(id));

-- ============================================================================
-- LIBRARY_MEMBERS POLICIES
-- ============================================================================
DROP POLICY IF EXISTS "Users can view members of their libraries" ON library_members;
CREATE POLICY "Users can view members of their libraries"
    ON library_members FOR SELECT
    USING (is_library_member(library_id));

DROP POLICY IF EXISTS "Library owners can manage members" ON library_members;
CREATE POLICY "Library owners can manage members"
    ON library_members FOR INSERT
    WITH CHECK (is_library_owner(library_id));

DROP POLICY IF EXISTS "Library owners can update member roles" ON library_members;
CREATE POLICY "Library owners can update member roles"
    ON library_members FOR UPDATE
    USING (is_library_owner(library_id));

DROP POLICY IF EXISTS "Library owners can remove members" ON library_members;
CREATE POLICY "Library owners can remove members"
    ON library_members FOR DELETE
    USING (is_library_owner(library_id));

-- Allow users to leave libraries (delete own membership)
DROP POLICY IF EXISTS "Users can leave libraries" ON library_members;
CREATE POLICY "Users can leave libraries"
    ON library_members FOR DELETE
    USING (user_id = get_user_id_from_auth() AND role != 'owner');

-- ============================================================================
-- ALBUMS POLICIES (Canonical - shared across libraries)
-- ============================================================================
-- Albums are readable by any authenticated user
DROP POLICY IF EXISTS "Authenticated users can view albums" ON albums;
CREATE POLICY "Authenticated users can view albums"
    ON albums FOR SELECT
    USING (auth.role() = 'authenticated');

-- Albums can be created by authenticated users
DROP POLICY IF EXISTS "Authenticated users can create albums" ON albums;
CREATE POLICY "Authenticated users can create albums"
    ON albums FOR INSERT
    WITH CHECK (auth.role() = 'authenticated');

-- Albums can be updated by authenticated users (for metadata corrections)
DROP POLICY IF EXISTS "Authenticated users can update albums" ON albums;
CREATE POLICY "Authenticated users can update albums"
    ON albums FOR UPDATE
    USING (auth.role() = 'authenticated');

-- ============================================================================
-- LIBRARY_ALBUMS POLICIES
-- ============================================================================
DROP POLICY IF EXISTS "Users can view albums in their libraries" ON library_albums;
CREATE POLICY "Users can view albums in their libraries"
    ON library_albums FOR SELECT
    USING (is_library_member(library_id));

DROP POLICY IF EXISTS "Editors can add albums to libraries" ON library_albums;
CREATE POLICY "Editors can add albums to libraries"
    ON library_albums FOR INSERT
    WITH CHECK (can_edit_library(library_id) AND get_user_id_from_auth() = added_by);

DROP POLICY IF EXISTS "Editors can update library albums" ON library_albums;
CREATE POLICY "Editors can update library albums"
    ON library_albums FOR UPDATE
    USING (can_edit_library(library_id));

DROP POLICY IF EXISTS "Editors can remove albums from libraries" ON library_albums;
CREATE POLICY "Editors can remove albums from libraries"
    ON library_albums FOR DELETE
    USING (can_edit_library(library_id));

-- ============================================================================
-- RFID_TAGS POLICIES (Additional consumer policies)
-- ============================================================================
-- The admin app has its own policies. We add policies for the new consumer columns.

-- Allow users to view tags associated with their library albums
DROP POLICY IF EXISTS "Users can view tags for their library albums" ON rfid_tags;
CREATE POLICY "Users can view tags for their library albums"
    ON rfid_tags FOR SELECT
    USING (
        library_album_id IS NULL
        OR EXISTS (
            SELECT 1 FROM library_albums la
            WHERE la.id = rfid_tags.library_album_id
            AND is_library_member(la.library_id)
        )
    );

-- Editors can associate tags with albums in their libraries
DROP POLICY IF EXISTS "Editors can update tags for association" ON rfid_tags;
CREATE POLICY "Editors can update tags for association"
    ON rfid_tags FOR UPDATE
    USING (
        -- Can update if currently unassociated
        library_album_id IS NULL
        -- Or if associated with an album in a library they can edit
        OR EXISTS (
            SELECT 1 FROM library_albums la
            WHERE la.id = rfid_tags.library_album_id
            AND can_edit_library(la.library_id)
        )
    );

-- ============================================================================
-- CONSUMER_DEVICES POLICIES
-- ============================================================================
DROP POLICY IF EXISTS "Users can view own devices" ON consumer_devices;
CREATE POLICY "Users can view own devices"
    ON consumer_devices FOR SELECT
    USING (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can create own devices" ON consumer_devices;
CREATE POLICY "Users can create own devices"
    ON consumer_devices FOR INSERT
    WITH CHECK (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can update own devices" ON consumer_devices;
CREATE POLICY "Users can update own devices"
    ON consumer_devices FOR UPDATE
    USING (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can delete own devices" ON consumer_devices;
CREATE POLICY "Users can delete own devices"
    ON consumer_devices FOR DELETE
    USING (user_id = get_user_id_from_auth());

-- ============================================================================
-- LISTENING_HISTORY POLICIES
-- ============================================================================
DROP POLICY IF EXISTS "Users can view own listening history" ON listening_history;
CREATE POLICY "Users can view own listening history"
    ON listening_history FOR SELECT
    USING (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can create own listening history" ON listening_history;
CREATE POLICY "Users can create own listening history"
    ON listening_history FOR INSERT
    WITH CHECK (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can update own listening history" ON listening_history;
CREATE POLICY "Users can update own listening history"
    ON listening_history FOR UPDATE
    USING (user_id = get_user_id_from_auth());

-- ============================================================================
-- ALBUM_LOCATIONS POLICIES
-- ============================================================================
-- Users can view locations for albums in their libraries
DROP POLICY IF EXISTS "Users can view album locations" ON album_locations;
CREATE POLICY "Users can view album locations"
    ON album_locations FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM library_albums la
            WHERE la.id = album_locations.library_album_id
            AND is_library_member(la.library_id)
        )
    );

-- Device owners can insert/update locations
DROP POLICY IF EXISTS "Device owners can create album locations" ON album_locations;
CREATE POLICY "Device owners can create album locations"
    ON album_locations FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM consumer_devices d
            WHERE d.id = device_id
            AND d.user_id = get_user_id_from_auth()
        )
    );

DROP POLICY IF EXISTS "Device owners can update album locations" ON album_locations;
CREATE POLICY "Device owners can update album locations"
    ON album_locations FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM consumer_devices d
            WHERE d.id = album_locations.device_id
            AND d.user_id = get_user_id_from_auth()
        )
    );
