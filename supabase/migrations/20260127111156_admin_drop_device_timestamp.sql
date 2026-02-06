-- ============================================================================
-- Migration: 20260127111156_drop_device_timestamp.sql
-- Description: Drop device_timestamp column - not in protocol, server uses created_at
-- Date: 2026-01-27
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Drop device_timestamp column (not in Device Command Protocol v1.2.3)
-- The server-side created_at timestamp is sufficient for tracking heartbeat receipt time
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_heartbeats' AND column_name = 'device_timestamp'
  ) THEN
    ALTER TABLE device_heartbeats DROP COLUMN device_timestamp;
  END IF;
END $$;
