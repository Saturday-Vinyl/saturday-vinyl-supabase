-- Migration 006: Firmware Versions
-- Created: 2025-10-10
-- Description: Create firmware_versions table for managing device firmware binaries

-- Create firmware_versions table
CREATE TABLE IF NOT EXISTS firmware_versions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  device_type_id UUID NOT NULL REFERENCES device_types(id) ON DELETE CASCADE,
  version VARCHAR(50) NOT NULL,
  release_notes TEXT,
  binary_url TEXT NOT NULL,
  binary_filename VARCHAR(255) NOT NULL,
  binary_size BIGINT,
  is_production_ready BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),
  UNIQUE(device_type_id, version)
);

-- Create indexes
CREATE INDEX idx_firmware_versions_device_type ON firmware_versions(device_type_id);
CREATE INDEX idx_firmware_versions_production ON firmware_versions(is_production_ready);
CREATE INDEX idx_firmware_versions_version ON firmware_versions(version);
CREATE INDEX idx_firmware_versions_created_at ON firmware_versions(created_at DESC);

-- Enable RLS
ALTER TABLE firmware_versions ENABLE ROW LEVEL SECURITY;

-- RLS Policies

-- Allow all authenticated users to read firmware versions
CREATE POLICY "Allow authenticated reads"
  ON firmware_versions
  FOR SELECT
  TO authenticated
  USING (true);

-- Allow authenticated users to create firmware versions
CREATE POLICY "Allow authenticated creates"
  ON firmware_versions
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- Allow authenticated users to update firmware versions
CREATE POLICY "Allow authenticated updates"
  ON firmware_versions
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

-- Allow authenticated users to delete firmware versions
CREATE POLICY "Allow authenticated deletes"
  ON firmware_versions
  FOR DELETE
  TO authenticated
  USING (true);

-- Comments for documentation
COMMENT ON TABLE firmware_versions IS 'Firmware versions for device types with binary storage references';
COMMENT ON COLUMN firmware_versions.id IS 'Unique identifier for the firmware version';
COMMENT ON COLUMN firmware_versions.device_type_id IS 'Foreign key to device_types table';
COMMENT ON COLUMN firmware_versions.version IS 'Semantic version string (e.g., 1.2.3)';
COMMENT ON COLUMN firmware_versions.release_notes IS 'Optional release notes describing changes';
COMMENT ON COLUMN firmware_versions.binary_url IS 'Supabase storage URL to the firmware binary file';
COMMENT ON COLUMN firmware_versions.binary_filename IS 'Original filename of the uploaded binary';
COMMENT ON COLUMN firmware_versions.binary_size IS 'Size of the binary file in bytes';
COMMENT ON COLUMN firmware_versions.is_production_ready IS 'Whether this version is approved for production use';
COMMENT ON COLUMN firmware_versions.created_at IS 'Timestamp when the firmware version was uploaded';
COMMENT ON COLUMN firmware_versions.created_by IS 'User ID who uploaded this firmware version';
