-- ============================================================================
-- Supabase Migration Schema Seed (Centralized)
-- ============================================================================
--
-- Run this script ONCE on your production database if you need to re-seed
-- the migration tracking table to match the centralized migration filenames
-- (with project prefixes).
--
-- This updates the `name` column in `supabase_migrations.schema_migrations`
-- to match the renamed migration files. The `version` (timestamp) column
-- remains unchanged, which is what the Supabase CLI uses for matching.
--
-- Usage:
--   1. Connect to your Supabase database via SQL Editor or psql
--   2. Run this script
--   3. Verify with: supabase migration list
--
-- ============================================================================

-- Create the schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS supabase_migrations;

-- Create the schema_migrations table if it doesn't exist
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (
    version TEXT PRIMARY KEY,
    statements TEXT[],
    name TEXT
);

-- Update existing migration names to include admin_ prefix
-- This makes the tracking table match the renamed files
UPDATE supabase_migrations.schema_migrations
SET name = 'admin_' || name
WHERE version IN (
    '20251001000000',
    '20251001010000',
    '20251002000000',
    '20251003000000',
    '20251009000000',
    '20251010000000',
    '20251011000000',
    '20251012000000',
    '20251013000000',
    '20251014000000',
    '20251015000000',
    '20251016000000',
    '20251017000000',
    '20251018000000',
    '20251019000000',
    '20251020000000',
    '20260104000000',
    '20260104010000',
    '20260105000000',
    '20260107000000',
    '20260125000000',
    '20260125010000',
    '20260125020000',
    '20260125030000',
    '20260125040000',
    '20260125050000',
    '20260125060000',
    '20260125070000',
    '20260125080000',
    '20260125090000',
    '20260125120000',
    '20260125130000',
    '20260125140000',
    '20260125150000',
    '20260125160000',
    '20260125170000',
    '20260126100000',
    '20260126110000',
    '20260126150000',
    '20260127084309',
    '20260127111156',
    '20260127111628',
    '20260127122404',
    '20260130163344',
    '20260130181155',
    '20260201000000',
    '20260201000001'
)
AND name NOT LIKE 'admin_%';

-- Verify the update
DO $$
DECLARE
    migration_count INTEGER;
    admin_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO migration_count FROM supabase_migrations.schema_migrations;
    SELECT COUNT(*) INTO admin_count FROM supabase_migrations.schema_migrations WHERE name LIKE 'admin_%';
    RAISE NOTICE 'Total migrations: %, Admin-prefixed: %', migration_count, admin_count;
END $$;
