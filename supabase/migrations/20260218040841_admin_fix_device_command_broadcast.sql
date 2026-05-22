-- ============================================================================
-- Migration: 20260218040841_admin_fix_device_command_broadcast.sql
-- Project: admin
-- Description: Fix device command broadcast to use realtime.send() instead of
--              deprecated pg_notify('realtime:broadcast'). Also add device_commands
--              to supabase_realtime publication for Postgres Changes support.
-- Date: 2026-02-18
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Replace broadcast function with realtime.send()
-- The old pg_notify('realtime:broadcast', ...) is no longer supported.
-- realtime.send(payload, event, topic, is_private) is the modern API.
CREATE OR REPLACE FUNCTION broadcast_device_command()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  channel_name TEXT;
BEGIN
  -- Replace colons with dashes for channel name
  channel_name := 'device:' || REPLACE(NEW.mac_address, ':', '-');

  -- Broadcast command to device channel via Supabase Realtime
  PERFORM realtime.send(
    jsonb_build_object(
      'id', NEW.id,
      'command', NEW.command,
      'capability', NEW.capability,
      'test_name', NEW.test_name,
      'parameters', NEW.parameters
    ),
    'command',
    channel_name,
    false
  );

  RETURN NEW;
END;
$$;

-- Add device_commands to supabase_realtime publication
-- This enables Postgres Changes (INSERT/UPDATE) for admin app monitoring
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE device_commands;
      RAISE NOTICE 'Added device_commands to supabase_realtime publication';
    EXCEPTION
      WHEN duplicate_object THEN
        RAISE NOTICE 'device_commands already in supabase_realtime publication';
    END;
  END IF;
END $$;
