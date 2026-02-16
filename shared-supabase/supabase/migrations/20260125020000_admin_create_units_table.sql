-- ============================================================================
-- Migration: 20260125020000_create_units_table.sql
-- Description: Create unified units table (replaces production_units + consumer_devices)
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Units represent manufactured products (e.g., a Saturday Hub, a Saturday Crate)
-- This unified table replaces both production_units and consumer_devices
-- A unit contains one or more devices (hardware instances)
CREATE TABLE IF NOT EXISTS units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Serial number is the primary identifier (null = unprovisioned)
  -- Format: SV-{PRODUCT_CODE}-{NUMBER} e.g., SV-HUB-000001
  serial_number VARCHAR(100) UNIQUE,

  -- Product association (from Shopify sync)
  product_id UUID REFERENCES products(id),
  variant_id UUID REFERENCES product_variants(id),

  -- Order association (for build-to-order units)
  order_id UUID REFERENCES orders(id),

  -- Factory provisioning (set during production)
  factory_provisioned_at TIMESTAMPTZ,
  factory_provisioned_by UUID REFERENCES users(id),

  -- Consumer provisioning (set by consumer app)
  user_id UUID,  -- Consumer's auth user ID
  consumer_provisioned_at TIMESTAMPTZ,
  device_name VARCHAR(255),  -- User-friendly name given by consumer
  consumer_attributes JSONB DEFAULT '{}',  -- Capability-scoped consumer config

  -- Status tracks the unit lifecycle
  -- unprovisioned -> factory_provisioned -> user_provisioned
  status VARCHAR(50) DEFAULT 'unprovisioned',

  -- Production workflow (backwards compatibility with production_units)
  production_started_at TIMESTAMPTZ,
  production_completed_at TIMESTAMPTZ,
  is_completed BOOLEAN DEFAULT false,
  qr_code_url TEXT,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES users(id)
);

COMMENT ON TABLE units IS 'Unified table for manufactured products. Replaces production_units and consumer_devices. A unit contains one or more devices (hardware instances).';

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_units_serial_number ON units(serial_number) WHERE serial_number IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_units_status ON units(status);
CREATE INDEX IF NOT EXISTS idx_units_user_id ON units(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_units_product_id ON units(product_id);
CREATE INDEX IF NOT EXISTS idx_units_order_id ON units(order_id) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_units_is_completed ON units(is_completed);
CREATE INDEX IF NOT EXISTS idx_units_factory_provisioned ON units(factory_provisioned_at) WHERE factory_provisioned_at IS NOT NULL;

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_units_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_units_updated_at ON units;
CREATE TRIGGER trigger_units_updated_at
  BEFORE UPDATE ON units
  FOR EACH ROW
  EXECUTE FUNCTION update_units_updated_at();

-- Row Level Security
ALTER TABLE units ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated employees can read all units" ON units;
DROP POLICY IF EXISTS "Employees with manage_production can manage units" ON units;
DROP POLICY IF EXISTS "Consumers can read own units" ON units;
DROP POLICY IF EXISTS "Consumers can update own units" ON units;

-- Employee read access (all authenticated employees)
CREATE POLICY "Authenticated employees can read all units"
ON units FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.is_active = true
  )
  OR user_id = auth.uid()  -- Consumers can also read their own
);

-- Employee write access (requires manage_production permission)
CREATE POLICY "Employees with manage_production can manage units"
ON units FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.id = auth.uid()
    AND u.is_active = true
    AND (u.is_admin = true OR p.name = 'manage_production')
  )
);

-- Consumer update access (only for consumer fields)
-- Note: This allows consumers to claim unclaimed units and update their own
CREATE POLICY "Consumers can update own units"
ON units FOR UPDATE
TO authenticated
USING (
  user_id = auth.uid()
  OR (user_id IS NULL AND status = 'factory_provisioned')  -- Allow claiming
)
WITH CHECK (
  user_id = auth.uid()  -- Can only set to own user_id
);
