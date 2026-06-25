-- ============================================================================
-- Migration: 20260622160000_admin_label_stocks.sql
-- Project: saturday-admin-app
-- Description: Shared catalog of label consumable stocks for the printing-
--              hardening initiative. Metric (mm) dimensions with a printable
--              area distinct from the physical label (e.g. cable wrap labels),
--              print material/sensing metadata, optional link to a `parts`
--              inventory row (so settings can show on-hand), and RLS. Seeds the
--              five stocks currently in use.
-- Date: 2026-06-22
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- TABLE
-- ============================================================================

-- Label Stocks: one row per distinct label consumable. Dimensions are physical;
-- the printable_* columns describe the area a template may draw into (which is
-- smaller than physical for wrap-around cable labels). `code` is a stable slug
-- the code-defined template registry keys on (so templates never hardcode UUIDs).
CREATE TABLE IF NOT EXISTS label_stocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Stable machine slug referenced by templates/code (e.g. 'dt_25_qr').
  code TEXT NOT NULL UNIQUE,
  -- Human-readable name shown in settings (e.g. '25.4 × 25.4 Part QR').
  name TEXT NOT NULL,

  -- Physical label size (mm).
  width_mm NUMERIC NOT NULL CHECK (width_mm > 0),
  height_mm NUMERIC NOT NULL CHECK (height_mm > 0),

  -- Printable area within the physical label (mm). Defaults equal to physical
  -- via the seed/app; offsets locate the printable region (top-left origin).
  printable_width_mm NUMERIC NOT NULL CHECK (printable_width_mm > 0),
  printable_height_mm NUMERIC NOT NULL CHECK (printable_height_mm > 0),
  printable_offset_x_mm NUMERIC NOT NULL DEFAULT 0 CHECK (printable_offset_x_mm >= 0),
  printable_offset_y_mm NUMERIC NOT NULL DEFAULT 0 CHECK (printable_offset_y_mm >= 0),

  -- Print method: direct thermal, thermal transfer (ribbon), or RFID inlay
  -- (direct-thermal printable + embedded tag). Drives which printer family fits.
  material TEXT NOT NULL DEFAULT 'direct_thermal'
    CHECK (material IN ('direct_thermal', 'thermal_transfer', 'rfid')),
  -- Media sensing for label printers.
  sensing TEXT NOT NULL DEFAULT 'gap'
    CHECK (sensing IN ('gap', 'black_mark', 'continuous')),
  -- Print head resolution in dots-per-inch.
  dpi INTEGER NOT NULL DEFAULT 203 CHECK (dpi > 0),

  -- Optional link to the inventory part for this consumable (on-hand display).
  -- SET NULL (not RESTRICT): deleting a part should not block stock config.
  part_id UUID REFERENCES parts(id) ON DELETE SET NULL,

  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Printable area must fit within the physical label.
  CONSTRAINT label_stocks_printable_fits CHECK (
    printable_offset_x_mm + printable_width_mm <= width_mm AND
    printable_offset_y_mm + printable_height_mm <= height_mm
  )
);

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_label_stocks_part ON label_stocks(part_id) WHERE part_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_label_stocks_active ON label_stocks(is_active) WHERE is_active = true;

-- ============================================================================
-- UPDATED_AT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION update_label_stocks_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_label_stocks_updated_at ON label_stocks;
CREATE TRIGGER trigger_label_stocks_updated_at
  BEFORE UPDATE ON label_stocks
  FOR EACH ROW
  EXECUTE FUNCTION update_label_stocks_updated_at();

-- ============================================================================
-- ROW LEVEL SECURITY (open to authenticated, matching the parts-inventory domain)
-- ============================================================================

ALTER TABLE label_stocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can select label_stocks" ON label_stocks;
CREATE POLICY "Authenticated users can select label_stocks"
ON label_stocks FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert label_stocks" ON label_stocks;
CREATE POLICY "Authenticated users can insert label_stocks"
ON label_stocks FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update label_stocks" ON label_stocks;
CREATE POLICY "Authenticated users can update label_stocks"
ON label_stocks FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete label_stocks" ON label_stocks;
CREATE POLICY "Authenticated users can delete label_stocks"
ON label_stocks FOR DELETE TO authenticated USING (true);

-- ============================================================================
-- SEED: the five consumables currently in use (part_id linked later via UI)
-- ============================================================================

INSERT INTO label_stocks
  (code, name, width_mm, height_mm, printable_width_mm, printable_height_mm,
   printable_offset_x_mm, printable_offset_y_mm, material, sensing)
VALUES
  -- Standard thermal-transfer label.
  ('tt_50x30', '50 × 30 Thermal Transfer', 50, 30, 50, 30, 0, 0, 'thermal_transfer', 'gap'),
  -- Cable wrap label: 78mm tall but only the top 38mm is printable; the lower
  -- 40mm is a tail that wraps the cable.
  ('tt_25x78_cable', '25 × 78 Cable Label', 25, 78, 25, 38, 0, 0, 'thermal_transfer', 'gap'),
  -- Printable RFID tag.
  ('rfid_50x50', '50 × 50 RFID Tag', 50, 50, 50, 50, 0, 0, 'rfid', 'gap'),
  -- Factory part QR codes.
  ('dt_25_qr', '25.4 × 25.4 Part QR', 25.4, 25.4, 25.4, 25.4, 0, 0, 'direct_thermal', 'gap'),
  -- Shipping labels (4" × 6").
  ('dt_4x6_ship', '4" × 6" Shipping', 101.6, 152.4, 101.6, 152.4, 0, 0, 'direct_thermal', 'gap')
ON CONFLICT (code) DO NOTHING;
