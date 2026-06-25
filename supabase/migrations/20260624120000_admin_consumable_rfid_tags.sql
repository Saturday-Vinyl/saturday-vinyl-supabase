-- ============================================================================
-- Migration: 20260624120000_admin_consumable_rfid_tags.sql
-- Project: saturday-admin-app
-- Description: Maps printer-read NFC/RFID consumable codes to inventory parts,
--              and teaches label_stocks how many labels a roll holds so a roll
--              received into stock can be tracked (and decremented) in labels.
--
--              `part_consumable_tags`: a Niimbot roll/ribbon NFC tag reports a
--              manufacturer product code (e.g. '042225005') that is stable across
--              every roll of that product, regardless of which supplier it was
--              bought from. That is a different identifier class than the
--              supplier receiving barcode (`supplier_parts.barcode_value`, e.g.
--              an Amazon FNSKU), so it gets its own part-level mapping table.
--
--              `label_stocks.labels_per_roll`: stock-unit (roll) vs consumption-
--              unit (label) conversion. Receiving one roll stocks N labels;
--              printing decrements labels. The roll's NFC tag (allPaper) is the
--              authoritative per-roll count and seeds/validates this nominal.
-- Date: 2026-06-24
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- TABLE: part_consumable_tags
-- ============================================================================

CREATE TABLE IF NOT EXISTS part_consumable_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- The inventory part this consumable code identifies. CASCADE: the mapping is
  -- meaningless without its part.
  part_id UUID NOT NULL REFERENCES parts(id) ON DELETE CASCADE,

  -- Identifier scheme. 'niimbot_rfid' = the product code in a Niimbot roll/ribbon
  -- NFC tag. Kept generic so other tag schemes can be added later.
  tag_kind TEXT NOT NULL DEFAULT 'niimbot_rfid',

  -- The code as read from the tag (Niimbot's barCode field, e.g. '042225005').
  tag_value TEXT NOT NULL,

  -- Whether this tag is the label media or the ribbon.
  consumable_role TEXT NOT NULL DEFAULT 'label'
    CHECK (consumable_role IN ('label', 'ribbon')),

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- A given (scheme, value) identifies exactly one part — this is the lookup key
  -- the printer uses to resolve a loaded roll to inventory.
  CONSTRAINT part_consumable_tags_kind_value_unique UNIQUE (tag_kind, tag_value)
);

CREATE INDEX IF NOT EXISTS idx_part_consumable_tags_part
  ON part_consumable_tags(part_id);

-- ============================================================================
-- COLUMN: label_stocks.labels_per_roll
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'label_stocks' AND column_name = 'labels_per_roll'
  ) THEN
    ALTER TABLE label_stocks
      ADD COLUMN labels_per_roll INTEGER CHECK (labels_per_roll > 0);
  END IF;
END $$;

COMMENT ON COLUMN label_stocks.labels_per_roll IS
  'Nominal labels per roll for roll-fed stock; receiving one roll stocks this '
  'many labels (each). NULL for non-roll/continuous media. The roll NFC tag '
  '(allPaper) is authoritative per physical roll and seeds/validates this.';

-- ============================================================================
-- UPDATED_AT TRIGGER (part_consumable_tags)
-- ============================================================================

CREATE OR REPLACE FUNCTION update_part_consumable_tags_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_part_consumable_tags_updated_at ON part_consumable_tags;
CREATE TRIGGER trigger_part_consumable_tags_updated_at
  BEFORE UPDATE ON part_consumable_tags
  FOR EACH ROW
  EXECUTE FUNCTION update_part_consumable_tags_updated_at();

-- ============================================================================
-- ROW LEVEL SECURITY (open to authenticated, matching the parts-inventory domain)
-- ============================================================================

ALTER TABLE part_consumable_tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can select part_consumable_tags" ON part_consumable_tags;
CREATE POLICY "Authenticated users can select part_consumable_tags"
ON part_consumable_tags FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert part_consumable_tags" ON part_consumable_tags;
CREATE POLICY "Authenticated users can insert part_consumable_tags"
ON part_consumable_tags FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can update part_consumable_tags" ON part_consumable_tags;
CREATE POLICY "Authenticated users can update part_consumable_tags"
ON part_consumable_tags FOR UPDATE TO authenticated USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Authenticated users can delete part_consumable_tags" ON part_consumable_tags;
CREATE POLICY "Authenticated users can delete part_consumable_tags"
ON part_consumable_tags FOR DELETE TO authenticated USING (true);
