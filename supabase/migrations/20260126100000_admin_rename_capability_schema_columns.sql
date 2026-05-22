-- ============================================================================
-- Migration: 20260126100000_rename_capability_schema_columns.sql
-- Description: Rename capability schema columns to clearer {phase}_{direction}_schema pattern
-- Date: 2026-01-26
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================
--
-- Renames:
--   factory_attributes_schema         -> factory_input_schema
--   factory_provision_attributes_schema -> factory_output_schema
--   consumer_attributes_schema        -> consumer_input_schema
--   consumer_provision_attributes_schema -> consumer_output_schema
--   heartbeat_attributes_schema       -> heartbeat_schema
-- ============================================================================

-- Rename factory_attributes_schema -> factory_input_schema
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'factory_attributes_schema'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'factory_input_schema'
  ) THEN
    ALTER TABLE capabilities RENAME COLUMN factory_attributes_schema TO factory_input_schema;
  END IF;
END $$;

-- Rename factory_provision_attributes_schema -> factory_output_schema
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'factory_provision_attributes_schema'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'factory_output_schema'
  ) THEN
    ALTER TABLE capabilities RENAME COLUMN factory_provision_attributes_schema TO factory_output_schema;
  END IF;
END $$;

-- Rename consumer_attributes_schema -> consumer_input_schema
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'consumer_attributes_schema'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'consumer_input_schema'
  ) THEN
    ALTER TABLE capabilities RENAME COLUMN consumer_attributes_schema TO consumer_input_schema;
  END IF;
END $$;

-- Rename consumer_provision_attributes_schema -> consumer_output_schema
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'consumer_provision_attributes_schema'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'consumer_output_schema'
  ) THEN
    ALTER TABLE capabilities RENAME COLUMN consumer_provision_attributes_schema TO consumer_output_schema;
  END IF;
END $$;

-- Rename heartbeat_attributes_schema -> heartbeat_schema
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'heartbeat_attributes_schema'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'capabilities' AND column_name = 'heartbeat_schema'
  ) THEN
    ALTER TABLE capabilities RENAME COLUMN heartbeat_attributes_schema TO heartbeat_schema;
  END IF;
END $$;

-- Add comment to explain the naming convention
COMMENT ON TABLE capabilities IS 'Device capability definitions with input/output schemas for factory and consumer provisioning phases';
