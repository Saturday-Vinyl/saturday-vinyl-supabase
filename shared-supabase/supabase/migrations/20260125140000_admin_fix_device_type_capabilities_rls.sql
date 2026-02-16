-- ============================================================================
-- Migration: 20260125140000_fix_device_type_capabilities_rls.sql
-- Description: Fix RLS policies for device_type_capabilities to use auth_user_id
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Authenticated users can read device_type_capabilities" ON device_type_capabilities;
DROP POLICY IF EXISTS "Admins can manage device_type_capabilities" ON device_type_capabilities;

-- Read policy for authenticated users
CREATE POLICY "Authenticated users can read device_type_capabilities"
ON device_type_capabilities FOR SELECT
TO authenticated
USING (true);

-- Insert policy for admins (using auth_user_id)
CREATE POLICY "Admins can insert device_type_capabilities"
ON device_type_capabilities FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_products')
  )
);

-- Update policy for admins
CREATE POLICY "Admins can update device_type_capabilities"
ON device_type_capabilities FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_products')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_products')
  )
);

-- Delete policy for admins
CREATE POLICY "Admins can delete device_type_capabilities"
ON device_type_capabilities FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_products')
  )
);
