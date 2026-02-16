# Saturday Vinyl Supabase

Centralized Supabase migrations and edge functions for all Saturday Vinyl projects.

## Overview

This repository is the **single source of truth** for the Saturday Vinyl database schema and edge functions. It is distributed to consuming projects via git subtree at `shared-supabase/`.

### Consuming Projects

| Project | Prefix | Description |
|---------|--------|-------------|
| `saturday-admin-app` | `admin` | Factory/technician desktop app (Flutter) |
| `saturday-mobile-app` | `mobile` | Consumer mobile app (Flutter) |
| `sv-hub-firmware` | `firmware` | ESP32 device firmware |

## Quick Start

### First-time setup (add to a new project)

```bash
# From your project root:
~/saturday-vinyl-supabase/scripts/setup-supabase-subtree.sh
```

Or manually:

```bash
git remote add shared-supabase https://github.com/Saturday-Vinyl/saturday-vinyl-supabase.git
git subtree add --prefix=shared-supabase shared-supabase main --squash
```

### Pull latest changes

```bash
git subtree pull --prefix=shared-supabase shared-supabase main --squash -m "Merge shared-supabase updates"
```

### Push changes back to central repo

```bash
git subtree push --prefix=shared-supabase shared-supabase main
```

## Supabase CLI Usage

All Supabase CLI commands use `--workdir shared-supabase` when run from a consuming project:

```bash
# List migration status
supabase migration list --workdir shared-supabase

# Dry-run pending migrations
supabase db push --workdir shared-supabase --dry-run

# Check for schema drift
supabase db diff --workdir shared-supabase

# Deploy an edge function
supabase functions deploy <function-name> --workdir shared-supabase

# Dump current remote schema
supabase db dump --workdir shared-supabase
```

When working directly in this repo (not via subtree), omit `--workdir`:

```bash
supabase migration list
supabase db push --dry-run
```

## Creating a New Migration

1. Create the migration file:
   ```bash
   supabase migration new {project}_description --workdir shared-supabase
   ```

2. Edit the generated SQL file. Follow the conventions in `CLAUDE.md`.

3. Validate against the remote database:
   ```bash
   supabase db push --workdir shared-supabase --dry-run
   ```

4. Commit, then push to the central repo:
   ```bash
   git subtree push --prefix=shared-supabase shared-supabase main
   ```

## Schema Documentation

- **`schema/SCHEMA.md`** - Human-readable schema reference (auto-generated)
- **`schema/schema_dump.sql`** - Raw pg_dump of the current schema

Regenerate after applying migrations:

```bash
./scripts/generate-schema-docs.sh
```

## Directory Structure

```
├── CLAUDE.md                          # Migration guidelines for AI agents
├── README.md                          # This file
├── supabase/
│   ├── config.toml                    # Supabase project configuration
│   ├── migrations/                    # ALL migrations from ALL projects
│   └── functions/                     # ALL edge functions
├── schema/
│   ├── SCHEMA.md                      # Generated schema documentation
│   └── schema_dump.sql                # Generated schema dump
├── scripts/
│   ├── setup-supabase-subtree.sh      # First-time setup for consuming projects
│   └── generate-schema-docs.sh        # Schema doc generation
└── templates/
    └── claude-commands/               # Claude Code slash command templates
```
