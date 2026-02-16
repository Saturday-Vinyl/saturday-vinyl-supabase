-- ============================================================================
-- Migration: 20260107000000_thread_credentials.sql
-- Description: Add Thread Border Router credentials storage for Hub provisioning
-- Date: 2026-01-07
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================
--
-- During factory serial provisioning of Saturday Vinyl Hubs, Thread Border Router
-- credentials are captured via the get_status response. These credentials need to
-- be stored so the mobile app can retrieve them when provisioning crates (ESP32-H2
-- devices) to join the hub's Thread network.
--
-- The thread object from get_status contains:
-- {
--   "thread": {
--     "network_name": "SaturdayVinyl",
--     "pan_id": 21334,
--     "channel": 15,
--     "network_key": "a1b2c3d4e5f6789012345678abcdef12",  -- 32 hex chars
--     "extended_pan_id": "0123456789abcdef",              -- 16 hex chars
--     "mesh_local_prefix": "fd00000000000000",            -- 16 hex chars
--     "pskc": "fedcba9876543210fedcba9876543210"          -- 32 hex chars
--   }
-- }
-- ============================================================================

-- ============================================================================
-- Create Thread Credentials Table
-- ============================================================================

CREATE TABLE IF NOT EXISTS thread_credentials (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- Link to the production unit (hub) that owns these credentials
  unit_id UUID NOT NULL REFERENCES production_units(id) ON DELETE CASCADE,

  -- Thread network identification
  network_name VARCHAR(16) NOT NULL,  -- Thread network name (max 16 chars)
  pan_id INTEGER NOT NULL,            -- PAN ID (16-bit, 0-65534)
  channel INTEGER NOT NULL,           -- Thread channel (11-26)

  -- Thread network security credentials (stored as hex strings)
  network_key VARCHAR(32) NOT NULL,       -- 128-bit key as 32 hex chars
  extended_pan_id VARCHAR(16) NOT NULL,   -- 64-bit extended PAN ID as 16 hex chars
  mesh_local_prefix VARCHAR(16) NOT NULL, -- 64-bit mesh local prefix as 16 hex chars
  pskc VARCHAR(32) NOT NULL,              -- Pre-Shared Key for Commissioner as 32 hex chars

  -- Metadata
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  -- Each unit can only have one set of Thread credentials
  UNIQUE(unit_id)
);

-- ============================================================================
-- Constraints (Idempotent - check if constraint exists before adding)
-- ============================================================================

DO $$
BEGIN
  -- Validate PAN ID range (0-65534, 65535 is broadcast)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_pan_id' AND conrelid = 'thread_credentials'::regclass
  ) THEN
    ALTER TABLE thread_credentials
      ADD CONSTRAINT valid_pan_id CHECK (pan_id >= 0 AND pan_id <= 65534);
  END IF;

  -- Validate Thread channel range (11-26 for 2.4GHz)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_channel' AND conrelid = 'thread_credentials'::regclass
  ) THEN
    ALTER TABLE thread_credentials
      ADD CONSTRAINT valid_channel CHECK (channel >= 11 AND channel <= 26);
  END IF;

  -- Validate network_key hex string length
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_network_key_length' AND conrelid = 'thread_credentials'::regclass
  ) THEN
    ALTER TABLE thread_credentials
      ADD CONSTRAINT valid_network_key_length CHECK (
        LENGTH(network_key) = 32 AND network_key ~ '^[0-9a-fA-F]+$'
      );
  END IF;

  -- Validate extended_pan_id hex string length
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_extended_pan_id_length' AND conrelid = 'thread_credentials'::regclass
  ) THEN
    ALTER TABLE thread_credentials
      ADD CONSTRAINT valid_extended_pan_id_length CHECK (
        LENGTH(extended_pan_id) = 16 AND extended_pan_id ~ '^[0-9a-fA-F]+$'
      );
  END IF;

  -- Validate mesh_local_prefix hex string length
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_mesh_local_prefix_length' AND conrelid = 'thread_credentials'::regclass
  ) THEN
    ALTER TABLE thread_credentials
      ADD CONSTRAINT valid_mesh_local_prefix_length CHECK (
        LENGTH(mesh_local_prefix) = 16 AND mesh_local_prefix ~ '^[0-9a-fA-F]+$'
      );
  END IF;

  -- Validate pskc hex string length
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'valid_pskc_length' AND conrelid = 'thread_credentials'::regclass
  ) THEN
    ALTER TABLE thread_credentials
      ADD CONSTRAINT valid_pskc_length CHECK (
        LENGTH(pskc) = 32 AND pskc ~ '^[0-9a-fA-F]+$'
      );
  END IF;
END $$;

-- ============================================================================
-- Indexes (Idempotent with IF NOT EXISTS)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_thread_credentials_unit_id ON thread_credentials(unit_id);

-- ============================================================================
-- Row Level Security
-- ============================================================================

ALTER TABLE thread_credentials ENABLE ROW LEVEL SECURITY;

-- RLS Policies (Idempotent - drop if exists, then create)
DROP POLICY IF EXISTS "Allow authenticated reads on thread_credentials" ON thread_credentials;
CREATE POLICY "Allow authenticated reads on thread_credentials"
  ON thread_credentials
  FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Allow authenticated creates on thread_credentials" ON thread_credentials;
CREATE POLICY "Allow authenticated creates on thread_credentials"
  ON thread_credentials
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated updates on thread_credentials" ON thread_credentials;
CREATE POLICY "Allow authenticated updates on thread_credentials"
  ON thread_credentials
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated deletes on thread_credentials" ON thread_credentials;
CREATE POLICY "Allow authenticated deletes on thread_credentials"
  ON thread_credentials
  FOR DELETE
  TO authenticated
  USING (true);

-- ============================================================================
-- Updated At Trigger
-- ============================================================================

-- Create trigger function if it doesn't exist (using CREATE OR REPLACE)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger (idempotent - drop if exists, then create)
DROP TRIGGER IF EXISTS update_thread_credentials_updated_at ON thread_credentials;
CREATE TRIGGER update_thread_credentials_updated_at
  BEFORE UPDATE ON thread_credentials
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Comments (Idempotent - COMMENT ON is always safe to repeat)
-- ============================================================================

COMMENT ON TABLE thread_credentials IS
  'Thread Border Router credentials captured during Hub provisioning. Used by mobile app to provision crates to join the Thread network.';

COMMENT ON COLUMN thread_credentials.unit_id IS
  'Reference to the production unit (Hub) that owns this Thread network';

COMMENT ON COLUMN thread_credentials.network_name IS
  'Thread network name (max 16 characters)';

COMMENT ON COLUMN thread_credentials.pan_id IS
  'Thread PAN ID (Personal Area Network identifier, 16-bit value 0-65534)';

COMMENT ON COLUMN thread_credentials.channel IS
  'Thread radio channel (11-26 for 2.4GHz band)';

COMMENT ON COLUMN thread_credentials.network_key IS
  'Thread Network Key - 128-bit AES key stored as 32 hex characters';

COMMENT ON COLUMN thread_credentials.extended_pan_id IS
  'Extended PAN ID - 64-bit identifier stored as 16 hex characters';

COMMENT ON COLUMN thread_credentials.mesh_local_prefix IS
  'Mesh-Local Prefix - 64-bit ULA prefix stored as 16 hex characters';

COMMENT ON COLUMN thread_credentials.pskc IS
  'Pre-Shared Key for Commissioner - 128-bit key stored as 32 hex characters';

-- ============================================================================
-- Completion Message
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 20260107000000_thread_credentials completed successfully!';
    RAISE NOTICE 'Changes:';
    RAISE NOTICE '  - Created thread_credentials table (if not exists)';
    RAISE NOTICE '  - Added constraints for PAN ID, channel, and hex string validation';
    RAISE NOTICE '  - Added RLS policies for authenticated access';
    RAISE NOTICE '  - Added updated_at trigger';
END $$;
