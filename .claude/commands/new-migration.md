---
description: Guide for creating a new database migration
---

# New Migration

Reference the migration conventions and current schema before creating a new migration.

@shared-supabase/CLAUDE.md
@shared-supabase/schema/SCHEMA.md

## Steps

1. Determine the appropriate project prefix for the migration filename:
   - `admin` for saturday-admin-app changes
   - `mobile` for saturday-mobile-app changes
   - `firmware` for sv-hub-firmware changes
   - `shared` for cross-project changes

2. Create the migration file in `shared-supabase/supabase/migrations/` using:
   ```bash
   supabase migration new {prefix}_description --workdir shared-supabase
   ```

3. Write idempotent SQL following the conventions in the CLAUDE.md above.

4. Validate with: `supabase db push --workdir shared-supabase --dry-run`
