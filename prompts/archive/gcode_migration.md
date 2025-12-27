# GCode Repository Migration Guide

## Overview

This guide walks you through restructuring your GitHub gcode repository to use `cnc/` and `laser/` root directories, and migrating your existing Supabase database to match.

## Problem

Currently, all gcode files are being categorized as "cnc" because the detection logic defaults to 'cnc' when it can't find 'cnc' or 'laser' keywords in the path. This prevents laser cutting production steps from finding appropriate gcode files.

## Solution

Restructure the GitHub repository with clear `cnc/` and `laser/` directories, then update the database paths to match.

---

## Migration Steps

### Phase 1: Backup Current State ⚠️

**Before making any changes**, backup your current database:

```sql
-- Export current gcode_files table
COPY (SELECT * FROM public.gcode_files) TO '/tmp/gcode_files_backup.csv' WITH CSV HEADER;

-- Export step_gcode_files associations
COPY (SELECT * FROM public.step_gcode_files) TO '/tmp/step_gcode_files_backup.csv' WITH CSV HEADER;
```

Or use Supabase dashboard to export tables to CSV.

### Phase 2: Restructure GitHub Repository

1. **Clone your gcode repository locally**
   ```bash
   git clone https://github.com/Saturday-Vinyl/gcode.git
   cd gcode
   ```

2. **Create the new directory structure**
   ```bash
   # Create cnc and laser directories
   mkdir -p cnc laser
   ```

3. **Move existing folders to appropriate directories**

   For CNC files (milling, drilling, etc.):
   ```bash
   git mv turntable-base cnc/
   git mv platter-holes cnc/
   # ... move other CNC folders
   ```

   For Laser files (cutting, engraving):
   ```bash
   git mv logo-engrave laser/
   git mv panel-cut laser/
   # ... move other laser folders
   ```

4. **Commit and push changes**
   ```bash
   git add .
   git commit -m "Restructure repository with cnc/ and laser/ root directories"
   git push origin main
   ```

5. **Verify the new structure**

   Your repository should now look like:
   ```
   Saturday-Vinyl/gcode/
   ├── cnc/
   │   ├── turntable-base/
   │   │   ├── README.md
   │   │   └── base-mill.gcode
   │   └── platter-holes/
   │       ├── README.md
   │       └── holes.nc
   └── laser/
       └── logo-engrave/
           ├── README.md
           └── logo-engrave.gcode
   ```

### Phase 3: Update Database Paths

**Option A: Using the SQL Migration (Recommended)**

1. **Apply the migration**

   The migration file `supabase/migrations/012_gcode_path_migration.sql` has been created.

   If using Supabase CLI:
   ```bash
   cd saturday_app
   supabase db push
   ```

   Or manually run the migration in Supabase SQL Editor.

2. **Verify the migration**

   Run these queries to check results:

   ```sql
   -- Check for unmigrated files
   SELECT COUNT(*) as unmigrated_count
   FROM public.gcode_files
   WHERE migration_applied = false;

   -- Should return 0

   -- View updated CNC paths
   SELECT id, file_name, github_path, machine_type
   FROM public.gcode_files
   WHERE machine_type = 'cnc'
   ORDER BY github_path;

   -- View updated Laser paths
   SELECT id, file_name, github_path, machine_type
   FROM public.gcode_files
   WHERE machine_type = 'laser'
   ORDER BY github_path;
   ```

3. **Check production step associations**

   ```sql
   -- Verify steps still reference correct files
   SELECT
     ps.id as step_id,
     ps.name as step_name,
     ps.step_type,
     gf.id as gcode_file_id,
     gf.file_name,
     gf.github_path,
     gf.machine_type
   FROM public.production_steps ps
   INNER JOIN public.step_gcode_files sgf ON sgf.step_id = ps.id
   INNER JOIN public.gcode_files gf ON gf.id = sgf.gcode_file_id
   ORDER BY ps.name, sgf.execution_order;
   ```

**Option B: Using App UI (Alternative)**

If you prefer to use the app:

1. Navigate to Settings > GCode Sync
2. Click "Sync Repository"
3. The sync service will:
   - Fetch files from new paths (cnc/*, laser/*)
   - Create new records with correct paths
   - Mark old records for deletion
4. **Important**: This will create duplicate files with new IDs, breaking existing production step associations! Use Option A instead.

### Phase 4: Re-sync from GitHub

After the database paths are updated:

1. **In your Flutter app**, go to Settings
2. Find the "GCode Repository Sync" section
3. Click **"Sync Repository"**
4. The sync should now:
   - Match existing files by their new paths
   - Update descriptions from READMEs
   - Not create duplicates (thanks to unique constraint on github_path)

### Phase 5: Verify Everything Works

1. **Check laser files are available**
   - Navigate to a Product
   - Configure a production step
   - Set step type to "Laser Cutting"
   - You should now see laser gcode files in the selection dropdown

2. **Check CNC files still work**
   - Configure a "CNC Milling" step
   - Verify CNC files appear correctly

3. **Test existing production steps**
   - Any production steps that already had gcode files should still work
   - The UUIDs haven't changed, only the paths

### Phase 6: Cleanup (Optional)

After confirming everything works for a few days:

```sql
-- Remove the migration tracking column
ALTER TABLE public.gcode_files DROP COLUMN IF EXISTS migration_applied;
```

---

## Rollback Plan

If something goes wrong:

1. **Revert GitHub repository**
   ```bash
   git revert <commit-hash>
   git push origin main
   ```

2. **Restore database from backup**
   ```sql
   -- Restore gcode_files
   DELETE FROM public.gcode_files;
   COPY public.gcode_files FROM '/tmp/gcode_files_backup.csv' WITH CSV HEADER;

   -- Restore step_gcode_files (should be unchanged, but just in case)
   DELETE FROM public.step_gcode_files;
   COPY public.step_gcode_files FROM '/tmp/step_gcode_files_backup.csv' WITH CSV HEADER;
   ```

---

## Why This Works

1. **Production steps use UUIDs, not paths**: The `step_gcode_files` table references files by `gcode_file_id` (UUID), so changing the `github_path` doesn't break the associations.

2. **Unique constraint on github_path**: When you sync after restructuring, the upsert logic uses `github_path` as the conflict key, so files get updated rather than duplicated.

3. **The sync service fetches actual content from GitHub**: When a production step needs to run, it fetches the file content using the `github_path`, which will now point to the correct location.

---

## Expected Outcome

After migration:

- ✅ Laser files categorized as `machine_type: 'laser'`
- ✅ CNC files categorized as `machine_type: 'cnc'`
- ✅ Laser cutting production steps show laser gcode files
- ✅ CNC milling production steps show CNC gcode files
- ✅ Existing production step configurations remain intact
- ✅ Clear, self-documenting repository structure

---

## Questions or Issues?

If you encounter problems during migration:

1. Check the SQL migration output for errors
2. Verify the GitHub repository structure is correct
3. Check the verification queries to see which files weren't migrated
4. Review the `migration_applied` column to see which files were processed

The migration is designed to be **idempotent** - you can run it multiple times safely. It only updates paths that haven't been migrated yet.
