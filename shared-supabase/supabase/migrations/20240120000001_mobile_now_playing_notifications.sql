-- Migration: Create tables for Now Playing notifications infrastructure
-- This migration is idempotent - safe to run multiple times
-- Depends on: 20240101000002_create_tables.sql
--
-- This migration creates:
--   - push_notification_tokens: FCM/APNs token storage
--   - user_now_playing_notifications: User-facing realtime table
--   - notification_delivery_log: Push delivery tracking

-- ============================================================================
-- PUSH NOTIFICATION TOKENS TABLE
-- ============================================================================
-- Stores FCM/APNs tokens for each user/device pair
CREATE TABLE IF NOT EXISTS push_notification_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('ios', 'android')),
    device_identifier TEXT NOT NULL,  -- Unique per physical device
    app_version TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Ensure one token per device per user
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'push_tokens_user_device_key'
    ) THEN
        ALTER TABLE push_notification_tokens
        ADD CONSTRAINT push_tokens_user_device_key UNIQUE (user_id, device_identifier);
    END IF;
END$$;

-- Indexes for push_notification_tokens
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_active
    ON push_notification_tokens(user_id) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_push_tokens_token
    ON push_notification_tokens(token);

-- ============================================================================
-- USER NOW PLAYING NOTIFICATIONS TABLE
-- ============================================================================
-- User-facing realtime table with pre-resolved data
-- Apps subscribe to this table with user_id filter (RLS-protected)
CREATE TABLE IF NOT EXISTS user_now_playing_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_event_id UUID NOT NULL,  -- References now_playing_events.id
    unit_id TEXT NOT NULL,          -- Hub serial number (denormalized)
    epc TEXT NOT NULL,              -- Tag EPC (denormalized for debugging)
    event_type TEXT NOT NULL CHECK (event_type IN ('placed', 'removed')),

    -- Pre-resolved album data (NULL if tag not associated)
    library_album_id UUID REFERENCES library_albums(id) ON DELETE SET NULL,
    album_title TEXT,
    album_artist TEXT,
    cover_image_url TEXT,
    library_id UUID REFERENCES libraries(id) ON DELETE SET NULL,
    library_name TEXT,

    -- Device info
    device_id UUID REFERENCES consumer_devices(id) ON DELETE SET NULL,
    device_name TEXT,

    -- Timing
    event_timestamp TIMESTAMPTZ NOT NULL,  -- When hub detected
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure one notification per event per user (handles shared library case)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'user_notifications_event_user_key'
    ) THEN
        ALTER TABLE user_now_playing_notifications
        ADD CONSTRAINT user_notifications_event_user_key UNIQUE (source_event_id, user_id);
    END IF;
END$$;

-- Indexes for user_now_playing_notifications
CREATE INDEX IF NOT EXISTS idx_user_notifications_user_timestamp
    ON user_now_playing_notifications(user_id, event_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_user_notifications_recent
    ON user_now_playing_notifications(created_at DESC);

-- ============================================================================
-- NOTIFICATION DELIVERY LOG TABLE
-- ============================================================================
-- Tracks push notification delivery attempts
CREATE TABLE IF NOT EXISTS notification_delivery_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notification_type TEXT NOT NULL,  -- 'now_playing', 'flip_reminder', 'device_offline', etc.
    source_id UUID,                   -- ID of the triggering record
    token_id UUID REFERENCES push_notification_tokens(id) ON DELETE SET NULL,
    status TEXT NOT NULL CHECK (status IN ('pending', 'sent', 'failed', 'delivered')),
    error_message TEXT,
    sent_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for notification_delivery_log
CREATE INDEX IF NOT EXISTS idx_delivery_log_user_recent
    ON notification_delivery_log(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_delivery_log_source
    ON notification_delivery_log(source_id);

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE push_notification_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_now_playing_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_delivery_log ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES: PUSH NOTIFICATION TOKENS
-- ============================================================================
-- Users can only manage their own push tokens

DROP POLICY IF EXISTS "Users can view own push tokens" ON push_notification_tokens;
CREATE POLICY "Users can view own push tokens"
    ON push_notification_tokens FOR SELECT
    USING (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can insert own push tokens" ON push_notification_tokens;
CREATE POLICY "Users can insert own push tokens"
    ON push_notification_tokens FOR INSERT
    WITH CHECK (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can update own push tokens" ON push_notification_tokens;
CREATE POLICY "Users can update own push tokens"
    ON push_notification_tokens FOR UPDATE
    USING (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can delete own push tokens" ON push_notification_tokens;
CREATE POLICY "Users can delete own push tokens"
    ON push_notification_tokens FOR DELETE
    USING (user_id = get_user_id_from_auth());

-- Service role can manage all tokens (for Edge Functions)
DROP POLICY IF EXISTS "Service role can manage all push tokens" ON push_notification_tokens;
CREATE POLICY "Service role can manage all push tokens"
    ON push_notification_tokens FOR ALL
    USING (auth.role() = 'service_role');

-- ============================================================================
-- RLS POLICIES: USER NOW PLAYING NOTIFICATIONS
-- ============================================================================
-- Users can only view their own notifications
-- Service role (Edge Function) inserts notifications

DROP POLICY IF EXISTS "Users can view own now playing notifications" ON user_now_playing_notifications;
CREATE POLICY "Users can view own now playing notifications"
    ON user_now_playing_notifications FOR SELECT
    USING (user_id = get_user_id_from_auth());

-- Service role can insert notifications (from Edge Function)
DROP POLICY IF EXISTS "Service role can insert notifications" ON user_now_playing_notifications;
CREATE POLICY "Service role can insert notifications"
    ON user_now_playing_notifications FOR INSERT
    WITH CHECK (auth.role() = 'service_role');

-- Service role can manage all notifications
DROP POLICY IF EXISTS "Service role can manage all notifications" ON user_now_playing_notifications;
CREATE POLICY "Service role can manage all notifications"
    ON user_now_playing_notifications FOR ALL
    USING (auth.role() = 'service_role');

-- ============================================================================
-- RLS POLICIES: NOTIFICATION DELIVERY LOG
-- ============================================================================

DROP POLICY IF EXISTS "Users can view own delivery log" ON notification_delivery_log;
CREATE POLICY "Users can view own delivery log"
    ON notification_delivery_log FOR SELECT
    USING (user_id = get_user_id_from_auth());

-- Service role can manage delivery logs
DROP POLICY IF EXISTS "Service role can manage delivery logs" ON notification_delivery_log;
CREATE POLICY "Service role can manage delivery logs"
    ON notification_delivery_log FOR ALL
    USING (auth.role() = 'service_role');

-- ============================================================================
-- ENABLE REALTIME FOR USER NOTIFICATIONS TABLE
-- ============================================================================
-- This enables Supabase Realtime to broadcast changes to this table
DO $$
BEGIN
    -- Check if the publication exists and alter it
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        -- Add the table to the publication if not already added
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
            WHERE pubname = 'supabase_realtime'
            AND tablename = 'user_now_playing_notifications'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE user_now_playing_notifications;
            RAISE NOTICE 'Added user_now_playing_notifications to supabase_realtime publication';
        END IF;
    END IF;
END$$;

-- ============================================================================
-- CLEANUP FUNCTION: Remove old notifications
-- ============================================================================
-- Notifications older than 24 hours can be cleaned up
-- This can be called periodically via pg_cron or manually
CREATE OR REPLACE FUNCTION cleanup_old_notifications()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM user_now_playing_notifications
    WHERE created_at < NOW() - INTERVAL '24 hours';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to service role
GRANT EXECUTE ON FUNCTION cleanup_old_notifications() TO service_role;
