-- ============================================================================
-- Migration: 20260625120000_shared_schedule_heartbeat_cleanup.sql
-- Project: shared
-- Description: Schedule the cleanup_old_heartbeats() function via pg_cron so old
--              device_heartbeats rows are purged automatically (storage limits)
-- Date: 2026-06-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- The cleanup_old_heartbeats(retention_hours INTEGER DEFAULT 24) function
-- already exists but was never scheduled, so device_heartbeats grows unbounded.
-- device_heartbeats is high-volume (every connected device reports regularly),
-- so we run the purge hourly to keep the table close to the 24h retention
-- window rather than letting it drift toward ~2x between daily runs.

-- Unschedule first so re-running this migration (or changing the schedule)
-- does not create duplicate jobs.
SELECT cron.unschedule(jobname)
FROM cron.job
WHERE jobname = 'cleanup-old-heartbeats';

-- Run at the top of every hour. cleanup_old_heartbeats() defaults to a 24-hour
-- retention window and returns the number of rows deleted.
SELECT cron.schedule(
  'cleanup-old-heartbeats',
  '0 * * * *',
  $$SELECT public.cleanup_old_heartbeats()$$
);
