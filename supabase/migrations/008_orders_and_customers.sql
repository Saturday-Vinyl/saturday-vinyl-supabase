-- Migration 008: Orders and Customers
-- Created: 2025-10-10
-- Description: Create customers, orders, and order_line_items tables for Shopify order sync

-- =====================================================
-- Customers Table
-- =====================================================

CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shopify_customer_id VARCHAR(255) UNIQUE NOT NULL, -- Shopify customer ID (gid://shopify/Customer/...)
  email VARCHAR(255) NOT NULL,
  first_name VARCHAR(100),
  last_name VARCHAR(100),
  phone VARCHAR(50),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Indexes for customers
CREATE INDEX IF NOT EXISTS idx_customers_shopify_id ON customers(shopify_customer_id);
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);

-- =====================================================
-- Orders Table
-- =====================================================

CREATE TABLE IF NOT EXISTS orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shopify_order_id VARCHAR(255) UNIQUE NOT NULL, -- Shopify order ID (gid://shopify/Order/...)
  shopify_order_number VARCHAR(50) NOT NULL, -- Human-readable order number (e.g., "#1001")
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL, -- Link to customer
  order_date TIMESTAMP WITH TIME ZONE NOT NULL, -- Order creation date from Shopify
  status VARCHAR(50) NOT NULL, -- Order status (e.g., "open", "closed", "cancelled")
  fulfillment_status VARCHAR(50), -- Fulfillment status (e.g., "unfulfilled", "fulfilled", "partial")
  financial_status VARCHAR(50), -- Payment status (e.g., "paid", "pending", "authorized")
  tags TEXT[], -- Order tags from Shopify as array
  total_price VARCHAR(100), -- Total order price with currency (e.g., "USD 99.99")
  assigned_unit_id UUID REFERENCES production_units(id) ON DELETE SET NULL, -- Link to production unit if assigned
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Add new columns if they don't exist (for existing tables)
DO $$
BEGIN
  -- Add financial_status to orders if it doesn't exist
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='orders' AND column_name='financial_status') THEN
    ALTER TABLE orders ADD COLUMN financial_status VARCHAR(50);
  END IF;

  -- Add tags to orders if it doesn't exist
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='orders' AND column_name='tags') THEN
    ALTER TABLE orders ADD COLUMN tags TEXT[];
  END IF;

  -- Add total_price to orders if it doesn't exist
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='orders' AND column_name='total_price') THEN
    ALTER TABLE orders ADD COLUMN total_price VARCHAR(100);
  END IF;
END $$;

-- Indexes for orders
CREATE INDEX IF NOT EXISTS idx_orders_shopify_id ON orders(shopify_order_id);
CREATE INDEX IF NOT EXISTS idx_orders_shopify_order_number ON orders(shopify_order_number);
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_order_date ON orders(order_date);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_fulfillment_status ON orders(fulfillment_status);
CREATE INDEX IF NOT EXISTS idx_orders_assigned_unit_id ON orders(assigned_unit_id);

-- =====================================================
-- Order Line Items Table
-- =====================================================

CREATE TABLE IF NOT EXISTS order_line_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id UUID REFERENCES products(id) ON DELETE SET NULL, -- Link to internal product (null if not matched)
  variant_id UUID REFERENCES product_variants(id) ON DELETE SET NULL, -- Link to internal variant (null if not matched)
  shopify_product_id VARCHAR(255) NOT NULL, -- Shopify product ID for matching
  shopify_variant_id VARCHAR(255) NOT NULL, -- Shopify variant ID for matching
  title VARCHAR(255) NOT NULL, -- Product title from Shopify
  quantity INTEGER NOT NULL DEFAULT 1,
  price VARCHAR(50), -- Price as string (for display)
  variant_title VARCHAR(255), -- Variant title from Shopify (e.g., "Quarter Sawn White Oak / Natural Wool")
  variant_options TEXT, -- Formatted variant options (e.g., "Wood: Walnut, Liner: Black")
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Add new columns to order_line_items if they don't exist (for existing tables)
DO $$
BEGIN
  -- Add variant_title to order_line_items if it doesn't exist
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='order_line_items' AND column_name='variant_title') THEN
    ALTER TABLE order_line_items ADD COLUMN variant_title VARCHAR(255);
  END IF;

  -- Add variant_options to order_line_items if it doesn't exist
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_name='order_line_items' AND column_name='variant_options') THEN
    ALTER TABLE order_line_items ADD COLUMN variant_options TEXT;
  END IF;
END $$;

-- Indexes for order_line_items
CREATE INDEX IF NOT EXISTS idx_order_line_items_order_id ON order_line_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_product_id ON order_line_items(product_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_variant_id ON order_line_items(variant_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_shopify_product_id ON order_line_items(shopify_product_id);
CREATE INDEX IF NOT EXISTS idx_order_line_items_shopify_variant_id ON order_line_items(shopify_variant_id);

-- =====================================================
-- Row Level Security (RLS)
-- =====================================================

-- Enable RLS (safe to run multiple times)
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_line_items ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to make migration idempotent)
DROP POLICY IF EXISTS "Customers are viewable by authenticated users" ON customers;
DROP POLICY IF EXISTS "Customers are insertable by authenticated users" ON customers;
DROP POLICY IF EXISTS "Customers are updatable by authenticated users" ON customers;
DROP POLICY IF EXISTS "Customers are deletable by authenticated users" ON customers;

DROP POLICY IF EXISTS "Orders are viewable by authenticated users" ON orders;
DROP POLICY IF EXISTS "Orders are insertable by authenticated users" ON orders;
DROP POLICY IF EXISTS "Orders are updatable by authenticated users" ON orders;
DROP POLICY IF EXISTS "Orders are deletable by authenticated users" ON orders;

DROP POLICY IF EXISTS "Order line items are viewable by authenticated users" ON order_line_items;
DROP POLICY IF EXISTS "Order line items are insertable by authenticated users" ON order_line_items;
DROP POLICY IF EXISTS "Order line items are updatable by authenticated users" ON order_line_items;
DROP POLICY IF EXISTS "Order line items are deletable by authenticated users" ON order_line_items;

-- Customers policies
CREATE POLICY "Customers are viewable by authenticated users"
  ON customers FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Customers are insertable by authenticated users"
  ON customers FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Customers are updatable by authenticated users"
  ON customers FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Customers are deletable by authenticated users"
  ON customers FOR DELETE
  TO authenticated
  USING (true);

-- Orders policies
CREATE POLICY "Orders are viewable by authenticated users"
  ON orders FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Orders are insertable by authenticated users"
  ON orders FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Orders are updatable by authenticated users"
  ON orders FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Orders are deletable by authenticated users"
  ON orders FOR DELETE
  TO authenticated
  USING (true);

-- Order line items policies
CREATE POLICY "Order line items are viewable by authenticated users"
  ON order_line_items FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Order line items are insertable by authenticated users"
  ON order_line_items FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Order line items are updatable by authenticated users"
  ON order_line_items FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);

CREATE POLICY "Order line items are deletable by authenticated users"
  ON order_line_items FOR DELETE
  TO authenticated
  USING (true);

-- =====================================================
-- Triggers for updated_at
-- =====================================================

-- Trigger for customers
CREATE TRIGGER update_customers_updated_at
  BEFORE UPDATE ON customers
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Trigger for orders
CREATE TRIGGER update_orders_updated_at
  BEFORE UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- Comments for documentation
-- =====================================================

COMMENT ON TABLE customers IS 'Customer information synced from Shopify';
COMMENT ON COLUMN customers.shopify_customer_id IS 'Shopify customer ID (gid://shopify/Customer/...)';
COMMENT ON COLUMN customers.email IS 'Customer email address';
COMMENT ON COLUMN customers.first_name IS 'Customer first name';
COMMENT ON COLUMN customers.last_name IS 'Customer last name';
COMMENT ON COLUMN customers.phone IS 'Customer phone number';

COMMENT ON TABLE orders IS 'Orders synced from Shopify for production tracking';
COMMENT ON COLUMN orders.shopify_order_id IS 'Shopify order ID (gid://shopify/Order/...)';
COMMENT ON COLUMN orders.shopify_order_number IS 'Human-readable order number (e.g., "#1001")';
COMMENT ON COLUMN orders.customer_id IS 'Reference to customer who placed the order';
COMMENT ON COLUMN orders.order_date IS 'Timestamp when order was created in Shopify';
COMMENT ON COLUMN orders.status IS 'Order status from Shopify (e.g., "open", "closed", "cancelled")';
COMMENT ON COLUMN orders.fulfillment_status IS 'Fulfillment status from Shopify (e.g., "unfulfilled", "fulfilled")';
COMMENT ON COLUMN orders.financial_status IS 'Payment status from Shopify (e.g., "paid", "pending", "authorized")';
COMMENT ON COLUMN orders.tags IS 'Order tags from Shopify as text array';
COMMENT ON COLUMN orders.total_price IS 'Total order price with currency (e.g., "USD 99.99")';
COMMENT ON COLUMN orders.assigned_unit_id IS 'Production unit assigned to fulfill this order (null if not yet assigned)';

COMMENT ON TABLE order_line_items IS 'Line items (products) from Shopify orders';
COMMENT ON COLUMN order_line_items.order_id IS 'Reference to the parent order';
COMMENT ON COLUMN order_line_items.product_id IS 'Reference to internal product (null if product not matched)';
COMMENT ON COLUMN order_line_items.variant_id IS 'Reference to internal variant (null if variant not matched)';
COMMENT ON COLUMN order_line_items.shopify_product_id IS 'Shopify product ID for matching to internal products';
COMMENT ON COLUMN order_line_items.shopify_variant_id IS 'Shopify variant ID for matching to internal variants';
COMMENT ON COLUMN order_line_items.title IS 'Product title as displayed in Shopify';
COMMENT ON COLUMN order_line_items.quantity IS 'Quantity of this item ordered';
COMMENT ON COLUMN order_line_items.price IS 'Price per unit as string (for display purposes)';
COMMENT ON COLUMN order_line_items.variant_title IS 'Variant title from Shopify (e.g., "Quarter Sawn White Oak / Natural Wool")';
COMMENT ON COLUMN order_line_items.variant_options IS 'Formatted variant options for easy display (e.g., "Wood: Walnut, Liner: Black")';
