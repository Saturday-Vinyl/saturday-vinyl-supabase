-- ============================================================================
-- Migration: 20260525120000_shared_push_alerting.sql
-- Project: shared
-- Description: Alerting state for the push notification health evaluator.
--              `notification_alerts` holds one row per (rule_id,
--              notification_type) pair that is currently firing. The
--              `check-push-health` edge function inserts a row on first
--              trigger (and sends an email), updates `last_evaluated_at`
--              on subsequent ticks while still firing, and clears
--              (`cleared_at`) when the condition no longer holds.
--              Admin app subscribes via Realtime for the in-app banner.
-- Date: 2026-05-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

CREATE TABLE IF NOT EXISTS notification_alerts (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id              TEXT NOT NULL,
  notification_type    TEXT,
  severity             TEXT NOT NULL DEFAULT 'warning',
  fired_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_evaluated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  cleared_at           TIMESTAMPTZ,
  acknowledged_at      TIMESTAMPTZ,
  acknowledged_by      UUID REFERENCES users(id) ON DELETE SET NULL,
  last_payload         JSONB NOT NULL DEFAULT '{}'::jsonb,
  email_sent_at        TIMESTAMPTZ,
  email_message_id     TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT valid_severity CHECK (severity IN ('info', 'warning', 'critical'))
);

-- At most one active (uncleared) alert per (rule_id, notification_type).
-- Treats NULL notification_type as a distinct value via coalesce so global
-- rules (notification_type = NULL) get their own slot.
CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_alerts_active
  ON notification_alerts (rule_id, COALESCE(notification_type, ''))
  WHERE cleared_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_notification_alerts_fired_at
  ON notification_alerts (fired_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_alerts_active_lookup
  ON notification_alerts (rule_id, notification_type)
  WHERE cleared_at IS NULL;

-- RLS: admins read, admins update (for acknowledge), service role writes.
ALTER TABLE notification_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read alerts" ON notification_alerts;
CREATE POLICY "Admins can read alerts"
  ON notification_alerts FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.auth_user_id = auth.uid()
        AND u.is_admin = true
    )
  );

DROP POLICY IF EXISTS "Admins can acknowledge alerts" ON notification_alerts;
CREATE POLICY "Admins can acknowledge alerts"
  ON notification_alerts FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.auth_user_id = auth.uid()
        AND u.is_admin = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.auth_user_id = auth.uid()
        AND u.is_admin = true
    )
  );

DROP POLICY IF EXISTS "Service role full access on alerts" ON notification_alerts;
CREATE POLICY "Service role full access on alerts"
  ON notification_alerts FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Enable Realtime so the admin dashboard can show a live banner.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND tablename = 'notification_alerts'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE notification_alerts;
    END IF;
  END IF;
END $$;

COMMENT ON TABLE notification_alerts IS
'Active and historical push notification health alerts emitted by the check-push-health evaluator. One row per (rule_id, notification_type) firing event; cleared_at marks resolution.';
