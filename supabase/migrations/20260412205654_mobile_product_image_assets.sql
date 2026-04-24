-- ============================================================================
-- Migration: 20260412205654_mobile_product_image_assets.sql
-- Project: saturday-mobile-app
-- Description: Create product_image_assets table for storing CAD-rendered
--              product image metadata (frame images + mask images per variant/angle).
--              Also creates the product-images storage bucket.
-- Date: 2026-04-12
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- 1. Create product_image_assets table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.product_image_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    variant_id UUID NOT NULL,
    angle TEXT NOT NULL,
    frame_path TEXT NOT NULL,
    mask_path TEXT,
    slot_count INT NOT NULL DEFAULT 0,
    image_width INT NOT NULL,
    image_height INT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT product_image_assets_variant_id_fkey
        FOREIGN KEY (variant_id) REFERENCES public.product_variants(id) ON DELETE CASCADE
);

-- Unique constraint: one image per variant + angle combination
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'product_image_assets_variant_id_angle_key'
    ) THEN
        ALTER TABLE public.product_image_assets
            ADD CONSTRAINT product_image_assets_variant_id_angle_key UNIQUE (variant_id, angle);
    END IF;
END $$;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_product_image_assets_variant_id
    ON public.product_image_assets(variant_id);

-- ============================================================================
-- 2. RLS Policies
-- ============================================================================

ALTER TABLE public.product_image_assets ENABLE ROW LEVEL SECURITY;

-- Read-only for all authenticated users (these are marketing assets)
DROP POLICY IF EXISTS "Authenticated users can read product image assets" ON public.product_image_assets;
CREATE POLICY "Authenticated users can read product image assets"
    ON public.product_image_assets FOR SELECT
    TO authenticated
    USING (true);

-- Admins can manage product image assets
DROP POLICY IF EXISTS "Admins can insert product image assets" ON public.product_image_assets;
CREATE POLICY "Admins can insert product image assets"
    ON public.product_image_assets FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM users u
            WHERE u.auth_user_id = auth.uid()
            AND u.is_admin = true
        )
    );

DROP POLICY IF EXISTS "Admins can update product image assets" ON public.product_image_assets;
CREATE POLICY "Admins can update product image assets"
    ON public.product_image_assets FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users u
            WHERE u.auth_user_id = auth.uid()
            AND u.is_admin = true
        )
    );

DROP POLICY IF EXISTS "Admins can delete product image assets" ON public.product_image_assets;
CREATE POLICY "Admins can delete product image assets"
    ON public.product_image_assets FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users u
            WHERE u.auth_user_id = auth.uid()
            AND u.is_admin = true
        )
    );

-- ============================================================================
-- 3. Create product-images storage bucket (public, read-only for consumers)
-- ============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('product-images', 'product-images', true)
ON CONFLICT (id) DO NOTHING;

-- Allow public read access to product images
DROP POLICY IF EXISTS "Public read access for product images" ON storage.objects;
CREATE POLICY "Public read access for product images"
    ON storage.objects FOR SELECT
    TO public
    USING (bucket_id = 'product-images');

-- Admins can upload product images
DROP POLICY IF EXISTS "Admins can upload product images" ON storage.objects;
CREATE POLICY "Admins can upload product images"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'product-images'
        AND EXISTS (
            SELECT 1 FROM users u
            WHERE u.auth_user_id = auth.uid()
            AND u.is_admin = true
        )
    );

-- Admins can update product images
DROP POLICY IF EXISTS "Admins can update product images" ON storage.objects;
CREATE POLICY "Admins can update product images"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'product-images'
        AND EXISTS (
            SELECT 1 FROM users u
            WHERE u.auth_user_id = auth.uid()
            AND u.is_admin = true
        )
    );

-- Admins can delete product images
DROP POLICY IF EXISTS "Admins can delete product images" ON storage.objects;
CREATE POLICY "Admins can delete product images"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'product-images'
        AND EXISTS (
            SELECT 1 FROM users u
            WHERE u.auth_user_id = auth.uid()
            AND u.is_admin = true
        )
    );

-- ============================================================================
-- 4. Comments
-- ============================================================================

COMMENT ON TABLE public.product_image_assets IS 'CAD-rendered product images with optional mask images for album cover compositing';
COMMENT ON COLUMN public.product_image_assets.variant_id IS 'FK to product_variants - identifies which product variant this image represents';
COMMENT ON COLUMN public.product_image_assets.angle IS 'View angle identifier (e.g., front, angle, top)';
COMMENT ON COLUMN public.product_image_assets.frame_path IS 'Supabase Storage path to the product frame image (transparent slots for album compositing)';
COMMENT ON COLUMN public.product_image_assets.mask_path IS 'Supabase Storage path to the grayscale mask image (white=album slot, black=no content). Null if no album compositing for this angle.';
COMMENT ON COLUMN public.product_image_assets.slot_count IS 'Number of album slots in this view (0 = no compositing)';
COMMENT ON COLUMN public.product_image_assets.image_width IS 'Original image width in pixels';
COMMENT ON COLUMN public.product_image_assets.image_height IS 'Original image height in pixels';
