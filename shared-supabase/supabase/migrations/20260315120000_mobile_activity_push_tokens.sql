-- ============================================================================
-- Migration: 20260315120000_mobile_activity_push_tokens.sql
-- Project: saturday-mobile-app
-- Description: Stores ActivityKit push tokens for server-side Live Activity
--              updates. Separate from FCM push_notification_tokens because
--              activity tokens are tied to a specific Live Activity instance,
--              not a device.
-- Date: 2026-03-15
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ActivityKit push tokens for Live Activity updates
CREATE TABLE IF NOT EXISTS activity_push_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id uuid REFERENCES playback_sessions(id) ON DELETE CASCADE,
  push_token text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Unique constraint: one token per user (tokens are unique per Live Activity)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'activity_push_tokens_user_token_key'
  ) THEN
    ALTER TABLE activity_push_tokens
      ADD CONSTRAINT activity_push_tokens_user_token_key UNIQUE (user_id, push_token);
  END IF;
END $$;

-- Index for looking up active tokens by session (used by update-track-progression cron)
CREATE INDEX IF NOT EXISTS idx_activity_push_tokens_session_active
  ON activity_push_tokens (session_id) WHERE (is_active = true);

-- Index for looking up active tokens by user
CREATE INDEX IF NOT EXISTS idx_activity_push_tokens_user_active
  ON activity_push_tokens (user_id) WHERE (is_active = true);

-- Enable RLS
ALTER TABLE activity_push_tokens ENABLE ROW LEVEL SECURITY;

-- Users can manage their own activity tokens
DROP POLICY IF EXISTS "Users can view own activity tokens" ON activity_push_tokens;
CREATE POLICY "Users can view own activity tokens"
ON activity_push_tokens FOR SELECT TO authenticated
USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "Users can insert own activity tokens" ON activity_push_tokens;
CREATE POLICY "Users can insert own activity tokens"
ON activity_push_tokens FOR INSERT TO authenticated
WITH CHECK (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "Users can update own activity tokens" ON activity_push_tokens;
CREATE POLICY "Users can update own activity tokens"
ON activity_push_tokens FOR UPDATE TO authenticated
USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

DROP POLICY IF EXISTS "Users can delete own activity tokens" ON activity_push_tokens;
CREATE POLICY "Users can delete own activity tokens"
ON activity_push_tokens FOR DELETE TO authenticated
USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

-- Service role can manage all tokens (for cron function)
DROP POLICY IF EXISTS "Service role can manage all activity tokens" ON activity_push_tokens;
CREATE POLICY "Service role can manage all activity tokens"
ON activity_push_tokens FOR ALL TO service_role
USING (true) WITH CHECK (true);
