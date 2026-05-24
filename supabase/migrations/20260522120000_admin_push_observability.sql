-- ============================================================================
-- Migration: 20260522120000_admin_push_observability.sql
-- Project: saturday-admin-app
-- Description: Read-only observability surface over push notification delivery.
--              Adds four admin-only views over notification_delivery_log and
--              push_notification_tokens, admin-read RLS policies on the
--              underlying tables, and a sent_by_user_id audit column for
--              admin-initiated pushes (populated by future edge functions).
-- Date: 2026-05-22
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- COLUMN: notification_delivery_log.sent_by_user_id
-- Audits which admin initiated a push (NULL for system-generated pushes).
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'notification_delivery_log'
      AND column_name = 'sent_by_user_id'
  ) THEN
    ALTER TABLE notification_delivery_log
      ADD COLUMN sent_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_delivery_log_sent_by
  ON notification_delivery_log(sent_by_user_id)
  WHERE sent_by_user_id IS NOT NULL;

-- Helpful for the dashboard's time-bucketed aggregates.
CREATE INDEX IF NOT EXISTS idx_delivery_log_created_at
  ON notification_delivery_log(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_log_token_status
  ON notification_delivery_log(token_id, status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_log_type_status_created
  ON notification_delivery_log(notification_type, status, created_at DESC);

-- ============================================================================
-- RLS: admin read access on underlying tables
-- Views below run as the invoker, so admins must be permitted to read the
-- underlying rows. Existing user-scoped and service-role policies remain.
-- ============================================================================
DROP POLICY IF EXISTS "Admins can read all delivery log" ON notification_delivery_log;
CREATE POLICY "Admins can read all delivery log"
  ON notification_delivery_log FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.auth_user_id = auth.uid()
        AND u.is_admin = true
    )
  );

DROP POLICY IF EXISTS "Admins can read all push tokens" ON push_notification_tokens;
CREATE POLICY "Admins can read all push tokens"
  ON push_notification_tokens FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM users u
      WHERE u.auth_user_id = auth.uid()
        AND u.is_admin = true
    )
  );

-- ============================================================================
-- ENABLE REALTIME for the delivery log
-- The admin dashboard subscribes for the live activity tail.
-- ============================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND tablename = 'notification_delivery_log'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE notification_delivery_log;
    END IF;
  END IF;
END $$;

-- ============================================================================
-- VIEW: admin_push_devices
-- One row per push token with 7-day health metrics.
-- ============================================================================
CREATE OR REPLACE VIEW admin_push_devices
WITH (security_invoker = true) AS
SELECT
  pnt.id                AS token_id,
  pnt.user_id,
  u.email,
  u.full_name           AS display_name,
  pnt.platform,
  pnt.device_identifier,
  pnt.app_version,
  pnt.is_active,
  pnt.last_used_at,
  pnt.created_at        AS token_created_at,
  pnt.updated_at        AS token_updated_at,
  COALESCE(stats.sent_7d, 0)      AS sent_7d,
  COALESCE(stats.failed_7d, 0)    AS failed_7d,
  stats.last_sent_at,
  stats.last_failed_at
FROM push_notification_tokens pnt
JOIN users u ON u.id = pnt.user_id
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) FILTER (WHERE status = 'sent'   AND created_at > NOW() - INTERVAL '7 days') AS sent_7d,
    COUNT(*) FILTER (WHERE status = 'failed' AND created_at > NOW() - INTERVAL '7 days') AS failed_7d,
    MAX(created_at) FILTER (WHERE status = 'sent')   AS last_sent_at,
    MAX(created_at) FILTER (WHERE status = 'failed') AS last_failed_at
  FROM notification_delivery_log ndl
  WHERE ndl.token_id = pnt.id
) stats ON true;

-- ============================================================================
-- VIEW: admin_push_deliveries
-- Filterable delivery history joined to user + device metadata.
-- ============================================================================
CREATE OR REPLACE VIEW admin_push_deliveries
WITH (security_invoker = true) AS
SELECT
  ndl.id,
  ndl.created_at,
  ndl.user_id,
  u.email,
  u.full_name        AS display_name,
  ndl.notification_type,
  ndl.source_id,
  ndl.token_id,
  pnt.platform,
  pnt.device_identifier,
  ndl.status,
  ndl.error_message,
  ndl.sent_at,
  ndl.delivered_at,
  ndl.sent_by_user_id
FROM notification_delivery_log ndl
JOIN users u ON u.id = ndl.user_id
LEFT JOIN push_notification_tokens pnt ON pnt.id = ndl.token_id;

-- ============================================================================
-- VIEW: admin_push_health_by_type
-- Hourly buckets per notification_type over the last 7 days.
-- ============================================================================
CREATE OR REPLACE VIEW admin_push_health_by_type
WITH (security_invoker = true) AS
SELECT
  notification_type,
  DATE_TRUNC('hour', created_at)               AS bucket_hour,
  COUNT(*) FILTER (WHERE status = 'sent')      AS sent_count,
  COUNT(*) FILTER (WHERE status = 'failed')    AS failed_count,
  COUNT(*)                                     AS total_count
FROM notification_delivery_log
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY 1, 2;

-- ============================================================================
-- VIEW: admin_push_error_patterns
-- Failure categorization over the last 7 days. A server-wide outage shows up
-- as a single high-count row (e.g. apns_env_mismatch, fcm_auth_error).
-- ============================================================================
CREATE OR REPLACE VIEW admin_push_error_patterns
WITH (security_invoker = true) AS
SELECT
  notification_type,
  CASE
    WHEN error_message ILIKE '%BadEnvironmentKeyInToken%' THEN 'apns_env_mismatch'
    WHEN error_message ILIKE '%THIRD_PARTY_AUTH_ERROR%'   THEN 'fcm_auth_error'
    WHEN error_message ILIKE '%Unregistered%'             THEN 'token_unregistered'
    WHEN error_message ILIKE '%InvalidRegistration%'      THEN 'token_invalid'
    WHEN error_message ILIKE '%QuotaExceeded%'            THEN 'fcm_quota'
    WHEN error_message ILIKE '%401%'                      THEN 'unauthenticated'
    WHEN error_message ILIKE '%429%'                      THEN 'rate_limited'
    ELSE 'other'
  END                                          AS error_category,
  COUNT(*)                                     AS n,
  MIN(created_at)                              AS first_seen,
  MAX(created_at)                              AS last_seen,
  COUNT(DISTINCT token_id)                     AS affected_tokens,
  COUNT(DISTINCT user_id)                      AS affected_users
FROM notification_delivery_log
WHERE status = 'failed'
  AND created_at > NOW() - INTERVAL '7 days'
GROUP BY 1, 2;

-- ============================================================================
-- GRANTS
-- security_invoker views inherit table-level RLS; explicit SELECT grants on
-- the views themselves let authenticated clients (PostgREST) target them.
-- ============================================================================
GRANT SELECT ON admin_push_devices         TO authenticated;
GRANT SELECT ON admin_push_deliveries      TO authenticated;
GRANT SELECT ON admin_push_health_by_type  TO authenticated;
GRANT SELECT ON admin_push_error_patterns  TO authenticated;
