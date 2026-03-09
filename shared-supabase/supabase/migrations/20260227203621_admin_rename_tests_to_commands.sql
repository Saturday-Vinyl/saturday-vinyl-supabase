-- ============================================================================
-- Migration: 20260227203621_admin_rename_tests_to_commands.sql
-- Project: saturday-admin-app
-- Description: Rename capabilities.tests column to capabilities.commands
-- Date: 2026-02-27
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Rename tests -> commands (only if old column exists and new doesn't)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'tests'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'commands'
  ) THEN
    ALTER TABLE capabilities RENAME COLUMN tests TO commands;
  END IF;
END $$;
