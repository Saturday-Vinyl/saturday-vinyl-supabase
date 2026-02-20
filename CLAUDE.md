# Claude Code Guidelines for Saturday Vinyl Supabase

This is the centralized Supabase repository for all Saturday Vinyl projects. All database migrations and edge functions live here.

## Database Schema Reference

- **Full schema:** `schema/SCHEMA.md` (auto-generated, human-readable)
- **Raw dump:** `schema/schema_dump.sql`
- **Data model concepts:** See `shared-docs/concepts/data_model.md` in consuming projects

### CLI Commands for Schema Introspection

```bash
# List all migrations and their status on the remote
supabase migration list

# Show what the remote has that local doesn't
supabase db diff

# Dry-run pending migrations
supabase db push --dry-run

# Dump the full remote schema
supabase db dump
```

When running from a consuming project (via subtree), add `--workdir shared-supabase` to all commands.

## Database Migrations

### Naming Convention

All migrations MUST use timestamp-based naming with a **project prefix**:

```
YYYYMMDDHHMMSS_{project}_description.sql
```

**Project prefixes:**

| Project | Prefix |
|---------|--------|
| saturday-admin-app | `admin` |
| saturday-mobile-app | `mobile` |
| sv-hub-firmware | `firmware` |
| cross-project | `shared` |

Examples:
- `20260207143000_admin_add_production_notes.sql`
- `20260207150000_mobile_add_user_preferences.sql`
- `20260207160000_firmware_add_ota_log_table.sql`
- `20260207170000_shared_add_audit_trail.sql`

### Migration Header

Every migration file MUST include:

```sql
-- ============================================================================
-- Migration: YYYYMMDDHHMMSS_project_description.sql
-- Project: saturday-admin-app | saturday-mobile-app | sv-hub-firmware | shared
-- Description: Brief description of what this migration does
-- Date: YYYY-MM-DD
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================
```

### Idempotency Requirement

**All migrations MUST be idempotent** - safe to run multiple times without error or data loss.

Required patterns:

```sql
-- Tables: Always use IF NOT EXISTS
CREATE TABLE IF NOT EXISTS my_table (...);

-- Indexes: Always use IF NOT EXISTS
CREATE INDEX IF NOT EXISTS idx_name ON table(column);

-- Policies: Drop before create
DROP POLICY IF EXISTS "policy_name" ON table;
CREATE POLICY "policy_name" ON table ...;

-- Triggers: Drop before create
DROP TRIGGER IF EXISTS trigger_name ON table;
CREATE TRIGGER trigger_name ...;

-- Columns: Check existence first
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'my_table' AND column_name = 'new_column'
  ) THEN
    ALTER TABLE my_table ADD COLUMN new_column TYPE;
  END IF;
END $$;

-- Constraints: Check existence first
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'constraint_name'
  ) THEN
    ALTER TABLE my_table ADD CONSTRAINT constraint_name CHECK (...);
  END IF;
END $$;

-- Enum values: Use exception handling
DO $$
BEGIN
  ALTER TYPE my_enum ADD VALUE 'new_value';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
```

### Row Level Security (RLS) Policies

**CRITICAL: User ID Mapping**

This project uses a custom `users` table separate from Supabase's `auth.users`. The tables are linked via:

- `users.auth_user_id` -> `auth.users.id` (Supabase auth UUID)
- `users.id` -> Application-level user ID (used for foreign keys in other tables)

When writing RLS policies that check user permissions, **always use `auth_user_id`** to compare against `auth.uid()`:

```sql
-- CORRECT: Use auth_user_id for auth.uid() comparison
CREATE POLICY "Admins can insert records"
ON my_table FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    WHERE u.auth_user_id = auth.uid()  -- Correct
    AND u.is_admin = true
  )
);

-- WRONG: Do NOT use users.id for auth.uid() comparison
CREATE POLICY "Admins can insert records"
ON my_table FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    WHERE u.id = auth.uid()  -- Wrong - will never match!
    AND u.is_admin = true
  )
);
```

**Standard RLS Policy Pattern**

For tables that require admin or specific permissions:

```sql
-- Read policy (usually open to all authenticated users)
CREATE POLICY "Authenticated users can read"
ON my_table FOR SELECT
TO authenticated
USING (true);

-- Write policies (check permissions via users table)
CREATE POLICY "Admins can insert"
ON my_table FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND (u.is_admin = true OR p.name = 'relevant_permission')
  )
);
```

## Edge Functions

Edge functions live in `supabase/functions/`. Each function's entry file should include a header comment:

```typescript
/**
 * Edge Function: function-name
 * Project: saturday-admin-app | saturday-mobile-app | sv-hub-firmware
 * Description: What this function does
 */
```

Deploy: `supabase functions deploy <function-name>`

## Deployment Checklist

Before closing out any work that includes migrations or edge function changes, ensure the Supabase CLI is linked to the remote project so changes can be deployed:

1. **Verify project is linked:** Run `supabase migration list` — if it fails with "Cannot find project ref", ask the user to run `supabase link` to connect the workspace to the remote project.
2. **Push migrations:** `supabase db push` (dry-run first with `--dry-run`)
3. **Deploy edge functions:** `supabase functions deploy <function-name>` for each changed function

Do not consider migration or edge function work complete until changes are deployed to the remote database.

## Important Notes

1. **Never commit secrets** - Use environment variables or Supabase Vault
2. **Test migrations with dry-run** before applying: `supabase db push --dry-run`
3. **All migrations must be idempotent** - This is critical for reliability
4. **Use project prefixes** in migration filenames for attribution
5. **Read `schema/SCHEMA.md`** for the current database state before writing migrations
