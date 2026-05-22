-- ============================================================================
-- Migration: 20260411120000_admin_parts_inventory.sql
-- Project: saturday-admin-app
-- Description: Create parts inventory tables, enums, view, indexes, and RLS
--              policies for BOM management and inventory tracking
-- Date: 2026-04-11
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- ENUMS
-- ============================================================================

DO $$
BEGIN
  CREATE TYPE part_type AS ENUM ('raw_material', 'component', 'sub_assembly');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE part_category AS ENUM ('wood', 'electronics', 'hardware', 'fastener', 'battery', 'packaging', 'other');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE unit_of_measure AS ENUM ('each', 'board_feet', 'linear_feet', 'meters', 'inches', 'square_feet', 'grams', 'milliliters');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE inventory_transaction_type AS ENUM ('receive', 'consume', 'build', 'adjust', 'return');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- ============================================================================
-- TABLES
-- ============================================================================

-- Parts: materials, components, and sub-assemblies used in production
CREATE TABLE IF NOT EXISTS parts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  part_number TEXT NOT NULL UNIQUE,
  description TEXT,
  part_type part_type NOT NULL,
  category part_category NOT NULL,
  unit_of_measure unit_of_measure NOT NULL,
  reorder_threshold NUMERIC,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Suppliers: vendors who provide parts
CREATE TABLE IF NOT EXISTS suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  website TEXT,
  notes TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Supplier Parts: maps parts to suppliers with SKU/barcode info
CREATE TABLE IF NOT EXISTS supplier_parts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  part_id UUID NOT NULL REFERENCES parts(id),
  supplier_id UUID NOT NULL REFERENCES suppliers(id),
  supplier_sku TEXT NOT NULL,
  barcode_value TEXT,
  barcode_format TEXT,
  unit_cost NUMERIC,
  cost_currency TEXT NOT NULL DEFAULT 'USD',
  is_preferred BOOLEAN NOT NULL DEFAULT false,
  url TEXT,
  notes TEXT,
  UNIQUE (part_id, supplier_id, supplier_sku)
);

-- Sub-Assembly Lines: components needed to build a sub-assembly part
CREATE TABLE IF NOT EXISTS sub_assembly_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_part_id UUID NOT NULL REFERENCES parts(id),
  child_part_id UUID NOT NULL REFERENCES parts(id),
  quantity NUMERIC NOT NULL,
  reference_designator TEXT,
  notes TEXT
);

-- BOM Lines: parts needed to build one unit of a product
CREATE TABLE IF NOT EXISTS bom_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id),
  part_id UUID NOT NULL REFERENCES parts(id),
  production_step_id UUID REFERENCES production_steps(id),
  quantity NUMERIC NOT NULL,
  notes TEXT
);

-- BOM Variant Overrides: substitute parts for specific product variants
CREATE TABLE IF NOT EXISTS bom_variant_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bom_line_id UUID NOT NULL REFERENCES bom_lines(id),
  variant_id UUID NOT NULL REFERENCES product_variants(id),
  part_id UUID NOT NULL REFERENCES parts(id),
  quantity NUMERIC,
  UNIQUE (bom_line_id, variant_id)
);

-- Inventory Transactions: ledger of all inventory changes
CREATE TABLE IF NOT EXISTS inventory_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  part_id UUID NOT NULL REFERENCES parts(id),
  transaction_type inventory_transaction_type NOT NULL,
  quantity NUMERIC NOT NULL,
  unit_id UUID REFERENCES units(id),
  step_completion_id UUID REFERENCES unit_step_completions(id),
  supplier_id UUID REFERENCES suppliers(id),
  build_batch_id UUID,
  reference TEXT,
  performed_by UUID NOT NULL REFERENCES auth.users(id),
  performed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- VIEW
-- ============================================================================

CREATE OR REPLACE VIEW inventory_levels AS
SELECT part_id, SUM(quantity) AS quantity_on_hand
FROM inventory_transactions
GROUP BY part_id;

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS idx_sub_assembly_lines_unique
  ON sub_assembly_lines (parent_part_id, child_part_id, COALESCE(reference_designator, ''));

CREATE UNIQUE INDEX IF NOT EXISTS idx_bom_lines_unique
  ON bom_lines (product_id, part_id, COALESCE(production_step_id, '00000000-0000-0000-0000-000000000000'));

CREATE INDEX IF NOT EXISTS idx_parts_part_number ON parts(part_number);
CREATE INDEX IF NOT EXISTS idx_parts_part_type ON parts(part_type);
CREATE INDEX IF NOT EXISTS idx_parts_category ON parts(category);
CREATE INDEX IF NOT EXISTS idx_supplier_parts_barcode ON supplier_parts(barcode_value) WHERE barcode_value IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_supplier_parts_supplier_sku ON supplier_parts(supplier_sku);
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_part_id ON inventory_transactions(part_id);
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_build_batch ON inventory_transactions(build_batch_id) WHERE build_batch_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_bom_lines_product_id ON bom_lines(product_id);
CREATE INDEX IF NOT EXISTS idx_sub_assembly_lines_parent ON sub_assembly_lines(parent_part_id);

-- ============================================================================
-- UPDATED_AT TRIGGER FOR PARTS
-- ============================================================================

CREATE OR REPLACE FUNCTION update_parts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_parts_updated_at ON parts;
CREATE TRIGGER trigger_parts_updated_at
  BEFORE UPDATE ON parts
  FOR EACH ROW
  EXECUTE FUNCTION update_parts_updated_at();

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

-- Enable RLS on all new tables
ALTER TABLE parts ENABLE ROW LEVEL SECURITY;
ALTER TABLE suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE supplier_parts ENABLE ROW LEVEL SECURITY;
ALTER TABLE sub_assembly_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE bom_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE bom_variant_overrides ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_transactions ENABLE ROW LEVEL SECURITY;

-- Parts policies
DROP POLICY IF EXISTS "Authenticated users can select parts" ON parts;
CREATE POLICY "Authenticated users can select parts"
ON parts FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert parts" ON parts;
CREATE POLICY "Authenticated users can insert parts"
ON parts FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update parts" ON parts;
CREATE POLICY "Authenticated users can update parts"
ON parts FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete parts" ON parts;
CREATE POLICY "Authenticated users can delete parts"
ON parts FOR DELETE TO authenticated USING (true);

-- Suppliers policies
DROP POLICY IF EXISTS "Authenticated users can select suppliers" ON suppliers;
CREATE POLICY "Authenticated users can select suppliers"
ON suppliers FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert suppliers" ON suppliers;
CREATE POLICY "Authenticated users can insert suppliers"
ON suppliers FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update suppliers" ON suppliers;
CREATE POLICY "Authenticated users can update suppliers"
ON suppliers FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete suppliers" ON suppliers;
CREATE POLICY "Authenticated users can delete suppliers"
ON suppliers FOR DELETE TO authenticated USING (true);

-- Supplier Parts policies
DROP POLICY IF EXISTS "Authenticated users can select supplier_parts" ON supplier_parts;
CREATE POLICY "Authenticated users can select supplier_parts"
ON supplier_parts FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert supplier_parts" ON supplier_parts;
CREATE POLICY "Authenticated users can insert supplier_parts"
ON supplier_parts FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update supplier_parts" ON supplier_parts;
CREATE POLICY "Authenticated users can update supplier_parts"
ON supplier_parts FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete supplier_parts" ON supplier_parts;
CREATE POLICY "Authenticated users can delete supplier_parts"
ON supplier_parts FOR DELETE TO authenticated USING (true);

-- Sub-Assembly Lines policies
DROP POLICY IF EXISTS "Authenticated users can select sub_assembly_lines" ON sub_assembly_lines;
CREATE POLICY "Authenticated users can select sub_assembly_lines"
ON sub_assembly_lines FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert sub_assembly_lines" ON sub_assembly_lines;
CREATE POLICY "Authenticated users can insert sub_assembly_lines"
ON sub_assembly_lines FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update sub_assembly_lines" ON sub_assembly_lines;
CREATE POLICY "Authenticated users can update sub_assembly_lines"
ON sub_assembly_lines FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete sub_assembly_lines" ON sub_assembly_lines;
CREATE POLICY "Authenticated users can delete sub_assembly_lines"
ON sub_assembly_lines FOR DELETE TO authenticated USING (true);

-- BOM Lines policies
DROP POLICY IF EXISTS "Authenticated users can select bom_lines" ON bom_lines;
CREATE POLICY "Authenticated users can select bom_lines"
ON bom_lines FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert bom_lines" ON bom_lines;
CREATE POLICY "Authenticated users can insert bom_lines"
ON bom_lines FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update bom_lines" ON bom_lines;
CREATE POLICY "Authenticated users can update bom_lines"
ON bom_lines FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete bom_lines" ON bom_lines;
CREATE POLICY "Authenticated users can delete bom_lines"
ON bom_lines FOR DELETE TO authenticated USING (true);

-- BOM Variant Overrides policies
DROP POLICY IF EXISTS "Authenticated users can select bom_variant_overrides" ON bom_variant_overrides;
CREATE POLICY "Authenticated users can select bom_variant_overrides"
ON bom_variant_overrides FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert bom_variant_overrides" ON bom_variant_overrides;
CREATE POLICY "Authenticated users can insert bom_variant_overrides"
ON bom_variant_overrides FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update bom_variant_overrides" ON bom_variant_overrides;
CREATE POLICY "Authenticated users can update bom_variant_overrides"
ON bom_variant_overrides FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete bom_variant_overrides" ON bom_variant_overrides;
CREATE POLICY "Authenticated users can delete bom_variant_overrides"
ON bom_variant_overrides FOR DELETE TO authenticated USING (true);

-- Inventory Transactions policies
DROP POLICY IF EXISTS "Authenticated users can select inventory_transactions" ON inventory_transactions;
CREATE POLICY "Authenticated users can select inventory_transactions"
ON inventory_transactions FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert inventory_transactions" ON inventory_transactions;
CREATE POLICY "Authenticated users can insert inventory_transactions"
ON inventory_transactions FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update inventory_transactions" ON inventory_transactions;
CREATE POLICY "Authenticated users can update inventory_transactions"
ON inventory_transactions FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete inventory_transactions" ON inventory_transactions;
CREATE POLICY "Authenticated users can delete inventory_transactions"
ON inventory_transactions FOR DELETE TO authenticated USING (true);
