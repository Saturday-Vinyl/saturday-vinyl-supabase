-- ============================================================================
-- Migration: 20260125160000_fix_firmware_files_rls.sql
-- Description: Fix RLS policies for firmware_files to use auth_user_id
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Drop existing policies
DROP POLICY IF EXISTS "Authenticated users can read firmware_files" ON firmware_files;
DROP POLICY IF EXISTS "Admins can manage firmware_files" ON firmware_files;

-- Read policy for authenticated users
CREATE POLICY "Authenticated users can read firmware_files"
ON firmware_files FOR SELECT
TO authenticated
USING (true);

-- Insert policy for admins (using auth_user_id)
CREATE POLICY "Admins can insert firmware_files"
ON firmware_files FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_firmware')
  )
);

-- Update policy for admins
CREATE POLICY "Admins can update firmware_files"
ON firmware_files FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_firmware')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_firmware')
  )
);

-- Delete policy for admins
CREATE POLICY "Admins can delete firmware_files"
ON firmware_files FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND (u.is_admin = true OR p.name = 'manage_firmware')
  )
);
