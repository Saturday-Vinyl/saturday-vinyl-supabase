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

## Database Schema (Centralized)

All database migrations and edge functions are managed centrally in `shared-supabase/`. This is a git subtree from [saturday-vinyl-supabase](https://github.com/Saturday-Vinyl/saturday-vinyl-supabase), shared across all Saturday Vinyl projects.

- **Full schema reference:** `shared-supabase/schema/SCHEMA.md`
- **All migrations:** `shared-supabase/supabase/migrations/`
- **Migration conventions & RLS patterns:** `shared-supabase/CLAUDE.md`
- **Data model concepts:** `shared-docs/concepts/data_model.md`

### CLI Commands

```bash
# List migration status against remote
supabase migration list --workdir shared-supabase

# Check for schema drift
supabase db diff --workdir shared-supabase

# Dry-run pending migrations
supabase db push --workdir shared-supabase --dry-run

# Create a new migration (use admin_ prefix for this project)
supabase migration new admin_description --workdir shared-supabase
```

### Pushing migrations to the central repo

```bash
git subtree push --prefix=shared-supabase shared-supabase main
```

## Key Directories

- `lib/` - Flutter/Dart source code
- `lib/models/` - Data models
- `lib/providers/` - Riverpod providers
- `lib/repositories/` - Database repositories
- `lib/screens/` - UI screens
- `lib/services/` - Business logic services
- `lib/widgets/` - Reusable widgets
- `shared-supabase/` - Centralized Supabase migrations and edge functions (git subtree)
- `shared-docs/` - Cross-project protocols and documentation (git subtree)
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
