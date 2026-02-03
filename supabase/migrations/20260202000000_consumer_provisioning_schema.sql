-- Migration: Consumer Provisioning Schema Updates
-- This migration aligns the units and devices tables with consumer app requirements

-- 1. Create unit_status enum (skip if already exists from partial migration)
DO $$ BEGIN
  CREATE TYPE unit_status AS ENUM (
    'in_production',
    'inventory',
    'assigned',
    'claimed'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- 2. Drop existing RLS policies that reference columns we're changing
DROP POLICY IF EXISTS "Consumers can update own units" ON units;
DROP POLICY IF EXISTS "Consumers can view own units" ON units;
DROP POLICY IF EXISTS "Units are viewable by assigned consumer" ON units;
DROP POLICY IF EXISTS "Units are updatable by assigned consumer" ON units;
DROP POLICY IF EXISTS "Users can view their own units" ON units;
DROP POLICY IF EXISTS "Users can update their own units" ON units;

-- 2b. Drop views that reference the status column (will recreate after)
DROP VIEW IF EXISTS units_with_devices;
DROP VIEW IF EXISTS units_dashboard;

-- 3. Rename units columns for clarity (skip if already renamed)
DO $$ BEGIN
  ALTER TABLE units RENAME COLUMN user_id TO consumer_user_id;
EXCEPTION
  WHEN undefined_column THEN NULL;
END $$;

DO $$ BEGIN
  ALTER TABLE units RENAME COLUMN device_name TO consumer_name;
EXCEPTION
  WHEN undefined_column THEN NULL;
END $$;

-- 4. Migrate existing status values to new enum values
UPDATE units SET status = 'inventory' WHERE status = 'factory_provisioned';
UPDATE units SET status = 'assigned' WHERE status = 'user_claimed';
UPDATE units SET status = 'claimed' WHERE status = 'user_provisioned';
UPDATE units SET status = 'in_production' WHERE status IS NULL OR status = 'unprovisioned';

-- 5. Change status column type to enum
-- First drop the default, change type, then restore default
ALTER TABLE units ALTER COLUMN status DROP DEFAULT;
ALTER TABLE units ALTER COLUMN status TYPE unit_status USING status::unit_status;
ALTER TABLE units ALTER COLUMN status SET DEFAULT 'in_production'::unit_status;

-- 6. Add consumer provisioning columns to devices table
ALTER TABLE devices ADD COLUMN IF NOT EXISTS consumer_provisioned_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS consumer_provisioned_by UUID REFERENCES auth.users(id);

-- 7. Remove consumer_provisioned_at from units (now lives on devices)
ALTER TABLE units DROP COLUMN IF EXISTS consumer_provisioned_at;

-- 8. Create indexes for new columns
CREATE INDEX IF NOT EXISTS idx_devices_consumer_provisioned_by ON devices(consumer_provisioned_by);
CREATE INDEX IF NOT EXISTS idx_units_consumer_user_id ON units(consumer_user_id);

-- 9. Recreate RLS policies with new column name
CREATE POLICY "Users can view their own units" ON units
  FOR SELECT USING (auth.uid() = consumer_user_id);

CREATE POLICY "Users can update their own units" ON units
  FOR UPDATE USING (auth.uid() = consumer_user_id);
