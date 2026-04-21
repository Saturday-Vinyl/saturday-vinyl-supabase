-- ============================================================================
-- Migration: 20260412120000_admin_supplier_api_tokens.sql
-- Project: saturday-admin-app
-- Description: Table to store OAuth tokens for supplier APIs (DigiKey, etc.)
--              Tokens are stored per-user so each admin can link their own account.
-- Date: 2026-04-12
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- TABLE: supplier_api_tokens
-- ============================================================================
CREATE TABLE IF NOT EXISTS supplier_api_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,  -- e.g., 'digikey', 'mouser', 'lcsc'
  access_token TEXT NOT NULL,
  refresh_token TEXT,
  token_expires_at TIMESTAMPTZ,
  scopes TEXT,  -- space-separated OAuth scopes granted
  provider_metadata JSONB DEFAULT '{}'::jsonb,  -- extra data (e.g., client_id used)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One token set per user per provider
  UNIQUE (user_id, provider)
);

-- ============================================================================
-- INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_supplier_api_tokens_user
  ON supplier_api_tokens (user_id);

CREATE INDEX IF NOT EXISTS idx_supplier_api_tokens_provider
  ON supplier_api_tokens (provider);

-- ============================================================================
-- TRIGGERS
-- ============================================================================
-- Auto-update updated_at
DROP TRIGGER IF EXISTS set_supplier_api_tokens_updated_at ON supplier_api_tokens;
CREATE TRIGGER set_supplier_api_tokens_updated_at
  BEFORE UPDATE ON supplier_api_tokens
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- RLS POLICIES
-- ============================================================================
ALTER TABLE supplier_api_tokens ENABLE ROW LEVEL SECURITY;

-- Users can only see their own tokens
DROP POLICY IF EXISTS "Users can read own tokens" ON supplier_api_tokens;
CREATE POLICY "Users can read own tokens"
ON supplier_api_tokens FOR SELECT
TO authenticated
USING (
  user_id = (
    SELECT id FROM users WHERE auth_user_id = auth.uid()
  )
);

-- Users can insert their own tokens
DROP POLICY IF EXISTS "Users can insert own tokens" ON supplier_api_tokens;
CREATE POLICY "Users can insert own tokens"
ON supplier_api_tokens FOR INSERT
TO authenticated
WITH CHECK (
  user_id = (
    SELECT id FROM users WHERE auth_user_id = auth.uid()
  )
);

-- Users can update their own tokens
DROP POLICY IF EXISTS "Users can update own tokens" ON supplier_api_tokens;
CREATE POLICY "Users can update own tokens"
ON supplier_api_tokens FOR UPDATE
TO authenticated
USING (
  user_id = (
    SELECT id FROM users WHERE auth_user_id = auth.uid()
  )
);

-- Users can delete their own tokens (disconnect)
DROP POLICY IF EXISTS "Users can delete own tokens" ON supplier_api_tokens;
CREATE POLICY "Users can delete own tokens"
ON supplier_api_tokens FOR DELETE
TO authenticated
USING (
  user_id = (
    SELECT id FROM users WHERE auth_user_id = auth.uid()
  )
);

-- Service role (edge functions) can manage all tokens
DROP POLICY IF EXISTS "Service role full access to tokens" ON supplier_api_tokens;
CREATE POLICY "Service role full access to tokens"
ON supplier_api_tokens FOR ALL
TO service_role
USING (true)
WITH CHECK (true);
