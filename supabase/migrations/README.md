# Supabase Migrations

This directory contains SQL migration files for the Saturday! admin app database schema.

## Naming Convention

Migration files use timestamp-based naming for Supabase CLI compatibility:

```
YYYYMMDDHHMMSS_description.sql
```

Example: `20260123143000_add_user_preferences.sql`

## Migration Requirements

**All migrations MUST be idempotent** - safe to run multiple times without error or data loss.

### Idempotency Patterns

Use these patterns to ensure migrations are idempotent:

```sql
-- Tables
CREATE TABLE IF NOT EXISTS my_table (...);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_name ON table(column);

-- Policies (drop then create)
DROP POLICY IF EXISTS "policy_name" ON table;
CREATE POLICY "policy_name" ON table ...;

-- Triggers (drop then create)
DROP TRIGGER IF EXISTS trigger_name ON table;
CREATE TRIGGER trigger_name ...;

-- Functions
CREATE OR REPLACE FUNCTION function_name() ...;

-- Columns
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'my_table' AND column_name = 'new_column'
  ) THEN
    ALTER TABLE my_table ADD COLUMN new_column TYPE;
  END IF;
END $$;

-- Constraints
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'constraint_name'
  ) THEN
    ALTER TABLE my_table ADD CONSTRAINT constraint_name CHECK (...);
  END IF;
END $$;

-- Enum values
DO $$
BEGIN
  ALTER TYPE my_enum ADD VALUE 'new_value';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
```

### Migration Header Template

Every migration should include this header:

```sql
-- ============================================================================
-- Migration: YYYYMMDDHHMMSS_description.sql
-- Description: Brief description of what this migration does
-- Date: YYYY-MM-DD
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================
```

## How to Apply Migrations

### Option 1: Supabase CLI (Recommended)

```bash
# Push all pending migrations to your database
supabase db push

# Generate a new migration file
supabase migration new add_user_preferences
```

### Option 2: Supabase Dashboard

1. Go to your Supabase project dashboard
2. Click "SQL Editor" in the left sidebar
3. Copy the contents of the migration file
4. Paste into the SQL Editor
5. Click "Run"

## Initial Setup for CLI

If you're switching from manual migrations to CLI-based workflow:

1. Run `../seed_schema_migrations.sql` on your database ONCE
2. This marks all existing migrations as applied
3. You can now use `supabase db push` for new migrations

## Migration History

| Version | Name | Description |
|---------|------|-------------|
| 20251001000000 | users_and_permissions | Users, permissions, and authentication |
| 20251001010000 | products_schema | Products, variants, device types, production steps |
| 20251002000000 | products_and_variants | Additional product/variant features |
| 20251003000000 | device_types | Adds current_firmware_version to device_types |
| 20251009000000 | production_units | Production units and tracking |
| 20251010000000 | firmware_versions | Firmware version management |
| 20251011000000 | unit_firmware_history | Firmware history tracking |
| 20251012000000 | orders_and_customers | Shopify orders integration |
| 20251013000000 | production_step_labels | Step label system |
| 20251014000000 | production_step_types | Step types and machine integration |
| 20251015000000 | machine_macros | CNC/Laser machine macros |
| 20251016000000 | gcode_path_migration | GCode path migration |
| 20251017000000 | file_library | File library system |
| 20251018000000 | step_timers | Step timer tracking |
| 20251019000000 | rfid_tags | RFID tag management |
| 20251020000000 | rfid_tag_rolls | RFID tag roll batching |
| 20260104000000 | firmware_provisioning | Firmware provisioning step type |
| 20260104010000 | add_esp32_chip_types | ESP32-C6 and H2 chip support |
| 20260105000000 | remove_provisioning_manifest | Remove manifest columns |
| 20260107000000 | thread_credentials | Thread Border Router credentials |

## Storage Buckets

In addition to database migrations, you may need to create storage buckets:

1. **production-files** (Private) - Production step files
2. **qr-codes** (Private) - Generated QR codes
3. **firmware-binaries** (Public) - Device firmware files

See `../supabase_storage_setup.md` for detailed instructions.

## Notes

- All migrations are idempotent and safe to run multiple times
- Always backup your database before applying migrations to production
- New migrations should follow the timestamp naming convention
- Test migrations locally before applying to production
