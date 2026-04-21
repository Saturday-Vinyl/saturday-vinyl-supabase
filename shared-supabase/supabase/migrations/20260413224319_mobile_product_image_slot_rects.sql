-- ============================================================================
-- Migration: 20260413224319_mobile_product_image_slot_rects.sql
-- Project: saturday-mobile-app
-- Description: Add slot_rects JSONB column to product_image_assets for defining
--              album cover position/scale within the product frame image.
--              Each entry: {"x": px, "y": px, "width": px, "height": px}
--              in source image coordinates.
-- Date: 2026-04-13
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'product_image_assets'
      AND column_name = 'slot_rects'
  ) THEN
    ALTER TABLE public.product_image_assets
      ADD COLUMN slot_rects JSONB NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END $$;

COMMENT ON COLUMN public.product_image_assets.slot_rects IS
  'Array of album slot rectangles in image pixel coordinates. Each entry: {"x", "y", "width", "height"}. Order matches physical slot ordering (front to back).';
