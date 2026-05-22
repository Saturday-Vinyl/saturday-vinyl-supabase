-- ============================================================================
-- Migration: 20260421183316_mobile_product_image_slots.sql
-- Project: saturday-mobile-app
-- Description: Create product_image_slots table for defining album cover
--              transform and clip paths per product/angle/capacity.
--              Also cleans up deprecated columns from product_image_assets.
-- Date: 2026-04-21
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- 1. Create product_image_slots table
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.product_image_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL,
    angle TEXT NOT NULL,
    capacity TEXT NOT NULL DEFAULT 'full',
    slot_data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT product_image_slots_product_id_fkey
        FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE
);

-- Unique constraint: one slot definition per product + angle + capacity
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'product_image_slots_product_angle_capacity_key'
    ) THEN
        ALTER TABLE public.product_image_slots
            ADD CONSTRAINT product_image_slots_product_angle_capacity_key
            UNIQUE (product_id, angle, capacity);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_product_image_slots_product_id
    ON public.product_image_slots(product_id);

-- ============================================================================
-- 2. RLS Policies
-- ============================================================================

ALTER TABLE public.product_image_slots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users can read product image slots" ON public.product_image_slots;
CREATE POLICY "Authenticated users can read product image slots"
    ON public.product_image_slots FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Admins can insert product image slots" ON public.product_image_slots;
CREATE POLICY "Admins can insert product image slots"
    ON public.product_image_slots FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM users u
            WHERE u.auth_user_id = auth.uid()
            AND u.is_admin = true
        )
    );

DROP POLICY IF EXISTS "Admins can update product image slots" ON public.product_image_slots;
CREATE POLICY "Admins can update product image slots"
    ON public.product_image_slots FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users u
            WHERE u.auth_user_id = auth.uid()
            AND u.is_admin = true
        )
    );

DROP POLICY IF EXISTS "Admins can delete product image slots" ON public.product_image_slots;
CREATE POLICY "Admins can delete product image slots"
    ON public.product_image_slots FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users u
            WHERE u.auth_user_id = auth.uid()
            AND u.is_admin = true
        )
    );

-- ============================================================================
-- 3. Clean up deprecated columns from product_image_assets
-- ============================================================================

ALTER TABLE public.product_image_assets
    DROP COLUMN IF EXISTS mask_path,
    DROP COLUMN IF EXISTS slot_count,
    DROP COLUMN IF EXISTS slot_rects;

-- ============================================================================
-- 4. Comments
-- ============================================================================

COMMENT ON TABLE public.product_image_slots IS
    'Defines album cover compositing slots per product/angle/capacity. Shared across all variants of a product.';
COMMENT ON COLUMN public.product_image_slots.product_id IS
    'FK to products — slot geometry is the same across all variants of a product';
COMMENT ON COLUMN public.product_image_slots.angle IS
    'View angle identifier (e.g., front, angle, top)';
COMMENT ON COLUMN public.product_image_slots.capacity IS
    'Crate fill level affecting album position: full, half, empty. Use "full" for non-crate products.';
COMMENT ON COLUMN public.product_image_slots.slot_data IS
    'JSON with "transform" (4 corner points mapping album to perspective quad) and "clip" (N-point polygon for occlusion clipping). All coordinates in source image pixels.';
