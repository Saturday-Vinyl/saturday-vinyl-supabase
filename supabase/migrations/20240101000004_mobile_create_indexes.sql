-- Migration: Create indexes for Saturday Consumer App
-- This migration is idempotent - safe to run multiple times
-- Depends on: 20240101000002_create_tables.sql
--
-- NOTE: users and rfid_tags already have indexes from admin app.
-- We only add new indexes for new columns and new tables.

-- ============================================================================
-- USERS INDEXES (New columns only)
-- ============================================================================
-- idx_users_email and idx_users_google_id already exist from admin app
CREATE INDEX IF NOT EXISTS idx_users_auth_user_id ON users(auth_user_id);

-- ============================================================================
-- LIBRARIES INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_libraries_created_by ON libraries(created_by);
CREATE INDEX IF NOT EXISTS idx_libraries_created_at ON libraries(created_at);
CREATE INDEX IF NOT EXISTS idx_libraries_name ON libraries(name);

-- ============================================================================
-- LIBRARY_MEMBERS INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_library_members_library_id ON library_members(library_id);
CREATE INDEX IF NOT EXISTS idx_library_members_user_id ON library_members(user_id);
CREATE INDEX IF NOT EXISTS idx_library_members_role ON library_members(role);

-- ============================================================================
-- ALBUMS INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_albums_discogs_id ON albums(discogs_id);
CREATE INDEX IF NOT EXISTS idx_albums_title ON albums(title);
CREATE INDEX IF NOT EXISTS idx_albums_artist ON albums(artist);
CREATE INDEX IF NOT EXISTS idx_albums_year ON albums(year);
CREATE INDEX IF NOT EXISTS idx_albums_created_at ON albums(created_at);

-- Full text search index for album search
CREATE INDEX IF NOT EXISTS idx_albums_search ON albums
    USING gin(to_tsvector('english', title || ' ' || artist || ' ' || COALESCE(label, '')));

-- GIN index for genre/style arrays
CREATE INDEX IF NOT EXISTS idx_albums_genres ON albums USING gin(genres);
CREATE INDEX IF NOT EXISTS idx_albums_styles ON albums USING gin(styles);

-- ============================================================================
-- LIBRARY_ALBUMS INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_library_albums_library_id ON library_albums(library_id);
CREATE INDEX IF NOT EXISTS idx_library_albums_album_id ON library_albums(album_id);
CREATE INDEX IF NOT EXISTS idx_library_albums_added_by ON library_albums(added_by);
CREATE INDEX IF NOT EXISTS idx_library_albums_added_at ON library_albums(added_at DESC);
CREATE INDEX IF NOT EXISTS idx_library_albums_is_favorite ON library_albums(is_favorite) WHERE is_favorite = true;

-- ============================================================================
-- RFID_TAGS INDEXES (New columns only)
-- ============================================================================
-- idx_rfid_tags_epc and idx_rfid_tags_status already exist from admin app
CREATE INDEX IF NOT EXISTS idx_rfid_tags_library_album_id ON rfid_tags(library_album_id);
CREATE INDEX IF NOT EXISTS idx_rfid_tags_last_seen_at ON rfid_tags(last_seen_at DESC);

-- ============================================================================
-- CONSUMER_DEVICES INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_consumer_devices_user_id ON consumer_devices(user_id);
CREATE INDEX IF NOT EXISTS idx_consumer_devices_device_type ON consumer_devices(device_type);
CREATE INDEX IF NOT EXISTS idx_consumer_devices_serial_number ON consumer_devices(serial_number);
CREATE INDEX IF NOT EXISTS idx_consumer_devices_status ON consumer_devices(status);
CREATE INDEX IF NOT EXISTS idx_consumer_devices_last_seen_at ON consumer_devices(last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_consumer_devices_production_unit_id ON consumer_devices(production_unit_id);

-- ============================================================================
-- LISTENING_HISTORY INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_listening_history_user_id ON listening_history(user_id);
CREATE INDEX IF NOT EXISTS idx_listening_history_library_album_id ON listening_history(library_album_id);
CREATE INDEX IF NOT EXISTS idx_listening_history_played_at ON listening_history(played_at DESC);
CREATE INDEX IF NOT EXISTS idx_listening_history_device_id ON listening_history(device_id);

-- Composite index for user's recent history
CREATE INDEX IF NOT EXISTS idx_listening_history_user_recent
    ON listening_history(user_id, played_at DESC);

-- ============================================================================
-- ALBUM_LOCATIONS INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_album_locations_library_album_id ON album_locations(library_album_id);
CREATE INDEX IF NOT EXISTS idx_album_locations_device_id ON album_locations(device_id);
CREATE INDEX IF NOT EXISTS idx_album_locations_detected_at ON album_locations(detected_at DESC);

-- Index for currently present albums (removed_at IS NULL)
CREATE INDEX IF NOT EXISTS idx_album_locations_current
    ON album_locations(device_id, library_album_id)
    WHERE removed_at IS NULL;
