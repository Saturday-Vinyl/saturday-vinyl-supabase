-- ============================================================================
-- Migration: 012_gcode_path_migration.sql
-- Description: Update gcode_files paths for cnc/laser directory restructure
-- Date: 2025-10-15
-- Idempotent: Yes - safe to run multiple times
--
-- PURPOSE:
-- This migration updates existing gcode_files.github_path values to match
-- the new repository structure with cnc/ and laser/ root directories.
--
-- BEFORE: folder-name/file.gcode
-- AFTER:  cnc/folder-name/file.gcode OR laser/folder-name/file.gcode
--
-- ============================================================================

-- ============================================================================
-- STEP 1: Add temporary column to track migration status
-- ============================================================================

-- Add column if not exists (already idempotent)
ALTER TABLE public.gcode_files
  ADD COLUMN IF NOT EXISTS migration_applied BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.gcode_files.migration_applied IS
  'Tracks whether this file has been migrated to new path structure';

-- ============================================================================
-- STEP 2: Update paths for CNC files
-- ============================================================================

-- Update all CNC files to have 'cnc/' prefix (if not already present)
UPDATE public.gcode_files
SET
  github_path = 'cnc/' || github_path,
  updated_at = now(),
  migration_applied = true
WHERE
  machine_type = 'cnc'
  AND NOT github_path LIKE 'cnc/%'
  AND migration_applied = false;

-- ============================================================================
-- STEP 3: Update paths for Laser files
-- ============================================================================

-- Update all Laser files to have 'laser/' prefix (if not already present)
UPDATE public.gcode_files
SET
  github_path = 'laser/' || github_path,
  updated_at = now(),
  migration_applied = true
WHERE
  machine_type = 'laser'
  AND NOT github_path LIKE 'laser/%'
  AND migration_applied = false;

-- ============================================================================
-- STEP 4: Verification queries (run these manually to check results)
-- ============================================================================

-- Check that all files have been migrated
-- SELECT COUNT(*) as unmigrated_count
-- FROM public.gcode_files
-- WHERE migration_applied = false;

-- View all CNC files with new paths
-- SELECT id, file_name, github_path, machine_type
-- FROM public.gcode_files
-- WHERE machine_type = 'cnc'
-- ORDER BY github_path;

-- View all Laser files with new paths
-- SELECT id, file_name, github_path, machine_type
-- FROM public.gcode_files
-- WHERE machine_type = 'laser'
-- ORDER BY github_path;

-- Check for any production steps that use these files
-- SELECT
--   ps.id as step_id,
--   ps.name as step_name,
--   ps.step_type,
--   gf.id as gcode_file_id,
--   gf.file_name,
--   gf.github_path,
--   gf.machine_type
-- FROM public.production_steps ps
-- INNER JOIN public.step_gcode_files sgf ON sgf.step_id = ps.id
-- INNER JOIN public.gcode_files gf ON gf.id = sgf.gcode_file_id
-- ORDER BY ps.name, sgf.execution_order;

-- ============================================================================
-- STEP 5: Cleanup (Optional - run after verifying migration)
-- ============================================================================

-- After confirming everything works, you can drop the migration tracking column:
-- ALTER TABLE public.gcode_files DROP COLUMN IF EXISTS migration_applied;
