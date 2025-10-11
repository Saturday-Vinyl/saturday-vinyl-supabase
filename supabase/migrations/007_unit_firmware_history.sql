-- Migration 007: Unit Firmware History
-- Created: 2025-10-10
-- Description: Create unit_firmware_history table for tracking firmware installations during production

-- Create unit_firmware_history table
CREATE TABLE IF NOT EXISTS unit_firmware_history (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  unit_id UUID NOT NULL REFERENCES production_units(id) ON DELETE CASCADE,
  device_type_id UUID NOT NULL REFERENCES device_types(id) ON DELETE RESTRICT,
  firmware_version_id UUID NOT NULL REFERENCES firmware_versions(id) ON DELETE RESTRICT,
  installed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  installed_by UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  installation_method VARCHAR(50), -- e.g., 'manual', 'esptool', 'usb-flash'
  notes TEXT
);

-- Create indexes
CREATE INDEX idx_unit_firmware_history_unit_id ON unit_firmware_history(unit_id);
CREATE INDEX idx_unit_firmware_history_device_type ON unit_firmware_history(device_type_id);
CREATE INDEX idx_unit_firmware_history_firmware_version ON unit_firmware_history(firmware_version_id);
CREATE INDEX idx_unit_firmware_history_installed_at ON unit_firmware_history(installed_at DESC);

-- Enable RLS
ALTER TABLE unit_firmware_history ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Allow all authenticated users to read firmware installation history
CREATE POLICY "Allow authenticated reads"
  ON unit_firmware_history
  FOR SELECT
  TO authenticated
  USING (true);

-- Allow authenticated users to record firmware installations
CREATE POLICY "Allow authenticated creates"
  ON unit_firmware_history
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow authenticated users to update installation records (for corrections)
CREATE POLICY "Allow authenticated updates"
  ON unit_firmware_history
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Comments for documentation
COMMENT ON TABLE unit_firmware_history IS 'Tracks firmware installations on production units';
COMMENT ON COLUMN unit_firmware_history.id IS 'Unique identifier for the firmware installation record';
COMMENT ON COLUMN unit_firmware_history.unit_id IS 'Foreign key to production_units table';
COMMENT ON COLUMN unit_firmware_history.device_type_id IS 'Foreign key to device_types table';
COMMENT ON COLUMN unit_firmware_history.firmware_version_id IS 'Foreign key to firmware_versions table';
COMMENT ON COLUMN unit_firmware_history.installed_at IS 'Timestamp when firmware was installed';
COMMENT ON COLUMN unit_firmware_history.installed_by IS 'User ID who performed the installation';
COMMENT ON COLUMN unit_firmware_history.installation_method IS 'Method used to install firmware (e.g., manual, esptool)';
COMMENT ON COLUMN unit_firmware_history.notes IS 'Optional notes about the installation';
