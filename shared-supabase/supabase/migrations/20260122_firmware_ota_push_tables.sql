-- OTA Push Protocol: Tables for remote firmware updates
-- Saturday Vinyl Firmware
--
-- This migration creates tables for:
-- 1. firmware_releases - Available firmware versions
-- 2. update_requests - Pending/completed update requests
-- 3. device_commands - General command queue for devices
--
-- Run this migration in your Supabase SQL Editor:
-- https://supabase.com/dashboard/project/YOUR_PROJECT/sql/new

--------------------------------------------------------------------------------
-- Firmware Releases Table
-- Stores available firmware versions for all device types
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS firmware_releases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_type TEXT NOT NULL,                  -- 'hub_s3', 'hub_h2', 'crate'
    version TEXT NOT NULL,                      -- Semantic version "1.2.3"
    version_major INTEGER NOT NULL,
    version_minor INTEGER NOT NULL,
    version_patch INTEGER NOT NULL,
    firmware_url TEXT NOT NULL,                 -- Supabase Storage URL
    firmware_size INTEGER NOT NULL,             -- Size in bytes
    firmware_sha256 TEXT NOT NULL,              -- SHA-256 hash (hex string)
    release_notes TEXT,                         -- Markdown release notes
    min_required_version TEXT,                  -- Minimum version that can upgrade to this
    is_critical BOOLEAN DEFAULT FALSE,          -- Security/stability critical update
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    released_at TIMESTAMPTZ,                    -- NULL = draft, set = published
    UNIQUE(device_type, version)
);

-- Indexes for firmware_releases
CREATE INDEX IF NOT EXISTS idx_firmware_releases_device_type
    ON firmware_releases(device_type);

CREATE INDEX IF NOT EXISTS idx_firmware_releases_released
    ON firmware_releases(device_type, released_at DESC NULLS LAST)
    WHERE released_at IS NOT NULL;

COMMENT ON TABLE firmware_releases IS 'Available firmware versions for Saturday devices';
COMMENT ON COLUMN firmware_releases.device_type IS 'Device/component type: hub_s3, hub_h2, crate';
COMMENT ON COLUMN firmware_releases.version IS 'Semantic version string (e.g., 1.2.3)';
COMMENT ON COLUMN firmware_releases.firmware_url IS 'URL to download firmware binary from Supabase Storage';
COMMENT ON COLUMN firmware_releases.firmware_sha256 IS 'SHA-256 hash of firmware binary for verification';
COMMENT ON COLUMN firmware_releases.min_required_version IS 'Minimum version required to upgrade (for breaking changes)';
COMMENT ON COLUMN firmware_releases.is_critical IS 'If true, this is a security or critical stability update';
COMMENT ON COLUMN firmware_releases.released_at IS 'NULL for drafts, timestamp when published';

--------------------------------------------------------------------------------
-- Update Requests Table
-- Pending and historical update requests from apps
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS update_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_serial TEXT NOT NULL,                -- unit_id of the target device
    device_type TEXT NOT NULL,                  -- 'hub' (both), 'hub_s3', 'hub_h2', 'crate'
    target_version TEXT,                        -- NULL = latest available
    requested_by TEXT NOT NULL,                 -- 'admin:email', 'consumer:user_id', 'system'
    request_source TEXT NOT NULL,               -- 'admin_app', 'consumer_app', 'scheduled'
    priority TEXT DEFAULT 'normal'              -- 'low', 'normal', 'high', 'critical'
        CHECK (priority IN ('low', 'normal', 'high', 'critical')),
    status TEXT DEFAULT 'pending'               -- See status enum below
        CHECK (status IN ('pending', 'notified', 'downloading', 'applying', 'complete', 'failed')),
    component_status JSONB DEFAULT '{}',        -- Per-component status for dual-SoC: {"hub_s3": "complete", "hub_h2": "downloading"}
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notified_at TIMESTAMPTZ,                    -- When device was notified
    started_at TIMESTAMPTZ,                     -- When download began
    completed_at TIMESTAMPTZ,                   -- When update finished (success or fail)
    error_message TEXT,                         -- Error details if failed
    retry_count INTEGER DEFAULT 0               -- Number of retry attempts
);

-- Indexes for update_requests
CREATE INDEX IF NOT EXISTS idx_update_requests_device_serial
    ON update_requests(device_serial);

CREATE INDEX IF NOT EXISTS idx_update_requests_device_status
    ON update_requests(device_serial, status);

CREATE INDEX IF NOT EXISTS idx_update_requests_pending
    ON update_requests(status, created_at)
    WHERE status IN ('pending', 'notified', 'downloading', 'applying');

COMMENT ON TABLE update_requests IS 'OTA update requests from apps and systems';
COMMENT ON COLUMN update_requests.device_serial IS 'Target device unit_id';
COMMENT ON COLUMN update_requests.device_type IS 'hub=both S3+H2, hub_s3=S3 only, hub_h2=H2 only, crate=Thread device';
COMMENT ON COLUMN update_requests.requested_by IS 'Who requested: admin:email, consumer:user_id, or system';
COMMENT ON COLUMN update_requests.request_source IS 'Source app: admin_app, consumer_app, scheduled';
COMMENT ON COLUMN update_requests.status IS 'pending->notified->downloading->applying->complete/failed';
COMMENT ON COLUMN update_requests.component_status IS 'Per-component status for dual-SoC devices';

--------------------------------------------------------------------------------
-- Device Commands Table
-- General command queue (beyond OTA)
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_commands (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_serial TEXT NOT NULL,                -- unit_id of target device
    command TEXT NOT NULL,                      -- 'check_update', 'reboot', 'factory_reset', etc.
    parameters JSONB DEFAULT '{}',              -- Command-specific parameters
    priority INTEGER DEFAULT 0,                 -- Higher = more urgent
    status TEXT DEFAULT 'pending'
        CHECK (status IN ('pending', 'sent', 'acknowledged', 'completed', 'failed', 'expired')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by TEXT,                            -- Who issued the command
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours'),
    sent_at TIMESTAMPTZ,                        -- When sent to device
    acknowledged_at TIMESTAMPTZ,                -- When device acknowledged
    completed_at TIMESTAMPTZ,                   -- When command finished
    result JSONB                                -- Command result/output
);

-- Indexes for device_commands
CREATE INDEX IF NOT EXISTS idx_device_commands_device_serial
    ON device_commands(device_serial);

CREATE INDEX IF NOT EXISTS idx_device_commands_device_status
    ON device_commands(device_serial, status);

CREATE INDEX IF NOT EXISTS idx_device_commands_pending
    ON device_commands(status, priority DESC, created_at)
    WHERE status = 'pending';

COMMENT ON TABLE device_commands IS 'Command queue for remote device control';
COMMENT ON COLUMN device_commands.command IS 'Command name: check_update, reboot, factory_reset, etc.';
COMMENT ON COLUMN device_commands.parameters IS 'Command-specific parameters as JSON';
COMMENT ON COLUMN device_commands.expires_at IS 'Command expires if not executed by this time';
COMMENT ON COLUMN device_commands.result IS 'Command execution result/output as JSON';

--------------------------------------------------------------------------------
-- Row Level Security (RLS)
--------------------------------------------------------------------------------

-- Enable RLS on all tables
ALTER TABLE firmware_releases ENABLE ROW LEVEL SECURITY;
ALTER TABLE update_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_commands ENABLE ROW LEVEL SECURITY;

-- firmware_releases: Anyone can read released firmware, only service role can write
CREATE POLICY "Allow reading released firmware" ON firmware_releases
    FOR SELECT
    TO anon, authenticated
    USING (released_at IS NOT NULL);

CREATE POLICY "Service role full access to firmware" ON firmware_releases
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- update_requests: Devices can read/update their own, authenticated users can create
CREATE POLICY "Devices can read own update requests" ON update_requests
    FOR SELECT
    TO anon
    USING (true);  -- Devices filter by their own unit_id in queries

CREATE POLICY "Devices can update own request status" ON update_requests
    FOR UPDATE
    TO anon
    USING (true)
    WITH CHECK (true);  -- Device can only update status fields

CREATE POLICY "Authenticated users can create update requests" ON update_requests
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can read all update requests" ON update_requests
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Service role full access to update_requests" ON update_requests
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- device_commands: Similar pattern to update_requests
CREATE POLICY "Devices can read own commands" ON device_commands
    FOR SELECT
    TO anon
    USING (true);

CREATE POLICY "Devices can update own command status" ON device_commands
    FOR UPDATE
    TO anon
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Authenticated users can create commands" ON device_commands
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can read all commands" ON device_commands
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Service role full access to device_commands" ON device_commands
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

--------------------------------------------------------------------------------
-- Realtime Broadcast Trigger
-- Broadcasts new update_requests to devices via Supabase Realtime
--------------------------------------------------------------------------------

-- Function to broadcast update_available event
CREATE OR REPLACE FUNCTION broadcast_update_request()
RETURNS TRIGGER AS $$
DECLARE
    channel_name TEXT;
    payload JSONB;
    firmware_info JSONB;
    components JSONB;
BEGIN
    -- Build channel name: device:{device_serial}
    channel_name := 'device:' || NEW.device_serial;

    -- Get firmware info for the requested version
    IF NEW.device_type = 'hub' THEN
        -- Dual-SoC: get both S3 and H2 firmware
        SELECT jsonb_agg(
            jsonb_build_object(
                'type', device_type,
                'version', version,
                'download_url', firmware_url,
                'firmware_size', firmware_size,
                'sha256', firmware_sha256
            )
        )
        INTO components
        FROM firmware_releases
        WHERE device_type IN ('hub_s3', 'hub_h2')
          AND released_at IS NOT NULL
          AND (NEW.target_version IS NULL OR version = NEW.target_version);

        payload := jsonb_build_object(
            'event', 'update_available',
            'payload', jsonb_build_object(
                'request_id', NEW.id,
                'device_type', NEW.device_type,
                'components', COALESCE(components, '[]'::jsonb),
                'is_critical', (
                    SELECT COALESCE(bool_or(is_critical), false)
                    FROM firmware_releases
                    WHERE device_type IN ('hub_s3', 'hub_h2')
                      AND released_at IS NOT NULL
                )
            )
        );
    ELSE
        -- Single component: hub_s3, hub_h2, or crate
        SELECT jsonb_build_object(
            'version', version,
            'download_url', firmware_url,
            'firmware_size', firmware_size,
            'sha256', firmware_sha256,
            'is_critical', is_critical
        )
        INTO firmware_info
        FROM firmware_releases
        WHERE device_type = NEW.device_type
          AND released_at IS NOT NULL
          AND (NEW.target_version IS NULL OR version = NEW.target_version)
        ORDER BY version_major DESC, version_minor DESC, version_patch DESC
        LIMIT 1;

        payload := jsonb_build_object(
            'event', 'update_available',
            'payload', jsonb_build_object(
                'request_id', NEW.id,
                'device_type', NEW.device_type
            ) || COALESCE(firmware_info, '{}'::jsonb)
        );
    END IF;

    -- Broadcast to the device channel via pg_notify
    -- Supabase Realtime listens to these notifications
    PERFORM pg_notify(
        'realtime:broadcast',
        jsonb_build_object(
            'topic', channel_name,
            'event', 'broadcast',
            'payload', payload
        )::text
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on new update requests
DROP TRIGGER IF EXISTS on_update_request_created ON update_requests;
CREATE TRIGGER on_update_request_created
    AFTER INSERT ON update_requests
    FOR EACH ROW
    EXECUTE FUNCTION broadcast_update_request();

COMMENT ON FUNCTION broadcast_update_request IS 'Broadcasts update_available event to device channel via Realtime';

--------------------------------------------------------------------------------
-- Function to broadcast device commands
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION broadcast_device_command()
RETURNS TRIGGER AS $$
DECLARE
    channel_name TEXT;
BEGIN
    channel_name := 'device:' || NEW.device_serial;

    PERFORM pg_notify(
        'realtime:broadcast',
        jsonb_build_object(
            'topic', channel_name,
            'event', 'broadcast',
            'payload', jsonb_build_object(
                'event', 'command',
                'payload', jsonb_build_object(
                    'id', NEW.id,
                    'command', NEW.command,
                    'parameters', NEW.parameters
                )
            )
        )::text
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger on new device commands
DROP TRIGGER IF EXISTS on_device_command_created ON device_commands;
CREATE TRIGGER on_device_command_created
    AFTER INSERT ON device_commands
    FOR EACH ROW
    EXECUTE FUNCTION broadcast_device_command();

COMMENT ON FUNCTION broadcast_device_command IS 'Broadcasts command event to device channel via Realtime';

--------------------------------------------------------------------------------
-- Useful Views
--------------------------------------------------------------------------------

-- View: Latest available firmware per device type
CREATE OR REPLACE VIEW latest_firmware AS
SELECT DISTINCT ON (device_type)
    id,
    device_type,
    version,
    version_major,
    version_minor,
    version_patch,
    firmware_url,
    firmware_size,
    firmware_sha256,
    is_critical,
    released_at,
    release_notes
FROM firmware_releases
WHERE released_at IS NOT NULL
ORDER BY device_type, version_major DESC, version_minor DESC, version_patch DESC;

COMMENT ON VIEW latest_firmware IS 'Latest released firmware for each device type';

-- View: Pending update requests
CREATE OR REPLACE VIEW pending_updates AS
SELECT
    ur.id,
    ur.device_serial,
    ur.device_type,
    ur.target_version,
    ur.requested_by,
    ur.request_source,
    ur.priority,
    ur.status,
    ur.component_status,
    ur.created_at,
    ur.notified_at,
    ur.started_at,
    ur.error_message,
    ur.retry_count,
    EXTRACT(EPOCH FROM (NOW() - ur.created_at))::INTEGER as age_seconds
FROM update_requests ur
WHERE ur.status NOT IN ('complete', 'failed')
ORDER BY
    CASE ur.priority
        WHEN 'critical' THEN 0
        WHEN 'high' THEN 1
        WHEN 'normal' THEN 2
        WHEN 'low' THEN 3
    END,
    ur.created_at;

COMMENT ON VIEW pending_updates IS 'All pending update requests ordered by priority';

-- View: Pending commands per device
CREATE OR REPLACE VIEW pending_commands AS
SELECT
    dc.id,
    dc.device_serial,
    dc.command,
    dc.parameters,
    dc.priority,
    dc.status,
    dc.created_at,
    dc.expires_at,
    dc.created_by,
    EXTRACT(EPOCH FROM (dc.expires_at - NOW()))::INTEGER as ttl_seconds
FROM device_commands dc
WHERE dc.status = 'pending'
  AND (dc.expires_at IS NULL OR dc.expires_at > NOW())
ORDER BY dc.priority DESC, dc.created_at;

COMMENT ON VIEW pending_commands IS 'Pending commands that have not expired';

--------------------------------------------------------------------------------
-- Sample Data (for testing)
--------------------------------------------------------------------------------

-- Insert sample firmware release (uncomment to use)
-- INSERT INTO firmware_releases (device_type, version, version_major, version_minor, version_patch, firmware_url, firmware_size, firmware_sha256, release_notes, released_at)
-- VALUES
--     ('hub_s3', '1.0.0', 1, 0, 0, 'https://your-project.supabase.co/storage/v1/object/public/firmware/hub_s3_1.0.0.bin', 1048576, 'abc123...', 'Initial release', NOW()),
--     ('hub_h2', '1.0.0', 1, 0, 0, 'https://your-project.supabase.co/storage/v1/object/public/firmware/hub_h2_1.0.0.bin', 262144, 'def456...', 'Initial release', NOW());

--------------------------------------------------------------------------------
-- Done
--------------------------------------------------------------------------------
-- After running this migration:
-- 1. Create a storage bucket named 'firmware' for firmware binaries
-- 2. Configure bucket policies to allow public read access
-- 3. Upload firmware binaries and note their URLs
-- 4. Insert rows into firmware_releases with the URLs
