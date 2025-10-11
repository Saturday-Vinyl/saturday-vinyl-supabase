-- Migration: Products and Product Variants
-- Description: Creates tables for products synced from Shopify and their variants
-- Dependencies: None (base tables)

-- =====================================================
-- Products Table
-- =====================================================

CREATE TABLE IF NOT EXISTS products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shopify_product_id VARCHAR(255) UNIQUE NOT NULL, -- Shopify's product ID (gid://shopify/Product/...)
  shopify_product_handle VARCHAR(255) NOT NULL, -- URL-friendly handle from Shopify
  name VARCHAR(255) NOT NULL, -- Product title from Shopify
  product_code VARCHAR(50) UNIQUE NOT NULL, -- Internal product code (e.g., "WALNUT-RECORD-PLAYER")
  description TEXT, -- Product description
  is_active BOOLEAN DEFAULT TRUE NOT NULL, -- Whether product is active in production
  last_synced_at TIMESTAMP WITH TIME ZONE, -- Last time synced from Shopify
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Indexes for products
CREATE INDEX IF NOT EXISTS idx_products_shopify_id ON products(shopify_product_id);
CREATE INDEX IF NOT EXISTS idx_products_handle ON products(shopify_product_handle);
CREATE INDEX IF NOT EXISTS idx_products_code ON products(product_code);
CREATE INDEX IF NOT EXISTS idx_products_active ON products(is_active);

-- =====================================================
-- Product Variants Table
-- =====================================================

CREATE TABLE IF NOT EXISTS product_variants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  shopify_variant_id VARCHAR(255) UNIQUE NOT NULL, -- Shopify's variant ID (gid://shopify/ProductVariant/...)
  sku VARCHAR(100) NOT NULL, -- Stock Keeping Unit
  name VARCHAR(255) NOT NULL, -- Variant name/title

  -- Option 1 (e.g., Wood Species)
  option1_name VARCHAR(100), -- Option name (e.g., "Wood Species")
  option1_value VARCHAR(100), -- Option value (e.g., "Walnut")

  -- Option 2 (e.g., Liner Color)
  option2_name VARCHAR(100), -- Option name (e.g., "Liner Color")
  option2_value VARCHAR(100), -- Option value (e.g., "Black")

  -- Option 3 (e.g., Size)
  option3_name VARCHAR(100), -- Option name (e.g., "Size")
  option3_value VARCHAR(100), -- Option value (e.g., "Large")

  price DECIMAL(10, 2) NOT NULL DEFAULT 0.00, -- Variant price
  is_active BOOLEAN DEFAULT TRUE NOT NULL, -- Whether variant is available for production

  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Indexes for product_variants
CREATE INDEX IF NOT EXISTS idx_product_variants_product_id ON product_variants(product_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_shopify_id ON product_variants(shopify_variant_id);
CREATE INDEX IF NOT EXISTS idx_product_variants_sku ON product_variants(sku);
CREATE INDEX IF NOT EXISTS idx_product_variants_active ON product_variants(is_active);

-- =====================================================
-- Row Level Security (RLS)
-- =====================================================

-- Enable RLS
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants ENABLE ROW LEVEL SECURITY;

-- Products policies
CREATE POLICY "Products are viewable by authenticated users"
  ON products FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Products are insertable by authenticated users"
  ON products FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Products are updatable by authenticated users"
  ON products FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Products are deletable by authenticated users"
  ON products FOR DELETE
  TO authenticated
  USING (true);

-- Product variants policies
CREATE POLICY "Variants are viewable by authenticated users"
  ON product_variants FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Variants are insertable by authenticated users"
  ON product_variants FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Variants are updatable by authenticated users"
  ON product_variants FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Variants are deletable by authenticated users"
  ON product_variants FOR DELETE
  TO authenticated
  USING (true);

-- =====================================================
-- Triggers for updated_at
-- =====================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for products
CREATE TRIGGER update_products_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Trigger for product_variants
CREATE TRIGGER update_product_variants_updated_at
  BEFORE UPDATE ON product_variants
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- Comments
-- =====================================================

COMMENT ON TABLE products IS 'Products synced from Shopify for production tracking';
COMMENT ON TABLE product_variants IS 'Product variants with options and pricing from Shopify';
COMMENT ON COLUMN products.product_code IS 'Internal code used for production unit IDs (e.g., SV-{CODE}-{SEQ})';
COMMENT ON COLUMN product_variants.option1_name IS 'First product option name (e.g., Wood Species, Color, Size)';
COMMENT ON COLUMN product_variants.option1_value IS 'First product option value (e.g., Walnut, Black, Large)';
