-- ============================================================================
-- Migration: 20260201000000_legacy_qr_lookup.sql
-- Description: Reference table for legacy QR codes that used separate uuid column
-- Date: 2026-02-01
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Reference table for ~5 legacy QR codes that used a separate uuid
-- NOT used by application - for manual lookup only if old QR codes are scanned
-- Going forward, new QR codes will encode units.id directly

CREATE TABLE IF NOT EXISTS legacy_qr_code_lookup (
  old_uuid UUID PRIMARY KEY,
  unit_id UUID NOT NULL REFERENCES units(id) ON DELETE CASCADE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE legacy_qr_code_lookup IS
  'Reference table for ~5 legacy QR codes that used a separate uuid column in production_units.
   Not used by application code - for manual lookup only if old QR codes need resolution.
   New QR codes encode units.id directly.';

-- Populate from production_units where uuid differs from id
-- This captures the legacy mapping for any units where uuid was different
-- IMPORTANT: Only insert if the unit exists in units table (some production_units may be orphaned)
INSERT INTO legacy_qr_code_lookup (old_uuid, unit_id, notes)
SELECT
  pu.uuid,
  pu.id,
  'Migrated from production_units on ' || NOW()::text
FROM production_units pu
INNER JOIN units u ON u.id = pu.id  -- Only include if unit exists in units table
WHERE NOT EXISTS (
  SELECT 1 FROM legacy_qr_code_lookup l WHERE l.old_uuid = pu.uuid
)
ON CONFLICT (old_uuid) DO NOTHING;

-- Grant access to authenticated users (read-only for reference)
GRANT SELECT ON legacy_qr_code_lookup TO authenticated;
