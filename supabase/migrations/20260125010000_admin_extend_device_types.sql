-- ============================================================================
-- Migration: 20260125010000_extend_device_types.sql
-- Description: Extend device_types with SoC types, firmware references, and capabilities
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Add SoC types array to device_types
-- A PCB can contain multiple SoCs (e.g., Crate has ESP32-S3 + ESP32-H2)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_types' AND column_name = 'soc_types'
  ) THEN
    ALTER TABLE device_types ADD COLUMN soc_types TEXT[] DEFAULT '{}';
  END IF;
END $$;

-- Add master_soc column - which SoC has network connectivity
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_types' AND column_name = 'master_soc'
  ) THEN
    ALTER TABLE device_types ADD COLUMN master_soc VARCHAR(50);
  END IF;
END $$;

-- Add production firmware reference
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_types' AND column_name = 'production_firmware_id'
  ) THEN
    ALTER TABLE device_types ADD COLUMN production_firmware_id UUID;
  END IF;
END $$;

-- Add dev firmware reference
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'device_types' AND column_name = 'dev_firmware_id'
  ) THEN
    ALTER TABLE device_types ADD COLUMN dev_firmware_id UUID;
  END IF;
END $$;

-- Migrate existing chip_type to soc_types array
UPDATE device_types
SET soc_types = ARRAY[chip_type], master_soc = chip_type
WHERE chip_type IS NOT NULL
  AND (soc_types IS NULL OR soc_types = '{}');

-- Create device_type_capabilities junction table
-- Links device types to their capabilities with optional configuration
CREATE TABLE IF NOT EXISTS device_type_capabilities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_type_id UUID NOT NULL REFERENCES device_types(id) ON DELETE CASCADE,
  capability_id UUID NOT NULL REFERENCES capabilities(id) ON DELETE CASCADE,

  -- Per-device-type capability configuration
  configuration JSONB DEFAULT '{}',

  -- Ordering for UI display
  display_order INTEGER DEFAULT 0,

  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(device_type_id, capability_id)
);

COMMENT ON TABLE device_type_capabilities IS 'Junction table linking device types to their supported capabilities';

-- Indexes for device_type_capabilities
CREATE INDEX IF NOT EXISTS idx_device_type_capabilities_device_type
ON device_type_capabilities(device_type_id);

CREATE INDEX IF NOT EXISTS idx_device_type_capabilities_capability
ON device_type_capabilities(capability_id);

-- Row Level Security for device_type_capabilities
ALTER TABLE device_type_capabilities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read device_type_capabilities" ON device_type_capabilities;
DROP POLICY IF EXISTS "Admins can manage device_type_capabilities" ON device_type_capabilities;

CREATE POLICY "Authenticated users can read device_type_capabilities"
ON device_type_capabilities FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admins can manage device_type_capabilities"
ON device_type_capabilities FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_products')
  )
);

-- Seed device_type_capabilities for existing device types
-- Link Hub to wifi, thread, cloud, rfid capabilities
INSERT INTO device_type_capabilities (device_type_id, capability_id, display_order)
SELECT dt.id, c.id, c_order.ord
FROM device_types dt
CROSS JOIN LATERAL (
  SELECT id, name,
    CASE name
      WHEN 'wifi' THEN 1
      WHEN 'cloud' THEN 2
      WHEN 'thread' THEN 3
      WHEN 'rfid' THEN 4
    END as ord
  FROM capabilities
  WHERE name IN ('wifi', 'cloud', 'thread', 'rfid')
) c(id, name, ord)
CROSS JOIN LATERAL (SELECT c.ord as ord) c_order
WHERE LOWER(dt.name) LIKE '%hub%'
ON CONFLICT (device_type_id, capability_id) DO NOTHING;

-- Link Crate to thread, rfid, led, environment, motion capabilities
INSERT INTO device_type_capabilities (device_type_id, capability_id, display_order)
SELECT dt.id, c.id, c_order.ord
FROM device_types dt
CROSS JOIN LATERAL (
  SELECT id, name,
    CASE name
      WHEN 'thread' THEN 1
      WHEN 'rfid' THEN 2
      WHEN 'led' THEN 3
      WHEN 'environment' THEN 4
      WHEN 'motion' THEN 5
    END as ord
  FROM capabilities
  WHERE name IN ('thread', 'rfid', 'led', 'environment', 'motion')
) c(id, name, ord)
CROSS JOIN LATERAL (SELECT c.ord as ord) c_order
WHERE LOWER(dt.name) LIKE '%crate%'
ON CONFLICT (device_type_id, capability_id) DO NOTHING;
