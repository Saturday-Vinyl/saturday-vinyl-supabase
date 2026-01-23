# Claude Code Guidelines for Saturday Admin App

This document provides context and guidelines for Claude Code agents working on this project.

## Project Overview

The Saturday Admin App is a Flutter application used by employees of Saturday (a maker of vinyl audio furniture with embedded record tracking technologies). The app manages:

- Product configuration and variants
- Production unit tracking and QR codes
- Firmware management and provisioning
- RFID tag management
- Machine operations (CNC, laser cutting)

## Technology Stack

- **Frontend**: Flutter/Dart with Riverpod state management
- **Backend**: Supabase (PostgreSQL, Auth, Storage)
- **Devices**: ESP32 family (ESP32, ESP32-S3, ESP32-C6, ESP32-H2)
- **Protocols**: Service Mode (USB serial), BLE Provisioning

## Database Migrations

### Naming Convention

All migrations MUST use timestamp-based naming:

```
YYYYMMDDHHMMSS_description.sql
```

Example: `20260123143000_add_user_preferences.sql`

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

### Migration Header

Every migration file should include:

```sql
-- ============================================================================
-- Migration: YYYYMMDDHHMMSS_description.sql
-- Description: Brief description of what this migration does
-- Date: YYYY-MM-DD
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================
```

### Migration Location

Migrations are stored in: `supabase/migrations/`

## Key Directories

- `lib/` - Flutter/Dart source code
- `lib/models/` - Data models
- `lib/providers/` - Riverpod providers
- `lib/repositories/` - Database repositories
- `lib/screens/` - UI screens
- `lib/services/` - Business logic services
- `lib/widgets/` - Reusable widgets
- `supabase/migrations/` - Database migrations
- `.claude/commands/` - Claude Code skill definitions

## Protocol Documentation

For device provisioning protocols, see:

- `.claude/commands/service-mode.md` - Factory serial provisioning
- `.claude/commands/ble-provisioning.md` - Consumer BLE provisioning

## Code Style

- Follow Flutter/Dart conventions
- Use Riverpod for state management
- Prefer `ConsumerWidget` and `ConsumerStatefulWidget`
- Use `ref.watch()` for reactive state, `ref.read()` for one-time reads
- Models should use Equatable for value equality

## Testing

Run analysis before committing:

```bash
flutter analyze
```

## Important Notes

1. **Never commit secrets** - Use environment variables or secure storage
2. **Test migrations locally** before applying to production
3. **Backup database** before running migrations on production
4. **All migrations must be idempotent** - This is critical for CLI workflows
