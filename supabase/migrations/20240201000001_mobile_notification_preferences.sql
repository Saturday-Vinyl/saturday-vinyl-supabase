-- Migration: Create tables for notification preferences and device status tracking
-- This migration is idempotent - safe to run multiple times
-- Depends on: 20240120000001_now_playing_notifications.sql
--
-- This migration creates:
--   - notification_preferences: Server-side user notification settings
--   - device_status_notifications: Tracks when device status notifications were sent

-- ============================================================================
-- NOTIFICATION PREFERENCES TABLE
-- ============================================================================
-- Stores user notification preferences server-side
-- Edge Functions check these before sending push notifications
CREATE TABLE IF NOT EXISTS notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Individual notification type toggles
    now_playing_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    flip_reminders_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    device_offline_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    device_online_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    battery_low_enabled BOOLEAN NOT NULL DEFAULT TRUE,

    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Ensure one preferences row per user
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'notification_preferences_user_unique'
    ) THEN
        ALTER TABLE notification_preferences
        ADD CONSTRAINT notification_preferences_user_unique UNIQUE (user_id);
    END IF;
END$$;

-- Indexes for notification_preferences
CREATE INDEX IF NOT EXISTS idx_notification_preferences_user
    ON notification_preferences(user_id);

-- ============================================================================
-- DEVICE STATUS NOTIFICATIONS TABLE
-- ============================================================================
-- Tracks when device status notifications were last sent
-- Used to prevent duplicate notifications and detect device recovery
CREATE TABLE IF NOT EXISTS device_status_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID NOT NULL REFERENCES consumer_devices(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Notification type: 'device_offline', 'battery_low', 'device_online'
    notification_type TEXT NOT NULL,

    -- When this notification was last sent
    last_sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Context data (JSON):
    -- For offline: {"last_seen_at": "..."}
    -- For battery_low: {"battery_level": 15}
    -- For online: {"recovered_at": "..."}
    context_data JSONB
);

-- Ensure one record per device/notification type combination
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'device_status_notifications_device_type_unique'
    ) THEN
        ALTER TABLE device_status_notifications
        ADD CONSTRAINT device_status_notifications_device_type_unique
            UNIQUE (device_id, notification_type);
    END IF;
END$$;

-- Indexes for device_status_notifications
CREATE INDEX IF NOT EXISTS idx_device_status_notifications_device
    ON device_status_notifications(device_id);
CREATE INDEX IF NOT EXISTS idx_device_status_notifications_user
    ON device_status_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_device_status_notifications_type_sent
    ON device_status_notifications(notification_type, last_sent_at DESC);

-- ============================================================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_status_notifications ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- RLS POLICIES: NOTIFICATION PREFERENCES
-- ============================================================================
-- Users can manage their own notification preferences

DROP POLICY IF EXISTS "Users can view own notification preferences" ON notification_preferences;
CREATE POLICY "Users can view own notification preferences"
    ON notification_preferences FOR SELECT
    USING (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can insert own notification preferences" ON notification_preferences;
CREATE POLICY "Users can insert own notification preferences"
    ON notification_preferences FOR INSERT
    WITH CHECK (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can update own notification preferences" ON notification_preferences;
CREATE POLICY "Users can update own notification preferences"
    ON notification_preferences FOR UPDATE
    USING (user_id = get_user_id_from_auth());

DROP POLICY IF EXISTS "Users can delete own notification preferences" ON notification_preferences;
CREATE POLICY "Users can delete own notification preferences"
    ON notification_preferences FOR DELETE
    USING (user_id = get_user_id_from_auth());

-- Service role can manage all preferences (for Edge Functions)
DROP POLICY IF EXISTS "Service role can manage all notification preferences" ON notification_preferences;
CREATE POLICY "Service role can manage all notification preferences"
    ON notification_preferences FOR ALL
    USING (auth.role() = 'service_role');

-- ============================================================================
-- RLS POLICIES: DEVICE STATUS NOTIFICATIONS
-- ============================================================================
-- Users can view their own device status notification tracking
-- Service role (Edge Functions) manages all records

DROP POLICY IF EXISTS "Users can view own device status notifications" ON device_status_notifications;
CREATE POLICY "Users can view own device status notifications"
    ON device_status_notifications FOR SELECT
    USING (user_id = get_user_id_from_auth());

-- Service role can manage all device status notifications
DROP POLICY IF EXISTS "Service role can manage device status notifications" ON device_status_notifications;
CREATE POLICY "Service role can manage device status notifications"
    ON device_status_notifications FOR ALL
    USING (auth.role() = 'service_role');

-- ============================================================================
-- TRIGGER: Update updated_at timestamp
-- ============================================================================
CREATE OR REPLACE FUNCTION update_notification_preferences_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS notification_preferences_updated_at ON notification_preferences;
CREATE TRIGGER notification_preferences_updated_at
    BEFORE UPDATE ON notification_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_notification_preferences_updated_at();
