# Supabase Migrations

This directory contains SQL migration files for the Saturday! admin app database schema.

## Migration Order

Apply migrations in the following order:

1. **000_users_and_permissions.sql** - Users, permissions, and authentication (run first!)
2. **001_products_schema.sql** - Base schema with products, variants, device_types, production_steps
3. **003_products_and_variants.sql** - Additional product/variant features (if needed)
4. **004_device_types.sql** - Adds `current_firmware_version` column to device_types
5. **005_production_units.sql** - Production units and tracking (references users table)
6. **006_firmware_versions.sql** - Firmware version management

## How to Apply Migrations

### Option 1: Supabase Dashboard (Recommended for existing databases)

1. Go to your Supabase project dashboard
2. Click "SQL Editor" in the left sidebar
3. Copy the contents of each migration file (in order)
4. Paste into the SQL Editor
5. Click "Run"

### Option 2: Supabase CLI (For new databases or dev environments)

```bash
cd /path/to/saturday_app
supabase db push
```

## Migration Safety

All migrations after 001 are designed to be **idempotent** - they can be run multiple times safely:
- Use `IF NOT EXISTS` checks for tables, columns, and indexes
- Use `DO $$ ... END $$` blocks to conditionally create policies
- Will not duplicate data or fail if already applied

## Storage Buckets

In addition to database migrations, you need to create storage buckets:

1. **production-files** (Private) - Production step files
2. **qr-codes** (Private) - Generated QR codes
3. **firmware-binaries** (Public) - Device firmware files

See `../supabase_storage_setup.md` for detailed instructions.

## Notes

- **Migration 000** must be run first as it creates the `users` table required by later migrations
- **Migration 001** drops and recreates tables, so only use it on a fresh database
- **Migrations 004-006** are safe to run on existing databases with migrations 000-001 applied
- Always backup your database before applying migrations to production

## For Existing Databases

If you've already applied the old root-level migration files:
- `supabase_schema.sql` → This is now **000_users_and_permissions.sql** (already applied)
- `supabase_products_schema.sql` → This is now **001_products_schema.sql** (already applied)

You only need to run migrations **004, 005, and 006** on your existing database.
