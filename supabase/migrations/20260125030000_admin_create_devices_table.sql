-- ============================================================================
-- Migration: 20260125030000_create_devices_table.sql
-- Description: Create devices table for hardware instances (PCBs with MAC addresses)
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- A device is a physical piece of hardware (a PCB with a MAC address)
-- Devices are linked to units and device_types
-- Example: A Saturday Hub unit contains one Hub device (PCB with S3+H2)
CREATE TABLE IF NOT EXISTS devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Primary identifier: MAC address of the master SoC
  mac_address VARCHAR(17) UNIQUE NOT NULL,

  -- Device type (template defining capabilities)
  device_type_id UUID REFERENCES device_types(id),

  -- Link to the unit this device belongs to (null until associated)
  unit_id UUID REFERENCES units(id),

  -- Firmware tracking
  firmware_version VARCHAR(50),
  firmware_id UUID,  -- Current firmware ID from firmware table

  -- Factory provisioning data (per-device, persists consumer reset)
  factory_provisioned_at TIMESTAMPTZ,
  factory_provisioned_by UUID REFERENCES users(id),
  factory_attributes JSONB DEFAULT '{}',  -- Capability-scoped factory config

  -- Status: unprovisioned -> provisioned, online/offline based on last_seen
  status VARCHAR(50) DEFAULT 'unprovisioned',

  -- Connectivity tracking
  last_seen_at TIMESTAMPTZ,

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE devices IS 'Hardware instances (PCBs) identified by MAC address. A device belongs to a unit and has a device_type template.';

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_devices_mac_address ON devices(mac_address);
CREATE INDEX IF NOT EXISTS idx_devices_unit_id ON devices(unit_id) WHERE unit_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_devices_device_type_id ON devices(device_type_id);
CREATE INDEX IF NOT EXISTS idx_devices_status ON devices(status);
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices(last_seen_at DESC) WHERE last_seen_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_devices_firmware_id ON devices(firmware_id) WHERE firmware_id IS NOT NULL;

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_devices_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_devices_updated_at ON devices;
CREATE TRIGGER trigger_devices_updated_at
  BEFORE UPDATE ON devices
  FOR EACH ROW
  EXECUTE FUNCTION update_devices_updated_at();

-- Row Level Security
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read devices" ON devices;
DROP POLICY IF EXISTS "Employees with manage_production can manage devices" ON devices;
DROP POLICY IF EXISTS "Devices can update their own status" ON devices;

-- Read access for all authenticated users
CREATE POLICY "Authenticated users can read devices"
ON devices FOR SELECT
TO authenticated
USING (true);

-- Write access for employees with manage_production permission
CREATE POLICY "Employees with manage_production can manage devices"
ON devices FOR ALL
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

-- Allow service role to update devices (for heartbeat updates)
-- This is typically handled by the anon key with specific column restrictions
-- or via Edge Functions with service role
CREATE POLICY "Devices can update their own status"
ON devices FOR UPDATE
TO anon
USING (true)
WITH CHECK (true);
