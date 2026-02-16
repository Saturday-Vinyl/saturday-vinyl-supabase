-- ============================================================================
-- Migration: 20260125000000_create_capabilities_table.sql
-- Description: Create capabilities table for dynamic device capability definitions
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Capabilities define configurable features of Saturday devices
-- Each capability specifies attribute schemas for factory/consumer provisioning,
-- heartbeat data, and available tests.
CREATE TABLE IF NOT EXISTS capabilities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name VARCHAR(100) UNIQUE NOT NULL,        -- e.g., "wifi", "thread", "rfid"
  display_name VARCHAR(100) NOT NULL,       -- e.g., "Wi-Fi", "Thread", "RFID"
  description TEXT,

  -- JSON Schema for provisioning attributes
  factory_attributes_schema JSONB DEFAULT '{}',
  factory_provision_attributes_schema JSONB DEFAULT '{}',
  consumer_attributes_schema JSONB DEFAULT '{}',
  consumer_provision_attributes_schema JSONB DEFAULT '{}',

  -- Heartbeat telemetry schema
  heartbeat_attributes_schema JSONB DEFAULT '{}',

  -- Test definitions with parameter and result schemas
  tests JSONB DEFAULT '[]',

  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add comment describing the table
COMMENT ON TABLE capabilities IS 'Dynamic capability definitions for Saturday devices. Each capability defines attribute schemas and available tests.';

-- Indexes for capability lookups
CREATE INDEX IF NOT EXISTS idx_capabilities_name ON capabilities(name);
CREATE INDEX IF NOT EXISTS idx_capabilities_active ON capabilities(is_active) WHERE is_active = true;

-- Trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_capabilities_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_capabilities_updated_at ON capabilities;
CREATE TRIGGER trigger_capabilities_updated_at
  BEFORE UPDATE ON capabilities
  FOR EACH ROW
  EXECUTE FUNCTION update_capabilities_updated_at();

-- Seed standard capabilities
INSERT INTO capabilities (name, display_name, description, factory_attributes_schema, consumer_attributes_schema, heartbeat_attributes_schema, tests)
VALUES
  (
    'wifi',
    'Wi-Fi',
    'Wi-Fi network connectivity',
    '{"type": "object", "properties": {"ssid": {"type": "string", "maxLength": 32}, "password": {"type": "string", "maxLength": 64}}}',
    '{"type": "object", "properties": {"ssid": {"type": "string", "maxLength": 32}, "password": {"type": "string", "maxLength": 64}}, "required": ["ssid", "password"]}',
    '{"type": "object", "properties": {"connected": {"type": "boolean"}, "ssid": {"type": "string"}, "rssi": {"type": "integer"}, "ip_address": {"type": "string"}}}',
    '[{"name": "connect", "display_name": "Connect to Wi-Fi", "parameters_schema": {"type": "object", "properties": {"ssid": {"type": "string"}, "password": {"type": "string"}, "timeout_ms": {"type": "integer", "default": 30000}}}}]'
  ),
  (
    'thread',
    'Thread',
    'Thread mesh network connectivity',
    '{"type": "object", "properties": {"network_name": {"type": "string", "maxLength": 16}, "pan_id": {"type": "integer"}, "channel": {"type": "integer", "minimum": 11, "maximum": 26}, "network_key": {"type": "string", "pattern": "^[0-9a-fA-F]{32}$"}}}',
    '{"type": "object", "properties": {"network_name": {"type": "string"}, "network_key": {"type": "string"}}}',
    '{"type": "object", "properties": {"connected": {"type": "boolean"}, "role": {"type": "string", "enum": ["disabled", "detached", "child", "router", "leader"]}}}',
    '[{"name": "join", "display_name": "Join Thread Network", "parameters_schema": {"type": "object", "properties": {"timeout_ms": {"type": "integer", "default": 60000}}}}]'
  ),
  (
    'cloud',
    'Cloud',
    'Cloud backend connectivity',
    '{"type": "object", "properties": {"cloud_url": {"type": "string", "format": "uri"}, "cloud_anon_key": {"type": "string"}}, "required": ["cloud_url", "cloud_anon_key"]}',
    '{}',
    '{"type": "object", "properties": {"connected": {"type": "boolean"}, "latency_ms": {"type": "integer"}}}',
    '[{"name": "ping", "display_name": "Test Cloud Connection", "parameters_schema": {"type": "object", "properties": {"timeout_ms": {"type": "integer", "default": 15000}}}}]'
  ),
  (
    'rfid',
    'RFID',
    'UHF RFID tag reading',
    '{"type": "object", "properties": {"power_dbm": {"type": "integer", "minimum": 0, "maximum": 30, "default": 20}}}',
    '{}',
    '{"type": "object", "properties": {"module_firmware": {"type": "string"}, "last_scan_count": {"type": "integer"}}}',
    '[{"name": "scan", "display_name": "Scan for Tags", "parameters_schema": {"type": "object", "properties": {"duration_ms": {"type": "integer", "default": 5000}}}}]'
  ),
  (
    'led',
    'LED Strip',
    'Addressable LED strip control',
    '{"type": "object", "properties": {"led_count": {"type": "integer", "minimum": 1}, "led_type": {"type": "string", "enum": ["SK6812", "WS2812B", "APA102"]}}}',
    '{}',
    '{}',
    '[{"name": "pattern", "display_name": "Test LED Pattern", "parameters_schema": {"type": "object", "properties": {"pattern": {"type": "string", "enum": ["rainbow", "solid", "chase"], "default": "rainbow"}}}}]'
  ),
  (
    'environment',
    'Environment Sensor',
    'Temperature and humidity sensing',
    '{}',
    '{}',
    '{"type": "object", "properties": {"temperature_c": {"type": "number"}, "humidity_pct": {"type": "number"}, "in_safe_range": {"type": "boolean"}}}',
    '[{"name": "read", "display_name": "Read Environment", "parameters_schema": {"type": "object", "properties": {}}}]'
  ),
  (
    'motion',
    'Motion Sensor',
    'Accelerometer/motion detection',
    '{}',
    '{}',
    '{}',
    '[{"name": "detect", "display_name": "Detect Motion", "parameters_schema": {"type": "object", "properties": {"timeout_ms": {"type": "integer", "default": 30000}}}}]'
  ),
  (
    'button',
    'Button',
    'Physical button input',
    '{}',
    '{}',
    '{}',
    '[{"name": "press", "display_name": "Wait for Button Press", "parameters_schema": {"type": "object", "properties": {"timeout_ms": {"type": "integer", "default": 30000}}}}]'
  )
ON CONFLICT (name) DO NOTHING;

-- Row Level Security
ALTER TABLE capabilities ENABLE ROW LEVEL SECURITY;

-- Drop existing policies before creating
DROP POLICY IF EXISTS "Authenticated users can read capabilities" ON capabilities;
DROP POLICY IF EXISTS "Admins can manage capabilities" ON capabilities;

-- Read policy for authenticated users
CREATE POLICY "Authenticated users can read capabilities"
ON capabilities FOR SELECT
TO authenticated
USING (true);

-- Write policy for admins (users with manage_products permission or is_admin)
CREATE POLICY "Admins can manage capabilities"
ON capabilities FOR ALL
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
