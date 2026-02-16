-- ============================================================================
-- Migration: 20260125120000_fix_capabilities_rls_policies.sql
-- Description: Fix RLS policies for capabilities table to allow insert/update/delete
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Authenticated users can read capabilities" ON capabilities;
DROP POLICY IF EXISTS "Admins can manage capabilities" ON capabilities;

-- Read policy for authenticated users (SELECT)
CREATE POLICY "Authenticated users can read capabilities"
ON capabilities FOR SELECT
TO authenticated
USING (true);

-- Insert policy for admins
CREATE POLICY "Admins can insert capabilities"
ON capabilities FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_products')
  )
);

-- Update policy for admins
CREATE POLICY "Admins can update capabilities"
ON capabilities FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_products')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_products')
  )
);

-- Delete policy for admins
CREATE POLICY "Admins can delete capabilities"
ON capabilities FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_products')
  )
);
