-- ============================================================================
-- Migration: 20260511180000_firmware_thread_networks.sql
-- Project: sv-hub-firmware
-- Description: Cloud-canonical Thread network credentials and per-device
--              session tokens. Supersedes the unused thread_credentials table.
-- Date: 2026-05-11
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================
--
-- Architectural background:
--
-- Thread network credentials previously lived only in H2 NVS, were generated
-- autonomously on first boot, and could be wiped by H2 OTA. Multi-Hub mesh
-- deployments were impossible because every Hub would generate its own keys.
--
-- This migration introduces:
--
--   1. thread_networks - one row per user account. Holds the user's Thread
--      mesh credentials. Sensitive columns (network_key, ext_pan_id,
--      mesh_local_prefix, pskc) are AES-256-GCM ciphertext produced by edge
--      functions using a key from the THREAD_ENCRYPTION_KEY environment
--      variable. The database never sees plaintext.
--
--   2. device_sessions - per-device opaque access/refresh tokens issued by
--      the adopt_device edge function at Hub adoption. The Hub uses these
--      tokens (instead of the shared anonymous key) for authenticated cloud
--      calls to edge functions like get_thread_credentials. Heartbeats and
--      Realtime continue using the anonymous key.
--
-- Replaced surfaces:
--
--   - DROP TABLE thread_credentials (the 2026-01-07 per-unit, plaintext
--     attempt at the same problem; empty in production, no firmware refs).
--   - Edge functions claim-unit and unclaim-unit collapse into adopt_device
--     and unadopt_device respectively (handled outside this migration).
--
-- Full design: .context/thread-credential-architecture.md in the firmware
-- repo (saturday-player-hub).
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Drop the legacy thread_credentials table.
--
-- This table was added 2026-01-07 as an earlier attempt at cloud-side Thread
-- credentials. It is keyed by unit_id, stores credentials in plaintext, has
-- `USING (true)` RLS (any authenticated user can read any row), and is never
-- written to by firmware. Confirmed empty in production.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS thread_credentials CASCADE;


-- ----------------------------------------------------------------------------
-- thread_networks: one Thread mesh per user account.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS thread_networks (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                     uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

  -- Plaintext fields. PAN ID and channel are observable on-air; network_name
  -- is aesthetic. Encrypting them adds cost without security benefit.
  network_name                text NOT NULL,
  pan_id                      integer NOT NULL,
  channel                     integer NOT NULL,

  -- Encrypted credentials. Ciphertext is AES-256-GCM produced by the
  -- adopt_device edge function. The DB stores opaque bytea; only the edge
  -- functions, holding the THREAD_ENCRYPTION_KEY env var, can decrypt.
  network_key_encrypted       bytea NOT NULL,
  extended_pan_id_encrypted   bytea NOT NULL,
  mesh_local_prefix_encrypted bytea NOT NULL,
  pskc_encrypted              bytea NOT NULL,

  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now(),
  rotated_at                  timestamptz
);

-- Range constraints (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'thread_networks_valid_pan_id'
  ) THEN
    ALTER TABLE thread_networks
      ADD CONSTRAINT thread_networks_valid_pan_id
      CHECK (pan_id >= 0 AND pan_id <= 65534);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'thread_networks_valid_channel'
  ) THEN
    ALTER TABLE thread_networks
      ADD CONSTRAINT thread_networks_valid_channel
      CHECK (channel >= 11 AND channel <= 26);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'thread_networks_valid_network_name'
  ) THEN
    ALTER TABLE thread_networks
      ADD CONSTRAINT thread_networks_valid_network_name
      CHECK (char_length(network_name) BETWEEN 1 AND 16);
  END IF;
END $$;


-- ----------------------------------------------------------------------------
-- device_sessions: per-device opaque session tokens issued at adoption.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id       uuid NOT NULL UNIQUE REFERENCES devices(id) ON DELETE CASCADE,
  auth_user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  access_token    text NOT NULL,
  refresh_token   text NOT NULL,
  expires_at      timestamptz NOT NULL,
  status          text NOT NULL DEFAULT 'active',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Constraints (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'device_sessions_valid_status'
  ) THEN
    ALTER TABLE device_sessions
      ADD CONSTRAINT device_sessions_valid_status
      CHECK (status IN ('active', 'revoked'));
  END IF;
END $$;

-- Token lookup indexes. The edge functions look sessions up by access_token
-- (every authenticated call) and refresh_token (during refresh).
CREATE INDEX IF NOT EXISTS idx_device_sessions_access_token
  ON device_sessions(access_token) WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_device_sessions_refresh_token
  ON device_sessions(refresh_token) WHERE status = 'active';


-- ----------------------------------------------------------------------------
-- Row Level Security
-- ----------------------------------------------------------------------------

ALTER TABLE thread_networks ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_sessions ENABLE ROW LEVEL SECURITY;

-- thread_networks: the owning user can SELECT their row. The returned bytea
-- is opaque ciphertext - useful only via the get_thread_credentials edge
-- function which holds the decryption key. Writes go through edge functions
-- using the service role.
DROP POLICY IF EXISTS "thread_networks_owner_read" ON thread_networks;
CREATE POLICY "thread_networks_owner_read"
  ON thread_networks FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.auth_user_id = auth.uid()
      AND u.id = thread_networks.user_id
    )
  );

-- device_sessions: service role only. Tokens are returned to the device once
-- at adoption (and on refresh) via the edge function response body and never
-- exposed through PostgREST.
DROP POLICY IF EXISTS "device_sessions_service_only" ON device_sessions;
CREATE POLICY "device_sessions_service_only"
  ON device_sessions FOR ALL
  USING (auth.role() = 'service_role');


-- ----------------------------------------------------------------------------
-- updated_at triggers
-- ----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_thread_networks_updated_at ON thread_networks;
CREATE TRIGGER update_thread_networks_updated_at
  BEFORE UPDATE ON thread_networks
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_device_sessions_updated_at ON device_sessions;
CREATE TRIGGER update_device_sessions_updated_at
  BEFORE UPDATE ON device_sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- ----------------------------------------------------------------------------
-- Comments
-- ----------------------------------------------------------------------------

COMMENT ON TABLE thread_networks IS
  'Cloud-canonical Thread mesh credentials, one row per user account. Sensitive columns are AES-256-GCM ciphertext produced by edge functions; the DB never sees plaintext.';

COMMENT ON COLUMN thread_networks.network_key_encrypted IS
  'AES-256-GCM ciphertext of the 128-bit Thread network key. Decrypted by edge functions using THREAD_ENCRYPTION_KEY.';

COMMENT ON COLUMN thread_networks.pskc_encrypted IS
  'AES-256-GCM ciphertext of the Pre-Shared Key for Commissioner.';

COMMENT ON COLUMN thread_networks.rotated_at IS
  'Set on credential rotation. NULL means original credentials from adoption.';

COMMENT ON TABLE device_sessions IS
  'Per-device opaque session tokens issued by the adopt_device edge function. Hub firmware uses these for authenticated cloud calls in place of the shared anonymous key.';


-- ----------------------------------------------------------------------------
-- Completion
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  RAISE NOTICE 'Migration 20260511180000_firmware_thread_networks completed successfully';
  RAISE NOTICE '  - Dropped legacy thread_credentials table (replaced)';
  RAISE NOTICE '  - Created thread_networks (one mesh per user, AES-256-GCM encrypted)';
  RAISE NOTICE '  - Created device_sessions (per-device opaque tokens)';
  RAISE NOTICE '  - RLS policies in place';
  RAISE NOTICE '';
  RAISE NOTICE 'NEXT STEPS:';
  RAISE NOTICE '  1. Generate encryption key: openssl rand -hex 32';
  RAISE NOTICE '  2. Set as edge function secret: supabase secrets set THREAD_ENCRYPTION_KEY=<value>';
  RAISE NOTICE '  3. Deploy edge functions: adopt_device, get_thread_credentials, unadopt_device';
  RAISE NOTICE '  4. Delete claim-unit and unclaim-unit edge functions (superseded)';
END $$;
