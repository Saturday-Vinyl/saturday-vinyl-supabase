-- ============================================================================
-- Migration: 20260125080000_add_short_name_to_products.sql
-- Description: Add short_name column to products for device provisioning
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- The short_name is the human-friendly product name used during factory provisioning.
-- Example: "Crate" instead of "Saturday Crate"
-- This name is sent to devices during factory_provision and stored in NVS.
-- The firmware uses it to construct identifiers like:
--   - BLE advertising: "Saturday {short_name} {serial_last_4}" → "Saturday Crate 0001"
--   - mDNS hostname: "saturday-{short_name}-{serial_last_4}" → "saturday-crate-0001"

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'short_name'
  ) THEN
    ALTER TABLE products ADD COLUMN short_name VARCHAR(50);

    -- Populate short_name from existing product names by removing "Saturday " prefix
    UPDATE products
    SET short_name = CASE
      WHEN name LIKE 'Saturday %' THEN SUBSTRING(name FROM 10)
      ELSE name
    END
    WHERE short_name IS NULL;
  END IF;
END $$;

COMMENT ON COLUMN products.short_name IS 'Short product name for device provisioning (e.g., "Crate" not "Saturday Crate"). Used in BLE advertising and mDNS hostnames.';
