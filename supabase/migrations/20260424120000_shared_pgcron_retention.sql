-- ============================================================================
-- Migration: 20260424120000_shared_pgcron_retention.sql
-- Project: shared
-- Description: Purge old pg_cron job_run_details to prevent storage bloat
-- Date: 2026-04-24
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- First, delete existing historical data older than 7 days
DELETE FROM cron.job_run_details
WHERE end_time < now() - interval '7 days';

-- Schedule a daily cleanup job that removes entries older than 7 days.
-- pg_cron stores a row in cron.job_run_details for every execution of every
-- cron job, and without pruning this table grows unbounded.

-- Unschedule if it already exists
SELECT cron.unschedule(jobname)
FROM cron.job
WHERE jobname = 'cleanup-job-run-details';

-- Run daily at 3:00 AM UTC
SELECT cron.schedule(
  'cleanup-job-run-details',
  '0 3 * * *',
  $$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '7 days'$$
);
