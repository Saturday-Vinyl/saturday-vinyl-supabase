-- ============================================================================
-- Migration: 20260625130000_shared_fix_heartbeat_cleanup_column.sql
-- Project: shared
-- Description: Fix cleanup_old_heartbeats() to use created_at — device_heartbeats
--              has no received_at column, so the scheduled purge was erroring out
-- Date: 2026-06-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- cleanup_old_heartbeats() referenced a non-existent "received_at" column,
-- causing the hourly cron job (scheduled in 20260625120000) to fail every run.
-- The retention timestamp lives in created_at (covered by
-- idx_device_heartbeats_created_at). CREATE OR REPLACE keeps the same
-- signature so the existing cron job picks up the fix automatically.
CREATE OR REPLACE FUNCTION public.cleanup_old_heartbeats(retention_hours integer DEFAULT 24)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM device_heartbeats
  WHERE created_at < NOW() - (retention_hours || ' hours')::INTERVAL;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$function$;
