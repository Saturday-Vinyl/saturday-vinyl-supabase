# Supabase Database Setup

This directory contains the database migrations for the Saturday Consumer App.

## Important: Extends Existing Schema

These migrations **extend** the existing Saturday admin app database. They:

- **EXTEND** the `users` table (add `avatar_url`, `preferences`, `auth_user_id`)
- **EXTEND** the `rfid_tags` table (add `library_album_id`, `associated_at`, `associated_by`, `last_seen_at`)
- **CREATE** new consumer-specific tables

The admin app's existing tables (`users`, `rfid_tags`, `production_units`, etc.) remain unchanged.

## Migrations

All migrations are idempotent and safe to run multiple times:

| File | Description |
|------|-------------|
| `20240101000001_create_enums.sql` | Custom enum types (library_role, consumer_device_type, etc.) |
| `20240101000002_create_tables.sql` | Extends users/rfid_tags, creates new consumer tables |
| `20240101000003_create_rls_policies.sql` | Row Level Security policies for consumer access |
| `20240101000004_create_indexes.sql` | Performance indexes including full-text search |
| `20240101000005_create_functions.sql` | Helper functions and triggers |

## Running Migrations

### Option 1: Using Supabase CLI (Recommended)

```bash
# Install Supabase CLI if not already installed
brew install supabase/tap/supabase

# Link to your project
supabase link --project-ref YOUR_PROJECT_REF

# Push migrations to remote database
supabase db push
```

### Option 2: Using Supabase Dashboard

1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor**
3. Run each migration file in order (001 → 005)

### Option 3: Direct psql

```bash
# Set your database URL
export DATABASE_URL="postgresql://postgres:[PASSWORD]@[HOST]:5432/postgres"

# Run migrations in order
psql $DATABASE_URL -f migrations/20240101000001_create_enums.sql
psql $DATABASE_URL -f migrations/20240101000002_create_tables.sql
psql $DATABASE_URL -f migrations/20240101000003_create_rls_policies.sql
psql $DATABASE_URL -f migrations/20240101000004_create_indexes.sql
psql $DATABASE_URL -f migrations/20240101000005_create_functions.sql
```

## Schema Overview

```
                    EXISTING (Admin App)              NEW (Consumer App)
                    ════════════════════              ══════════════════

users ◄─────────────────────────────────────────────► (extended with auth_user_id, etc.)
  │
  ├── libraries ──────────────────┐
  │       │                       │
  │       └── library_members ◄───┤ (user membership & roles)
  │               │               │
  │               ▼               │
  │       library_albums ◄────────┤
  │           │   │               │
  │           │   │               │
  │           │   └── listening_history
  │           │
  │           ▼
rfid_tags ◄───────────────────────────────────────► (extended with library_album_id, etc.)
  │
  │
consumer_devices ─────────────────┐
        │                         │
        └── album_locations ◄─────┘

albums (canonical, shared across libraries)
```

## Tables

### Extended Tables (from Admin App)

| Table | New Columns |
|-------|-------------|
| `users` | `avatar_url`, `preferences`, `auth_user_id` |
| `rfid_tags` | `library_album_id`, `associated_at`, `associated_by`, `last_seen_at` |

### New Consumer Tables

| Table | Description |
|-------|-------------|
| `libraries` | Vinyl record collections |
| `library_members` | Library membership with roles (owner/editor/viewer) |
| `albums` | Canonical album metadata from Discogs |
| `library_albums` | Links albums to libraries with notes, favorites |
| `consumer_devices` | User-owned hubs and crates |
| `listening_history` | Play history for recommendations |
| `album_locations` | Where albums are physically stored |

## Row Level Security

All new tables have RLS enabled. Key policies:

- **users**: Consumer users access via `auth_user_id`, can view library co-members
- **libraries**: Members can view, owners can modify
- **library_members**: Owners can manage, users can leave
- **albums**: Authenticated users can view/create (canonical data)
- **library_albums**: Members can view, editors can modify
- **rfid_tags**: Added policy for viewing/updating based on library membership
- **consumer_devices**: Users can only access their own devices
- **listening_history**: Users can only access their own history
- **album_locations**: Access based on library membership

## Helper Functions

| Function | Description |
|----------|-------------|
| `handle_consumer_auth_signup()` | Auto-creates/links user on Supabase Auth signup |
| `handle_new_library()` | Auto-adds creator as owner |
| `associate_rfid_tag()` | Associates existing rfid_tag with library album |
| `record_play()` | Records a listening session |
| `search_albums()` | Full-text search for albums |
| `get_library_albums_with_details()` | Fetches albums with location info |
| `get_recently_played()` | Gets user's recent listening history |
| `resolve_tag_to_album()` | Looks up EPC and returns album info |
| `get_or_create_consumer_user()` | Gets users table record from auth |
| `get_user_id_from_auth()` | Bridges auth.uid() to users.id |

## Enum Types

| Enum | Values |
|------|--------|
| `library_role` | owner, editor, viewer |
| `consumer_device_type` | hub, crate |
| `consumer_device_status` | online, offline, setup_required |
| `record_side` | A, B |
