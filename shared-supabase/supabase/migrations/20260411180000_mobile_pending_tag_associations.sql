-- ============================================================================
-- Migration: 20260411120000_mobile_pending_tag_associations.sql
-- Project: saturday-mobile-app
-- Description: Create pending_tag_associations table for hub-based RFID tag
--              association. The app creates a pending record, the hub scans a
--              tag (reported as a now_playing_event), and the edge function
--              fulfills the pending record with the detected EPC.
-- Date: 2026-04-11
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS pending_tag_associations (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    unit_id          TEXT NOT NULL,            -- hub serial number (e.g. SV-HUB-000001)
    library_album_id UUID NOT NULL REFERENCES library_albums(id) ON DELETE CASCADE,
    status           TEXT NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending', 'fulfilled', 'cancelled')),
    detected_epc     TEXT,                     -- filled by edge function when fulfilled
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fulfilled_at     TIMESTAMPTZ,
    cancelled_at     TIMESTAMPTZ
);

-- Only one active pending request per user per hub
CREATE UNIQUE INDEX IF NOT EXISTS idx_pending_tag_assoc_active
    ON pending_tag_associations(user_id, unit_id) WHERE status = 'pending';

-- Lookup by unit_id for edge function queries
CREATE INDEX IF NOT EXISTS idx_pending_tag_assoc_unit_status
    ON pending_tag_associations(unit_id, status);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE pending_tag_associations ENABLE ROW LEVEL SECURITY;

-- Users can view their own pending associations
DROP POLICY IF EXISTS "Users can view own pending associations" ON pending_tag_associations;
CREATE POLICY "Users can view own pending associations"
    ON pending_tag_associations FOR SELECT
    USING (user_id = get_user_id_from_auth());

-- Users can create pending associations for their own user_id
DROP POLICY IF EXISTS "Users can create pending associations" ON pending_tag_associations;
CREATE POLICY "Users can create pending associations"
    ON pending_tag_associations FOR INSERT
    WITH CHECK (user_id = get_user_id_from_auth());

-- Users can update their own pending associations (for cancellation)
DROP POLICY IF EXISTS "Users can update own pending associations" ON pending_tag_associations;
CREATE POLICY "Users can update own pending associations"
    ON pending_tag_associations FOR UPDATE
    USING (user_id = get_user_id_from_auth());

-- Service role can manage all (for edge function fulfillment)
DROP POLICY IF EXISTS "Service role can manage all pending associations" ON pending_tag_associations;
CREATE POLICY "Service role can manage all pending associations"
    ON pending_tag_associations FOR ALL
    USING (auth.role() = 'service_role');

-- ============================================================================
-- ENABLE REALTIME
-- ============================================================================
-- App subscribes to changes on this table to detect when a pending request
-- is fulfilled by the edge function.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
            AND tablename = 'pending_tag_associations'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE pending_tag_associations;
            RAISE NOTICE 'Added pending_tag_associations to supabase_realtime publication';
        END IF;
    END IF;
END$$;
