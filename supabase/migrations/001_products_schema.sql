-- ============================================================================
-- Saturday! Admin App - Products and Variants Schema
-- ============================================================================
-- This migration creates tables for products, variants, production steps,
-- device types, and their relationships.
-- ============================================================================

-- Drop existing tables if they exist (in reverse dependency order)
DROP TABLE IF EXISTS public.product_device_types CASCADE;
DROP TABLE IF EXISTS public.production_steps CASCADE;
DROP TABLE IF EXISTS public.product_variants CASCADE;
DROP TABLE IF EXISTS public.device_types CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;

-- ============================================================================
-- PRODUCTS TABLE
-- ============================================================================
CREATE TABLE public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shopify_product_id TEXT NOT NULL UNIQUE,
    shopify_product_handle TEXT NOT NULL,
    name TEXT NOT NULL,
    product_code TEXT NOT NULL UNIQUE,
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    last_synced_at TIMESTAMP WITH TIME ZONE
);

-- Create indexes for products
CREATE INDEX idx_products_shopify_id ON public.products(shopify_product_id);
CREATE INDEX idx_products_handle ON public.products(shopify_product_handle);
CREATE INDEX idx_products_code ON public.products(product_code);
CREATE INDEX idx_products_active ON public.products(is_active);

-- ============================================================================
-- PRODUCT VARIANTS TABLE
-- ============================================================================
CREATE TABLE public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    shopify_variant_id TEXT NOT NULL UNIQUE,
    sku TEXT NOT NULL,
    name TEXT NOT NULL,
    option1_name TEXT,
    option1_value TEXT,
    option2_name TEXT,
    option2_value TEXT,
    option3_name TEXT,
    option3_value TEXT,
    price DECIMAL(10, 2) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create indexes for product variants
CREATE INDEX idx_variants_product_id ON public.product_variants(product_id);
CREATE INDEX idx_variants_shopify_id ON public.product_variants(shopify_variant_id);
CREATE INDEX idx_variants_sku ON public.product_variants(sku);
CREATE INDEX idx_variants_active ON public.product_variants(is_active);

-- ============================================================================
-- DEVICE TYPES TABLE
-- ============================================================================
CREATE TABLE public.device_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    capabilities TEXT[] NOT NULL DEFAULT '{}',
    spec_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now()
);

-- Create indexes for device types
CREATE INDEX idx_device_types_name ON public.device_types(name);
CREATE INDEX idx_device_types_active ON public.device_types(is_active);

-- ============================================================================
-- PRODUCTION STEPS TABLE
-- ============================================================================
CREATE TABLE public.production_steps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    step_order INTEGER NOT NULL,
    file_url TEXT,
    file_name TEXT,
    file_type TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT positive_step_order CHECK (step_order > 0)
);

-- Create indexes for production steps
CREATE INDEX idx_production_steps_product_id ON public.production_steps(product_id);
CREATE INDEX idx_production_steps_order ON public.production_steps(step_order);

-- ============================================================================
-- PRODUCT DEVICE TYPES (JOIN TABLE)
-- ============================================================================
CREATE TABLE public.product_device_types (
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    device_type_id UUID NOT NULL REFERENCES public.device_types(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (product_id, device_type_id),
    CONSTRAINT positive_quantity CHECK (quantity > 0)
);

-- Create indexes for product device types
CREATE INDEX idx_product_devices_product ON public.product_device_types(product_id);
CREATE INDEX idx_product_devices_device ON public.product_device_types(device_type_id);

-- ============================================================================
-- TRIGGERS FOR UPDATED_AT
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for products
CREATE TRIGGER update_products_updated_at
    BEFORE UPDATE ON public.products
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for product_variants
CREATE TRIGGER update_product_variants_updated_at
    BEFORE UPDATE ON public.product_variants
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for device_types
CREATE TRIGGER update_device_types_updated_at
    BEFORE UPDATE ON public.device_types
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for production_steps
CREATE TRIGGER update_production_steps_updated_at
    BEFORE UPDATE ON public.production_steps
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.device_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.production_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_device_types ENABLE ROW LEVEL SECURITY;

-- Products policies
CREATE POLICY "Authenticated users can read products"
    ON public.products FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated users can insert products"
    ON public.products FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update products"
    ON public.products FOR UPDATE
    TO authenticated
    USING (true);

-- Product variants policies
CREATE POLICY "Authenticated users can read variants"
    ON public.product_variants FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated users can insert variants"
    ON public.product_variants FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update variants"
    ON public.product_variants FOR UPDATE
    TO authenticated
    USING (true);

-- Device types policies
CREATE POLICY "Authenticated users can read device types"
    ON public.device_types FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated users can insert device types"
    ON public.device_types FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update device types"
    ON public.device_types FOR UPDATE
    TO authenticated
    USING (true);

-- Production steps policies
CREATE POLICY "Authenticated users can read production steps"
    ON public.production_steps FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated users can insert production steps"
    ON public.production_steps FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update production steps"
    ON public.production_steps FOR UPDATE
    TO authenticated
    USING (true);

-- Product device types policies
CREATE POLICY "Authenticated users can read product device types"
    ON public.product_device_types FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated users can insert product device types"
    ON public.product_device_types FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "Authenticated users can update product device types"
    ON public.product_device_types FOR UPDATE
    TO authenticated
    USING (true);

-- ============================================================================
-- SAMPLE DATA (Optional - for testing)
-- ============================================================================

-- Uncomment to insert sample device types
-- INSERT INTO public.device_types (name, description, capabilities, is_active) VALUES
-- ('ESP32 Audio Controller', 'ESP32-based audio controller with BLE and WiFi', ARRAY['BLE', 'WiFi', 'Thread'], true),
-- ('RFID Reader', 'NFC/RFID reader module', ARRAY['RFID', 'NFC'], true);

-- ============================================================================
-- GRANTS
-- ============================================================================

-- Grant permissions to authenticated users
GRANT SELECT, INSERT, UPDATE ON public.products TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.product_variants TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.device_types TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.production_steps TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.product_device_types TO authenticated;

-- ============================================================================
-- COMPLETION MESSAGE
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Products schema migration completed successfully!';
    RAISE NOTICE 'Created tables:';
    RAISE NOTICE '  - products';
    RAISE NOTICE '  - product_variants';
    RAISE NOTICE '  - device_types';
    RAISE NOTICE '  - production_steps';
    RAISE NOTICE '  - product_device_types';
END $$;
