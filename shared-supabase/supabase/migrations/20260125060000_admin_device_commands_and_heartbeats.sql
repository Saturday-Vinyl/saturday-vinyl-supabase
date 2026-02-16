-- ============================================================================
-- Migration: 20260125060000_device_commands_and_heartbeats.sql
-- Description: Create device_commands and device_heartbeats tables for device communication
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Device commands table - handles ALL device commands including OTA updates
-- Commands target individual devices by MAC address
-- Supported commands: factory_provision, run_test, reboot, consumer_reset,
-- factory_reset, get_status, set_factory_attributes, set_consumer_attributes, ota_update
CREATE TABLE IF NOT EXISTS device_commands (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Target device by MAC address
  mac_address VARCHAR(17) NOT NULL,

  -- Command type
  command TEXT NOT NULL,

  -- Optional: which capability this command relates to
  capability TEXT,

  -- Optional: for run_test commands
  test_name TEXT,

  -- Command parameters as JSON
  parameters JSONB DEFAULT '{}',

  -- Priority: higher = more urgent
  priority INTEGER DEFAULT 0,

  -- Command lifecycle status
  -- pending: awaiting device
  -- sent: broadcast to device
  -- acknowledged: device received
  -- completed: device finished successfully
  -- failed: device reported failure
  -- expired: command timed out
  status TEXT DEFAULT 'pending',

  -- Optional expiration for time-sensitive commands
  expires_at TIMESTAMPTZ,

  -- Result from device
  result JSONB,
  error_message TEXT,

  -- Retry tracking
  retry_count INTEGER DEFAULT 0,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),

  -- Who created the command
  created_by UUID REFERENCES users(id)
);

COMMENT ON TABLE device_commands IS 'Command queue for device operations. Commands are broadcast via Supabase Realtime.';

-- Indexes for device_commands
CREATE INDEX IF NOT EXISTS idx_device_commands_mac ON device_commands(mac_address);
CREATE INDEX IF NOT EXISTS idx_device_commands_status ON device_commands(status);
CREATE INDEX IF NOT EXISTS idx_device_commands_pending ON device_commands(mac_address, status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_device_commands_created ON device_commands(created_at DESC);

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_device_commands_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_device_commands_updated_at ON device_commands;
CREATE TRIGGER trigger_device_commands_updated_at
  BEFORE UPDATE ON device_commands
  FOR EACH ROW
  EXECUTE FUNCTION update_device_commands_updated_at();

-- Broadcast trigger for Supabase Realtime
-- Notifies devices via their channel: device:{mac_address}
CREATE OR REPLACE FUNCTION broadcast_device_command()
RETURNS TRIGGER AS $$
DECLARE
  channel_name TEXT;
BEGIN
  -- Replace colons with dashes for channel name
  channel_name := 'device:' || REPLACE(NEW.mac_address, ':', '-');

  -- Use Supabase Realtime broadcast
  PERFORM pg_notify(
    'realtime:broadcast',
    json_build_object(
      'topic', channel_name,
      'event', 'broadcast',
      'payload', json_build_object(
        'event', 'command',
        'payload', json_build_object(
          'id', NEW.id,
          'command', NEW.command,
          'capability', NEW.capability,
          'test_name', NEW.test_name,
          'parameters', NEW.parameters
        )
      )
    )::text
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS on_device_command_created ON device_commands;
CREATE TRIGGER on_device_command_created
  AFTER INSERT ON device_commands
  FOR EACH ROW
  WHEN (NEW.status = 'pending')
  EXECUTE FUNCTION broadcast_device_command();

-- Device heartbeats table for status monitoring
-- Heartbeats come from individual devices (by MAC address)
CREATE TABLE IF NOT EXISTS device_heartbeats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Device identifier
  mac_address VARCHAR(17) NOT NULL,

  -- Firmware version at heartbeat time
  firmware_version TEXT,

  -- Capability-scoped telemetry data
  heartbeat_data JSONB DEFAULT '{}',

  -- When heartbeat was received
  received_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE device_heartbeats IS 'Device status heartbeats with telemetry data. Retained for 24 hours.';

-- Indexes for heartbeats (only create if required columns exist)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'mac_address'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'received_at'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_heartbeats_mac_recent
    ON device_heartbeats(mac_address, received_at DESC);
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'received_at'
  ) THEN
    CREATE INDEX IF NOT EXISTS idx_heartbeats_received
    ON device_heartbeats(received_at DESC);
  END IF;
END $$;

-- Trigger to update device.last_seen_at on heartbeat
-- Only create if mac_address column exists in device_heartbeats
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'mac_address'
  ) THEN
    -- Create the trigger function
    CREATE OR REPLACE FUNCTION update_device_last_seen()
    RETURNS TRIGGER AS $func$
    BEGIN
      UPDATE devices
      SET
        last_seen_at = NEW.received_at,
        firmware_version = COALESCE(NEW.firmware_version, firmware_version)
      WHERE mac_address = NEW.mac_address;

      RETURN NEW;
    END;
    $func$ LANGUAGE plpgsql;

    DROP TRIGGER IF EXISTS on_heartbeat_received ON device_heartbeats;
    CREATE TRIGGER on_heartbeat_received
      AFTER INSERT ON device_heartbeats
      FOR EACH ROW
      EXECUTE FUNCTION update_device_last_seen();
  END IF;
END $$;

-- Row Level Security for device_commands
ALTER TABLE device_commands ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read device_commands" ON device_commands;
DROP POLICY IF EXISTS "Employees can create device_commands" ON device_commands;
DROP POLICY IF EXISTS "Devices can update their commands" ON device_commands;

CREATE POLICY "Authenticated users can read device_commands"
ON device_commands FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Employees can create device_commands"
ON device_commands FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    WHERE u.id = auth.uid() AND u.is_active = true
  )
);

-- Allow updates for command status (from devices via anon key or service role)
CREATE POLICY "Devices can update their commands"
ON device_commands FOR UPDATE
TO anon
USING (true)
WITH CHECK (true);

-- Row Level Security for device_heartbeats
ALTER TABLE device_heartbeats ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read device_heartbeats" ON device_heartbeats;
DROP POLICY IF EXISTS "Devices can insert heartbeats" ON device_heartbeats;

CREATE POLICY "Authenticated users can read device_heartbeats"
ON device_heartbeats FOR SELECT
TO authenticated
USING (true);

-- Allow devices to insert heartbeats (via anon key)
CREATE POLICY "Devices can insert heartbeats"
ON device_heartbeats FOR INSERT
TO anon
WITH CHECK (true);

-- Cleanup function for old heartbeats (call via pg_cron or Edge Function)
CREATE OR REPLACE FUNCTION cleanup_old_heartbeats(retention_hours INTEGER DEFAULT 24)
RETURNS INTEGER AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM device_heartbeats
  WHERE received_at < NOW() - (retention_hours || ' hours')::INTERVAL;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION cleanup_old_heartbeats IS 'Deletes heartbeats older than retention_hours. Call via pg_cron: SELECT cleanup_old_heartbeats(24);';
