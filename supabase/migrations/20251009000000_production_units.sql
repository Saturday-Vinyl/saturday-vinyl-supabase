-- Migration 005: Production Units
-- Created: 2025-10-09
-- Description: Create production_units and unit_step_completions tables
-- Idempotent: Yes - safe to run multiple times

-- Create production_units table
CREATE TABLE IF NOT EXISTS production_units (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  uuid UUID UNIQUE NOT NULL DEFAULT uuid_generate_v4(),
  unit_id VARCHAR(100) UNIQUE NOT NULL,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
  variant_id UUID NOT NULL REFERENCES product_variants(id) ON DELETE RESTRICT,
  shopify_order_id VARCHAR(255), -- Shopify order ID (optional, for reference only)
  shopify_order_number VARCHAR(50), -- Human-readable order number (e.g., #1001)
  customer_name VARCHAR(255), -- Customer name for display (cached from Shopify)
  current_owner_id UUID REFERENCES users(id) ON DELETE SET NULL,
  qr_code_url TEXT NOT NULL,
  production_started_at TIMESTAMP WITH TIME ZONE,
  production_completed_at TIMESTAMP WITH TIME ZONE,
  is_completed BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT
);

-- Create unit_step_completions table
CREATE TABLE IF NOT EXISTS unit_step_completions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  unit_id UUID NOT NULL REFERENCES production_units(id) ON DELETE CASCADE,
  step_id UUID NOT NULL REFERENCES production_steps(id) ON DELETE CASCADE,
  completed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  notes TEXT,
  UNIQUE(unit_id, step_id)
);

-- Create indexes for production_units
CREATE INDEX IF NOT EXISTS idx_production_units_uuid ON production_units(uuid);
CREATE INDEX IF NOT EXISTS idx_production_units_unit_id ON production_units(unit_id);
CREATE INDEX IF NOT EXISTS idx_production_units_product_id ON production_units(product_id);
CREATE INDEX IF NOT EXISTS idx_production_units_variant_id ON production_units(variant_id);
CREATE INDEX IF NOT EXISTS idx_production_units_shopify_order_id ON production_units(shopify_order_id);
CREATE INDEX IF NOT EXISTS idx_production_units_is_completed ON production_units(is_completed);
CREATE INDEX IF NOT EXISTS idx_production_units_created_at ON production_units(created_at);

-- Create indexes for unit_step_completions
CREATE INDEX IF NOT EXISTS idx_unit_step_completions_unit_id ON unit_step_completions(unit_id);
CREATE INDEX IF NOT EXISTS idx_unit_step_completions_step_id ON unit_step_completions(step_id);
CREATE INDEX IF NOT EXISTS idx_unit_step_completions_completed_by ON unit_step_completions(completed_by);

-- Enable RLS
ALTER TABLE production_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE unit_step_completions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for production_units

-- Allow authenticated users to read all production units
DROP POLICY IF EXISTS "Allow authenticated reads on production_units" ON production_units;
CREATE POLICY "Allow authenticated reads on production_units"
  ON production_units
  FOR SELECT
  TO authenticated
  USING (true);

-- Allow authenticated users to create production units
DROP POLICY IF EXISTS "Allow authenticated creates on production_units" ON production_units;
CREATE POLICY "Allow authenticated creates on production_units"
  ON production_units
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow authenticated users to update production units
DROP POLICY IF EXISTS "Allow authenticated updates on production_units" ON production_units;
CREATE POLICY "Allow authenticated updates on production_units"
  ON production_units
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Allow authenticated users to delete production units
DROP POLICY IF EXISTS "Allow authenticated deletes on production_units" ON production_units;
CREATE POLICY "Allow authenticated deletes on production_units"
  ON production_units
  FOR DELETE
  TO authenticated
  USING (true);

-- RLS Policies for unit_step_completions

-- Allow authenticated users to read all step completions
DROP POLICY IF EXISTS "Allow authenticated reads on unit_step_completions" ON unit_step_completions;
CREATE POLICY "Allow authenticated reads on unit_step_completions"
  ON unit_step_completions
  FOR SELECT
  TO authenticated
  USING (true);

-- Allow authenticated users to create step completions
DROP POLICY IF EXISTS "Allow authenticated creates on unit_step_completions" ON unit_step_completions;
CREATE POLICY "Allow authenticated creates on unit_step_completions"
  ON unit_step_completions
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow authenticated users to update step completions
DROP POLICY IF EXISTS "Allow authenticated updates on unit_step_completions" ON unit_step_completions;
CREATE POLICY "Allow authenticated updates on unit_step_completions"
  ON unit_step_completions
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Allow authenticated users to delete step completions
DROP POLICY IF EXISTS "Allow authenticated deletes on unit_step_completions" ON unit_step_completions;
CREATE POLICY "Allow authenticated deletes on unit_step_completions"
  ON unit_step_completions
  FOR DELETE
  TO authenticated
  USING (true);

-- Comments for documentation
COMMENT ON TABLE production_units IS 'Individual production units being manufactured';
COMMENT ON COLUMN production_units.id IS 'Unique identifier for the production unit';
COMMENT ON COLUMN production_units.uuid IS 'UUID used in QR codes for scanning';
COMMENT ON COLUMN production_units.unit_id IS 'Human-readable unit ID (format: SV-{PRODUCT_CODE}-{SEQUENCE})';
COMMENT ON COLUMN production_units.product_id IS 'Reference to the product being manufactured';
COMMENT ON COLUMN production_units.variant_id IS 'Reference to the specific product variant';
COMMENT ON COLUMN production_units.shopify_order_id IS 'Shopify order ID (optional, for reference only - not a foreign key)';
COMMENT ON COLUMN production_units.shopify_order_number IS 'Human-readable Shopify order number (e.g., #1001)';
COMMENT ON COLUMN production_units.customer_name IS 'Customer name cached from Shopify for display purposes';
COMMENT ON COLUMN production_units.current_owner_id IS 'User currently responsible for the unit';
COMMENT ON COLUMN production_units.qr_code_url IS 'URL to the QR code image in storage';
COMMENT ON COLUMN production_units.production_started_at IS 'Timestamp when production started (first step completed)';
COMMENT ON COLUMN production_units.production_completed_at IS 'Timestamp when all steps were completed';
COMMENT ON COLUMN production_units.is_completed IS 'Whether all production steps are complete';
COMMENT ON COLUMN production_units.created_at IS 'Timestamp when the unit was created';
COMMENT ON COLUMN production_units.created_by IS 'User who created the unit';

COMMENT ON TABLE unit_step_completions IS 'Completed production steps for units';
COMMENT ON COLUMN unit_step_completions.id IS 'Unique identifier for the completion record';
COMMENT ON COLUMN unit_step_completions.unit_id IS 'Reference to the production unit';
COMMENT ON COLUMN unit_step_completions.step_id IS 'Reference to the production step that was completed';
COMMENT ON COLUMN unit_step_completions.completed_at IS 'Timestamp when the step was completed';
COMMENT ON COLUMN unit_step_completions.completed_by IS 'User who completed the step';
COMMENT ON COLUMN unit_step_completions.notes IS 'Optional notes about the step completion';
