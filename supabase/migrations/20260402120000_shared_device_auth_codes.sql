-- ============================================================================
-- Migration: 20260402120000_shared_device_auth_codes.sql
-- Project: shared
-- Description: Creates device_auth_codes table for TV/device pairing flow
-- Date: 2026-04-02
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Device code authentication table.
-- Stores short-lived codes that allow devices (like Apple TV) to authenticate
-- by displaying a code the user enters on their phone or computer.
CREATE TABLE IF NOT EXISTS device_auth_codes (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    device_code     text NOT NULL UNIQUE,
    user_code       text NOT NULL UNIQUE,
    auth_user_id    uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    access_token    text,
    refresh_token   text,
    status          text NOT NULL DEFAULT 'pending',
    expires_at      timestamptz NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT valid_status CHECK (status IN ('pending', 'claimed', 'expired'))
);

-- Fast lookup of pending codes by device_code (used during polling)
CREATE INDEX IF NOT EXISTS idx_device_auth_codes_device_code
    ON device_auth_codes (device_code) WHERE status = 'pending';

-- Fast lookup by user_code (used during claim)
CREATE INDEX IF NOT EXISTS idx_device_auth_codes_user_code
    ON device_auth_codes (user_code) WHERE status = 'pending';

-- Cleanup index for expired codes
CREATE INDEX IF NOT EXISTS idx_device_auth_codes_expires_at
    ON device_auth_codes (expires_at) WHERE status = 'pending';

-- RLS: Only service role can access this table (edge functions use service role)
ALTER TABLE device_auth_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "device_auth_codes_service" ON device_auth_codes;
CREATE POLICY "device_auth_codes_service" ON device_auth_codes
    FOR ALL USING (auth.role() = 'service_role');

-- Allow anon to insert (device requesting a code is not yet authenticated)
DROP POLICY IF EXISTS "device_auth_codes_anon_insert" ON device_auth_codes;
CREATE POLICY "device_auth_codes_anon_insert" ON device_auth_codes
    FOR INSERT TO anon
    WITH CHECK (true);
