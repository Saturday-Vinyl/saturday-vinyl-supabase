-- ============================================================================
-- Supabase Migration Schema Seed
-- ============================================================================
--
-- Run this script ONCE on your production database before switching to
-- Supabase CLI-based migrations. This marks all previously-applied migrations
-- as complete in Supabase's migration tracking table.
--
-- Usage:
--   1. Connect to your Supabase database via SQL Editor or psql
--   2. Run this script
--   3. You can now use `supabase db push` without it re-running old migrations
--
-- ============================================================================

-- Create the schema if it doesn't exist (Supabase CLI creates this automatically)
CREATE SCHEMA IF NOT EXISTS supabase_migrations;

-- Create the schema_migrations table if it doesn't exist
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (
    version TEXT PRIMARY KEY,
    statements TEXT[],
    name TEXT
);

-- Insert all previously-applied migrations
-- These are the migrations that were applied manually before switching to CLI
INSERT INTO supabase_migrations.schema_migrations (version, name) VALUES
    ('20251001000000', 'users_and_permissions'),
    ('20251001010000', 'products_schema'),
    ('20251002000000', 'products_and_variants'),
    ('20251003000000', 'device_types'),
    ('20251009000000', 'production_units'),
    ('20251010000000', 'firmware_versions'),
    ('20251011000000', 'unit_firmware_history'),
    ('20251012000000', 'orders_and_customers'),
    ('20251013000000', 'production_step_labels'),
    ('20251014000000', 'production_step_types'),
    ('20251015000000', 'machine_macros'),
    ('20251016000000', 'gcode_path_migration'),
    ('20251017000000', 'file_library'),
    ('20251018000000', 'step_timers'),
    ('20251019000000', 'rfid_tags'),
    ('20251020000000', 'rfid_tag_rolls'),
    ('20260104000000', 'firmware_provisioning'),
    ('20260104010000', 'add_esp32_chip_types'),
    ('20260105000000', 'remove_provisioning_manifest')
ON CONFLICT (version) DO NOTHING;

-- Verify the seeding
DO $$
DECLARE
    migration_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO migration_count FROM supabase_migrations.schema_migrations;
    RAISE NOTICE 'Schema migrations table now has % entries', migration_count;
    RAISE NOTICE 'You can now use supabase db push for new migrations';
END $$;
