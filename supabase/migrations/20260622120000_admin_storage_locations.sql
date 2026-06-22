-- ============================================================================
-- Migration: 20260622120000_admin_storage_locations.sql
-- Project: saturday-admin-app
-- Description: Physical storage location hierarchy (building -> cabinet -> drawer)
--              with cached display path, scannable code, optional addressable-LED
--              mapping, hierarchy-validation + path-maintenance triggers, and RLS.
-- Date: 2026-06-22
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- TABLE
-- ============================================================================

-- Storage Locations: a single self-referencing tree constrained to exactly three
-- typed levels (building -> cabinet -> drawer). LED mapping columns reference the
-- existing `devices` table by MAC (plain text, intentionally NOT a foreign key:
-- a drawer may be mapped to a controller before that device is provisioned).
CREATE TABLE IF NOT EXISTS storage_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  location_type TEXT NOT NULL CHECK (location_type IN ('building', 'cabinet', 'drawer')),
  parent_id UUID REFERENCES storage_locations(id) ON DELETE RESTRICT,
  name TEXT NOT NULL,
  -- Stable scannable code printed as a QR ({BASE_URL}/location/{code}); defaults to
  -- a random 10-char hex string and may be overridden by the app.
  code TEXT NOT NULL UNIQUE DEFAULT substr(replace(gen_random_uuid()::text, '-', ''), 1, 10),
  full_path TEXT,
  -- Optional addressable-LED "locate" mapping (controller is a standard Saturday device).
  led_device_mac VARCHAR(17),  -- MAC of the LED-locator device in `devices`; NULL = no LED
  led_index INTEGER,           -- first LED index for this drawer
  led_count INTEGER DEFAULT 1, -- number of LEDs in the range
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_storage_locations_parent ON storage_locations(parent_id);
CREATE INDEX IF NOT EXISTS idx_storage_locations_type ON storage_locations(location_type);
CREATE INDEX IF NOT EXISTS idx_storage_locations_led_device
  ON storage_locations(led_device_mac) WHERE led_device_mac IS NOT NULL;

-- ============================================================================
-- HIERARCHY VALIDATION + FULL_PATH MAINTENANCE
-- ============================================================================

-- BEFORE INSERT/UPDATE: enforce the 3-level parent rules and (re)compute full_path.
CREATE OR REPLACE FUNCTION storage_locations_validate_and_path()
RETURNS TRIGGER AS $$
DECLARE
  parent_type TEXT;
  parent_path TEXT;
BEGIN
  IF NEW.location_type = 'building' THEN
    IF NEW.parent_id IS NOT NULL THEN
      RAISE EXCEPTION 'storage_locations: a building must not have a parent';
    END IF;
    NEW.full_path := NEW.name;
  ELSE
    IF NEW.parent_id IS NULL THEN
      RAISE EXCEPTION 'storage_locations: a % must have a parent', NEW.location_type;
    END IF;

    SELECT location_type, full_path
      INTO parent_type, parent_path
      FROM storage_locations
      WHERE id = NEW.parent_id;

    IF parent_type IS NULL THEN
      RAISE EXCEPTION 'storage_locations: parent % not found', NEW.parent_id;
    END IF;

    IF NEW.location_type = 'cabinet' AND parent_type <> 'building' THEN
      RAISE EXCEPTION 'storage_locations: a cabinet''s parent must be a building (got %)', parent_type;
    ELSIF NEW.location_type = 'drawer' AND parent_type <> 'cabinet' THEN
      RAISE EXCEPTION 'storage_locations: a drawer''s parent must be a cabinet (got %)', parent_type;
    END IF;

    NEW.full_path := parent_path || ' › ' || NEW.name;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_storage_locations_validate_and_path ON storage_locations;
CREATE TRIGGER trigger_storage_locations_validate_and_path
  BEFORE INSERT OR UPDATE ON storage_locations
  FOR EACH ROW
  EXECUTE FUNCTION storage_locations_validate_and_path();

-- AFTER UPDATE: when a node's full_path changes (rename/reparent), refresh children.
-- Each child UPDATE re-fires the BEFORE trigger (recompute from this node's new
-- full_path) and this AFTER trigger (cascade to grandchildren). Terminates at the
-- drawer level. Guarded by an actual full_path change to avoid needless churn.
CREATE OR REPLACE FUNCTION storage_locations_cascade_path()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.full_path IS DISTINCT FROM OLD.full_path THEN
    UPDATE storage_locations
      SET full_path = NEW.full_path || ' › ' || name
      WHERE parent_id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_storage_locations_cascade_path ON storage_locations;
CREATE TRIGGER trigger_storage_locations_cascade_path
  AFTER UPDATE ON storage_locations
  FOR EACH ROW
  EXECUTE FUNCTION storage_locations_cascade_path();

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION update_storage_locations_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_storage_locations_updated_at ON storage_locations;
CREATE TRIGGER trigger_storage_locations_updated_at
  BEFORE UPDATE ON storage_locations
  FOR EACH ROW
  EXECUTE FUNCTION update_storage_locations_updated_at();

-- ============================================================================
-- ROW LEVEL SECURITY (open to authenticated, matching the parts-inventory domain)
-- ============================================================================

ALTER TABLE storage_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can select storage_locations" ON storage_locations;
CREATE POLICY "Authenticated users can select storage_locations"
ON storage_locations FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert storage_locations" ON storage_locations;
CREATE POLICY "Authenticated users can insert storage_locations"
ON storage_locations FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update storage_locations" ON storage_locations;
CREATE POLICY "Authenticated users can update storage_locations"
ON storage_locations FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete storage_locations" ON storage_locations;
CREATE POLICY "Authenticated users can delete storage_locations"
ON storage_locations FOR DELETE TO authenticated USING (true);
