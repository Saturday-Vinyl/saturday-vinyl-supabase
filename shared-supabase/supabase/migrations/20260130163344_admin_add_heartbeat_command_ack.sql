-- ============================================================================
-- Migration: 20260130163344_add_heartbeat_command_ack.sql
-- Description: Add type and command_id fields to device_heartbeats for command
--              acknowledgement support. Creates trigger to update device_commands
--              status when ack heartbeats are received.
-- Date: 2026-01-30
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Add type field to device_heartbeats for categorizing heartbeat types
-- Types: 'status' (regular), 'command_ack' (command acknowledged), 'command_result' (command completed/failed)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'type'
  ) THEN
    ALTER TABLE device_heartbeats ADD COLUMN type TEXT DEFAULT 'status';
  END IF;
END $$;

COMMENT ON COLUMN device_heartbeats.type IS
  'Heartbeat type: status (regular telemetry), command_ack (command acknowledged), command_result (command completed/failed)';

-- Add command_id field for linking acks to commands
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'command_id'
  ) THEN
    ALTER TABLE device_heartbeats ADD COLUMN command_id UUID REFERENCES device_commands(id);
  END IF;
END $$;

COMMENT ON COLUMN device_heartbeats.command_id IS
  'For command_ack/command_result types: links to the acknowledged command';

-- Index for efficient command ack lookups
CREATE INDEX IF NOT EXISTS idx_heartbeats_command_id ON device_heartbeats(command_id)
  WHERE command_id IS NOT NULL;

-- Index for filtering by type
CREATE INDEX IF NOT EXISTS idx_heartbeats_type ON device_heartbeats(type)
  WHERE type != 'status';

-- Trigger function to update device_commands status when ack/result heartbeats arrive
-- Uses SECURITY DEFINER to bypass RLS (device uses anon role for heartbeat inserts)
CREATE OR REPLACE FUNCTION update_command_on_ack()
RETURNS TRIGGER AS $$
BEGIN
  -- Handle command acknowledgement
  IF NEW.type = 'command_ack' AND NEW.command_id IS NOT NULL THEN
    UPDATE device_commands
    SET
      status = 'acknowledged',
      updated_at = NOW()
    WHERE id = NEW.command_id
      AND status IN ('pending', 'sent');

  -- Handle command result (completed or failed)
  ELSIF NEW.type = 'command_result' AND NEW.command_id IS NOT NULL THEN
    UPDATE device_commands
    SET
      status = COALESCE(NEW.heartbeat_data->>'status', 'completed'),
      result = NEW.heartbeat_data->'result',
      error_message = NEW.heartbeat_data->>'error_message',
      updated_at = NOW()
    WHERE id = NEW.command_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION update_command_on_ack IS
  'Updates device_commands status when command_ack or command_result heartbeats are received';

-- Drop and recreate trigger to ensure latest version
DROP TRIGGER IF EXISTS on_command_ack_heartbeat ON device_heartbeats;
CREATE TRIGGER on_command_ack_heartbeat
  AFTER INSERT ON device_heartbeats
  FOR EACH ROW
  WHEN (NEW.type IN ('command_ack', 'command_result'))
  EXECUTE FUNCTION update_command_on_ack();
