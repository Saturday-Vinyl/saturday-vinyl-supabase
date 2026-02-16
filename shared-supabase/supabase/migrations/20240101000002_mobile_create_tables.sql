-- Migration: Create/extend tables for Saturday Consumer App
-- This migration is idempotent - safe to run multiple times
-- Depends on: 20240101000001_create_enums.sql
--
-- NOTE: This migration extends the existing Saturday database:
--   - EXTENDS: users table (adds consumer-specific columns)
--   - EXTENDS: rfid_tags table (adds album association columns)
--   - CREATES: New consumer-specific tables

-- ============================================================================
-- EXTEND USERS TABLE
-- ============================================================================
-- The users table already exists from the admin app with:
--   id, google_id, email, full_name, is_admin, is_active, created_at, last_login, updated_at
--
-- For the consumer app, we need to add:
--   - avatar_url (profile picture)
--   - preferences (JSONB for app settings)
--   - auth_user_id (link to Supabase Auth for consumer auth flow)

DO $$
BEGIN
    -- Add avatar_url column if not exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'avatar_url'
    ) THEN
        ALTER TABLE users ADD COLUMN avatar_url TEXT;
        RAISE NOTICE 'Added avatar_url column to users table';
    END IF;

    -- Add preferences column if not exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'preferences'
    ) THEN
        ALTER TABLE users ADD COLUMN preferences JSONB DEFAULT '{}'::jsonb;
        RAISE NOTICE 'Added preferences column to users table';
    END IF;

    -- Add auth_user_id column if not exists (links to auth.users for consumer auth)
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'auth_user_id'
    ) THEN
        ALTER TABLE users ADD COLUMN auth_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
        RAISE NOTICE 'Added auth_user_id column to users table';
    END IF;
END$$;

-- Add index on auth_user_id if not exists
CREATE INDEX IF NOT EXISTS idx_users_auth_user_id ON users(auth_user_id);

-- ============================================================================
-- EXTEND RFID_TAGS TABLE
-- ============================================================================
-- The rfid_tags table already exists from the admin app with:
--   id, epc_identifier, tid, status, created_at, updated_at, written_at, locked_at, created_by
--
-- For the consumer app, we need to add:
--   - library_album_id (link to library_albums for album association)
--   - associated_at (when the tag was associated with an album)
--   - associated_by (who associated the tag)
--   - last_seen_at (last time the tag was detected by a device)
--
-- NOTE: Future extensibility consideration
-- Tags may eventually be associated with other entity types beyond albums, such as:
--   - production_unit components (to track installed options/features)
--   - consumer_device components (for device self-auditing)
-- When that need arises, consider either:
--   1. Adding additional nullable FK columns (e.g., production_unit_id, component_id)
--   2. Creating a polymorphic tag_associations junction table
-- For now, library_album_id is sufficient for consumer album tracking.

DO $$
BEGIN
    -- Add library_album_id column if not exists
    -- Note: We add this now but the FK constraint comes later after library_albums is created
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'rfid_tags' AND column_name = 'library_album_id'
    ) THEN
        ALTER TABLE rfid_tags ADD COLUMN library_album_id UUID;
        RAISE NOTICE 'Added library_album_id column to rfid_tags table';
    END IF;

    -- Add associated_at column if not exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'rfid_tags' AND column_name = 'associated_at'
    ) THEN
        ALTER TABLE rfid_tags ADD COLUMN associated_at TIMESTAMPTZ;
        RAISE NOTICE 'Added associated_at column to rfid_tags table';
    END IF;

    -- Add associated_by column if not exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'rfid_tags' AND column_name = 'associated_by'
    ) THEN
        ALTER TABLE rfid_tags ADD COLUMN associated_by UUID REFERENCES users(id) ON DELETE SET NULL;
        RAISE NOTICE 'Added associated_by column to rfid_tags table';
    END IF;

    -- Add last_seen_at column if not exists
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'rfid_tags' AND column_name = 'last_seen_at'
    ) THEN
        ALTER TABLE rfid_tags ADD COLUMN last_seen_at TIMESTAMPTZ;
        RAISE NOTICE 'Added last_seen_at column to rfid_tags table';
    END IF;
END$$;

-- Add indexes for new columns
CREATE INDEX IF NOT EXISTS idx_rfid_tags_library_album_id ON rfid_tags(library_album_id);
CREATE INDEX IF NOT EXISTS idx_rfid_tags_last_seen_at ON rfid_tags(last_seen_at DESC);

-- ============================================================================
-- LIBRARIES TABLE (NEW)
-- ============================================================================
-- Stores vinyl record libraries (collections)
CREATE TABLE IF NOT EXISTS libraries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE
);

-- ============================================================================
-- LIBRARY_MEMBERS TABLE (NEW)
-- ============================================================================
-- Stores library membership and roles
CREATE TABLE IF NOT EXISTS library_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role library_role NOT NULL DEFAULT 'viewer',
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    invited_by UUID REFERENCES users(id) ON DELETE SET NULL
);

-- Add unique constraint on library_id + user_id if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'library_members_library_user_key'
    ) THEN
        ALTER TABLE library_members
        ADD CONSTRAINT library_members_library_user_key UNIQUE (library_id, user_id);
    END IF;
END$$;

-- ============================================================================
-- ALBUMS TABLE (NEW - Canonical)
-- ============================================================================
-- Stores canonical album metadata from Discogs (shared across all libraries)
CREATE TABLE IF NOT EXISTS albums (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    discogs_id INTEGER,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    year INTEGER,
    genres TEXT[] DEFAULT '{}',
    styles TEXT[] DEFAULT '{}',
    label TEXT,
    cover_image_url TEXT,
    tracks JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add unique constraint on discogs_id if not exists (when not null)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'albums_discogs_id_key'
    ) THEN
        ALTER TABLE albums ADD CONSTRAINT albums_discogs_id_key UNIQUE (discogs_id);
    END IF;
END$$;

-- ============================================================================
-- LIBRARY_ALBUMS TABLE (NEW)
-- ============================================================================
-- Links albums to libraries with library-specific data
CREATE TABLE IF NOT EXISTS library_albums (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    album_id UUID NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notes TEXT,
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE
);

-- Add unique constraint on library_id + album_id if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'library_albums_library_album_key'
    ) THEN
        ALTER TABLE library_albums
        ADD CONSTRAINT library_albums_library_album_key UNIQUE (library_id, album_id);
    END IF;
END$$;

-- ============================================================================
-- ADD FOREIGN KEY FROM RFID_TAGS TO LIBRARY_ALBUMS
-- ============================================================================
-- Now that library_albums exists, add the FK constraint
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'rfid_tags_library_album_id_fkey'
    ) THEN
        ALTER TABLE rfid_tags
        ADD CONSTRAINT rfid_tags_library_album_id_fkey
        FOREIGN KEY (library_album_id) REFERENCES library_albums(id) ON DELETE SET NULL;
        RAISE NOTICE 'Added foreign key from rfid_tags to library_albums';
    END IF;
END$$;

-- ============================================================================
-- CONSUMER_DEVICES TABLE (NEW)
-- ============================================================================
-- Stores Saturday hardware devices owned by consumers (hubs and crates)
-- Note: This is separate from production_units which tracks manufacturing
CREATE TABLE IF NOT EXISTS consumer_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_type consumer_device_type NOT NULL,
    name TEXT NOT NULL,
    serial_number TEXT NOT NULL,
    production_unit_id UUID, -- Link to production_units if applicable
    firmware_version TEXT,
    status consumer_device_status NOT NULL DEFAULT 'offline',
    battery_level INTEGER CHECK (battery_level >= 0 AND battery_level <= 100),
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    settings JSONB DEFAULT '{}'::jsonb
);

-- Add unique constraint on serial_number if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'consumer_devices_serial_number_key'
    ) THEN
        ALTER TABLE consumer_devices ADD CONSTRAINT consumer_devices_serial_number_key UNIQUE (serial_number);
    END IF;
END$$;

-- Add FK to production_units if that table exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables WHERE table_name = 'production_units'
    ) AND NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'consumer_devices_production_unit_id_fkey'
    ) THEN
        ALTER TABLE consumer_devices
        ADD CONSTRAINT consumer_devices_production_unit_id_fkey
        FOREIGN KEY (production_unit_id) REFERENCES production_units(id) ON DELETE SET NULL;
        RAISE NOTICE 'Added foreign key from consumer_devices to production_units';
    END IF;
END$$;

-- ============================================================================
-- LISTENING_HISTORY TABLE (NEW)
-- ============================================================================
-- Tracks user listening history for recommendations
CREATE TABLE IF NOT EXISTS listening_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    library_album_id UUID NOT NULL REFERENCES library_albums(id) ON DELETE CASCADE,
    played_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    play_duration_seconds INTEGER,
    completed_side record_side,
    device_id UUID REFERENCES consumer_devices(id) ON DELETE SET NULL
);

-- ============================================================================
-- ALBUM_LOCATIONS TABLE (NEW)
-- ============================================================================
-- Tracks physical location of albums in crates
CREATE TABLE IF NOT EXISTS album_locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_album_id UUID NOT NULL REFERENCES library_albums(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES consumer_devices(id) ON DELETE CASCADE,
    detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    removed_at TIMESTAMPTZ
);

-- ============================================================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================================================
-- The update_updated_at_column function should already exist from admin app
-- But recreate it safely just in case
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at trigger to libraries
DROP TRIGGER IF EXISTS update_libraries_updated_at ON libraries;
CREATE TRIGGER update_libraries_updated_at
    BEFORE UPDATE ON libraries
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Apply updated_at trigger to albums
DROP TRIGGER IF EXISTS update_albums_updated_at ON albums;
CREATE TRIGGER update_albums_updated_at
    BEFORE UPDATE ON albums
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();
