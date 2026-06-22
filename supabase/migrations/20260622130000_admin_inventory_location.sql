-- ============================================================================
-- Migration: 20260622130000_admin_inventory_location.sql
-- Project: saturday-admin-app
-- Description: Make inventory location-aware: add location_id to the ledger, a
--              'transfer' transaction type, a per-location levels view, and a
--              tracked drawer-checkout (custody) table. Existing inventory_levels
--              view is left intact (now sums across all locations incl. NULL).
-- Date: 2026-06-22
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- ENUM: add 'transfer' (transfers are recorded as two balanced ledger rows --
-- negative at the source location, positive at the destination)
-- ============================================================================

DO $$
BEGIN
  ALTER TYPE inventory_transaction_type ADD VALUE 'transfer';
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- LEDGER: location_id (nullable -> NULL is the "Unassigned" bucket)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'inventory_transactions' AND column_name = 'location_id'
  ) THEN
    ALTER TABLE inventory_transactions
      ADD COLUMN location_id UUID REFERENCES storage_locations(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_inventory_transactions_location
  ON inventory_transactions(location_id) WHERE location_id IS NOT NULL;

-- ============================================================================
-- VIEW: per-location on-hand quantities (existing inventory_levels unchanged)
-- ============================================================================

CREATE OR REPLACE VIEW inventory_levels_by_location AS
SELECT part_id, location_id, SUM(quantity) AS quantity_on_hand
FROM inventory_transactions
GROUP BY part_id, location_id;

-- ============================================================================
-- TABLE: location_checkouts (tracked custody for removable bins/drawers)
-- ============================================================================

CREATE TABLE IF NOT EXISTS location_checkouts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_id UUID NOT NULL REFERENCES storage_locations(id),
  checked_out_by UUID NOT NULL REFERENCES auth.users(id),
  checked_out_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  returned_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'returned')),
  notes TEXT
);

-- At most one open checkout per drawer at a time.
CREATE UNIQUE INDEX IF NOT EXISTS idx_location_checkouts_one_open
  ON location_checkouts(location_id) WHERE returned_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_location_checkouts_location
  ON location_checkouts(location_id);

-- ============================================================================
-- ROW LEVEL SECURITY (open to authenticated, matching the parts-inventory domain)
-- ============================================================================

ALTER TABLE location_checkouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can select location_checkouts" ON location_checkouts;
CREATE POLICY "Authenticated users can select location_checkouts"
ON location_checkouts FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert location_checkouts" ON location_checkouts;
CREATE POLICY "Authenticated users can insert location_checkouts"
ON location_checkouts FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update location_checkouts" ON location_checkouts;
CREATE POLICY "Authenticated users can update location_checkouts"
ON location_checkouts FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete location_checkouts" ON location_checkouts;
CREATE POLICY "Authenticated users can delete location_checkouts"
ON location_checkouts FOR DELETE TO authenticated USING (true);
