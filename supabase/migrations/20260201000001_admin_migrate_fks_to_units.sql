-- ============================================================================
-- Migration: 20260201000001_migrate_fks_to_units.sql
-- Description: Update all foreign keys from production_units to units table
-- Date: 2026-02-01
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- This migration updates all tables that previously referenced production_units
-- to instead reference the units table. Since the data migration (20260125040000)
-- preserved IDs (units.id = production_units.id), the data remains valid.
--
-- NOTE: Some tables may have orphaned records pointing to units that were only
-- in production_units but never migrated to units. We clean these up first.

-- ============================================================================
-- 0. Clean up orphaned records (referencing non-existent units)
-- ============================================================================

-- Delete orphaned unit_step_completions
DELETE FROM unit_step_completions
WHERE unit_id NOT IN (SELECT id FROM units);

-- Delete orphaned unit_timers
DELETE FROM unit_timers
WHERE unit_id NOT IN (SELECT id FROM units);

-- Delete orphaned thread_credentials (if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'thread_credentials') THEN
    EXECUTE 'DELETE FROM thread_credentials WHERE unit_id NOT IN (SELECT id FROM units)';
  END IF;
END $$;

-- ============================================================================
-- 1. unit_step_completions
-- ============================================================================

-- Drop old FK constraint (may have different names depending on when created)
ALTER TABLE unit_step_completions
  DROP CONSTRAINT IF EXISTS unit_step_completions_unit_id_fkey;

-- Add new FK pointing to units table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'unit_step_completions_units_fkey'
    AND table_name = 'unit_step_completions'
  ) THEN
    ALTER TABLE unit_step_completions
      ADD CONSTRAINT unit_step_completions_units_fkey
      FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE;
  END IF;
END $$;

-- ============================================================================
-- 2. unit_timers
-- ============================================================================

-- Drop old FK constraint
ALTER TABLE unit_timers
  DROP CONSTRAINT IF EXISTS unit_timers_unit_id_fkey;

-- Add new FK pointing to units table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'unit_timers_units_fkey'
    AND table_name = 'unit_timers'
  ) THEN
    ALTER TABLE unit_timers
      ADD CONSTRAINT unit_timers_units_fkey
      FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE;
  END IF;
END $$;

-- ============================================================================
-- 3. unit_firmware_history (if exists)
-- ============================================================================

-- Only alter if table exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'unit_firmware_history'
  ) THEN
    -- Drop old FK constraint
    ALTER TABLE unit_firmware_history
      DROP CONSTRAINT IF EXISTS unit_firmware_history_unit_id_fkey;

    -- Add new FK pointing to units table
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints
      WHERE constraint_name = 'unit_firmware_history_units_fkey'
      AND table_name = 'unit_firmware_history'
    ) THEN
      ALTER TABLE unit_firmware_history
        ADD CONSTRAINT unit_firmware_history_units_fkey
        FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- ============================================================================
-- 4. thread_credentials (if exists)
-- ============================================================================

-- Only alter if table exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'thread_credentials'
  ) THEN
    -- Drop old FK constraint
    ALTER TABLE thread_credentials
      DROP CONSTRAINT IF EXISTS thread_credentials_unit_id_fkey;

    -- Add new FK pointing to units table
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints
      WHERE constraint_name = 'thread_credentials_units_fkey'
      AND table_name = 'thread_credentials'
    ) THEN
      ALTER TABLE thread_credentials
        ADD CONSTRAINT thread_credentials_units_fkey
        FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- ============================================================================
-- 5. orders (assigned_unit_id) - if column exists
-- ============================================================================

-- Only alter if table and column exist
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'assigned_unit_id'
  ) THEN
    -- Drop old FK constraint
    ALTER TABLE orders
      DROP CONSTRAINT IF EXISTS orders_assigned_unit_id_fkey;

    -- Add new FK pointing to units table
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints
      WHERE constraint_name = 'orders_units_fkey'
      AND table_name = 'orders'
    ) THEN
      ALTER TABLE orders
        ADD CONSTRAINT orders_units_fkey
        FOREIGN KEY (assigned_unit_id) REFERENCES units(id) ON DELETE SET NULL;
    END IF;
  END IF;
END $$;

-- ============================================================================
-- Verification queries (run manually to verify migration)
-- ============================================================================

-- Check all FKs now point to units table:
-- SELECT
--   tc.table_name,
--   tc.constraint_name,
--   ccu.table_name AS foreign_table_name,
--   kcu.column_name
-- FROM information_schema.table_constraints AS tc
-- JOIN information_schema.key_column_usage AS kcu
--   ON tc.constraint_name = kcu.constraint_name
-- JOIN information_schema.constraint_column_usage AS ccu
--   ON ccu.constraint_name = tc.constraint_name
-- WHERE tc.constraint_type = 'FOREIGN KEY'
--   AND ccu.table_name IN ('units', 'production_units');

-- Update table comments (only if tables exist)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'unit_step_completions') THEN
    COMMENT ON TABLE unit_step_completions IS 'Completed production steps for units. Links to units table.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'unit_timers') THEN
    COMMENT ON TABLE unit_timers IS 'Active timer instances for units. Links to units table.';
  END IF;
END $$;
