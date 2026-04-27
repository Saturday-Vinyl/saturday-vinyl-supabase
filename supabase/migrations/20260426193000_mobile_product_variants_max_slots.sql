-- ============================================================================
-- Migration: 20260426193000_mobile_product_variants_max_slots.sql
-- Project: saturday-mobile-app
-- Description: Add max_slots column to product_variants. Used by the consumer
--              app to compute crate fullness (current RFID inventory count
--              divided by max_slots) and pick the matching product_image_slots
--              capacity row ('empty' | 'half' | 'full') for compositing.
-- Date: 2026-04-26
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'product_variants' AND column_name = 'max_slots'
    ) THEN
        ALTER TABLE public.product_variants ADD COLUMN max_slots INT;
    END IF;
END $$;

COMMENT ON COLUMN public.product_variants.max_slots IS
    'Total album-slot capacity for this variant (e.g. 24 for a standard crate). NULL for non-crate variants. Used by the consumer app to derive empty/half/full capacity from current RFID inventory.';
