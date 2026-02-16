-- ============================================================================
-- Migration: 20260126110000_add_device_type_slug.sql
-- Description: Add slug column to device_types for stable machine-readable IDs
-- Date: 2026-01-26
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Step 1: Add slug column (nullable initially for migration)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_types' AND column_name = 'slug'
  ) THEN
    ALTER TABLE device_types ADD COLUMN slug VARCHAR(100);
  END IF;
END $$;

COMMENT ON COLUMN device_types.slug IS 'URL-safe identifier for device type. Used in firmware schemas instead of UUID.';

-- Step 2: Populate slugs from existing names (convert to kebab-case)
-- Remove non-alphanumeric chars, replace with hyphens, lowercase, trim leading/trailing hyphens
UPDATE device_types
SET slug = lower(
  regexp_replace(
    regexp_replace(
      regexp_replace(name, '[^a-zA-Z0-9]+', '-', 'g'),
      '^-+', '', 'g'
    ),
    '-+$', '', 'g'
  )
)
WHERE slug IS NULL OR slug = '';

-- Step 3: Handle any duplicate slugs by appending a number
DO $$
DECLARE
  dup_slug VARCHAR(100);
  dup_id UUID;
  counter INTEGER;
BEGIN
  -- Find slugs that appear more than once
  FOR dup_slug IN
    SELECT slug FROM device_types GROUP BY slug HAVING COUNT(*) > 1
  LOOP
    counter := 1;
    -- For each duplicate (skip the first one)
    FOR dup_id IN
      SELECT id FROM device_types WHERE slug = dup_slug ORDER BY created_at OFFSET 1
    LOOP
      counter := counter + 1;
      UPDATE device_types SET slug = dup_slug || '-' || counter WHERE id = dup_id;
    END LOOP;
  END LOOP;
END $$;

-- Step 4: Add NOT NULL constraint
DO $$
BEGIN
  ALTER TABLE device_types ALTER COLUMN slug SET NOT NULL;
EXCEPTION
  WHEN others THEN NULL;
END $$;

-- Step 5: Add unique index
CREATE UNIQUE INDEX IF NOT EXISTS idx_device_types_slug ON device_types(slug);

-- Step 6: Add check constraint for valid slug format
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'device_types_slug_format'
  ) THEN
    ALTER TABLE device_types ADD CONSTRAINT device_types_slug_format
      CHECK (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$');
  END IF;
END $$;
