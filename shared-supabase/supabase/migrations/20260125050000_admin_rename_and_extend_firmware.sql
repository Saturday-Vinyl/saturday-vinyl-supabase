-- ============================================================================
-- Migration: 20260125050000_rename_and_extend_firmware.sql
-- Description: Rename firmware_versions to firmware and add firmware_files for multi-SoC support
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Rename firmware_versions to firmware if not already renamed
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'firmware_versions'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'firmware'
  ) THEN
    ALTER TABLE firmware_versions RENAME TO firmware;
  END IF;
END $$;

-- Add is_critical flag for critical updates
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'firmware'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'firmware' AND column_name = 'is_critical'
  ) THEN
    ALTER TABLE firmware ADD COLUMN is_critical BOOLEAN DEFAULT false;
  END IF;
END $$;

-- Add released_at timestamp (replaces is_production_ready)
-- NULL = development, timestamp = released to production
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'firmware'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'firmware' AND column_name = 'released_at'
  ) THEN
    ALTER TABLE firmware ADD COLUMN released_at TIMESTAMPTZ;

    -- Migrate is_production_ready to released_at (use created_at as the release timestamp)
    UPDATE firmware
    SET released_at = created_at
    WHERE is_production_ready = true AND released_at IS NULL;
  END IF;
END $$;

-- Create firmware_files table for multi-SoC firmware support
-- A firmware version can have multiple binary files (one per SoC on the PCB)
-- Example: Crate v1.2.0 has esp32s3.bin (master) + esp32h2.bin
CREATE TABLE IF NOT EXISTS firmware_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Link to parent firmware version
  firmware_id UUID NOT NULL,

  -- SoC type this file is for
  soc_type VARCHAR(50) NOT NULL,  -- 'esp32', 'esp32s2', 'esp32s3', 'esp32c3', 'esp32c6', 'esp32h2'

  -- Master file is pushed via OTA, secondary files are pulled by device after update
  is_master BOOLEAN DEFAULT false,

  -- File storage
  file_url TEXT NOT NULL,
  file_sha256 TEXT,  -- SHA-256 hash for integrity verification
  file_size INTEGER,

  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(firmware_id, soc_type)
);

COMMENT ON TABLE firmware_files IS 'Binary files for multi-SoC firmware versions. Master file is pushed via OTA, secondary files are pulled by device.';

-- Add foreign key to firmware table if it exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'firmware'
  ) THEN
    -- Only add constraint if it doesn't exist
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'firmware_files_firmware_id_fkey'
    ) THEN
      ALTER TABLE firmware_files
      ADD CONSTRAINT firmware_files_firmware_id_fkey
      FOREIGN KEY (firmware_id) REFERENCES firmware(id) ON DELETE CASCADE;
    END IF;
  END IF;
END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_firmware_files_firmware_id ON firmware_files(firmware_id);
CREATE INDEX IF NOT EXISTS idx_firmware_files_soc_type ON firmware_files(soc_type);

-- Migrate existing binary_url data to firmware_files
-- Assumes single-SoC firmware, marked as master
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'firmware'
  ) AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'firmware' AND column_name = 'binary_url'
  ) THEN
    INSERT INTO firmware_files (firmware_id, soc_type, is_master, file_url, file_sha256, file_size)
    SELECT
      f.id,
      COALESCE(dt.chip_type, 'esp32s3'),  -- Default to esp32s3 if no chip_type
      true,  -- Mark as master
      f.binary_url,
      NULL,  -- sha256 not previously tracked
      f.binary_size
    FROM firmware f
    LEFT JOIN device_types dt ON dt.id = f.device_type_id
    WHERE f.binary_url IS NOT NULL
    ON CONFLICT (firmware_id, soc_type) DO NOTHING;
  END IF;
END $$;

-- Row Level Security for firmware_files
ALTER TABLE firmware_files ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read firmware_files" ON firmware_files;
DROP POLICY IF EXISTS "Admins can manage firmware_files" ON firmware_files;

CREATE POLICY "Authenticated users can read firmware_files"
ON firmware_files FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "Admins can manage firmware_files"
ON firmware_files FOR ALL
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_firmware')
  )
);

-- Add foreign key from device_types to firmware
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'firmware'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'device_types_production_firmware_id_fkey'
    ) THEN
      ALTER TABLE device_types
      ADD CONSTRAINT device_types_production_firmware_id_fkey
      FOREIGN KEY (production_firmware_id) REFERENCES firmware(id);
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'device_types_dev_firmware_id_fkey'
    ) THEN
      ALTER TABLE device_types
      ADD CONSTRAINT device_types_dev_firmware_id_fkey
      FOREIGN KEY (dev_firmware_id) REFERENCES firmware(id);
    END IF;
  END IF;
END $$;

-- Add foreign key from devices to firmware
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables WHERE table_name = 'firmware'
  ) THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint WHERE conname = 'devices_firmware_id_fkey'
    ) THEN
      ALTER TABLE devices
      ADD CONSTRAINT devices_firmware_id_fkey
      FOREIGN KEY (firmware_id) REFERENCES firmware(id);
    END IF;
  END IF;
END $$;
