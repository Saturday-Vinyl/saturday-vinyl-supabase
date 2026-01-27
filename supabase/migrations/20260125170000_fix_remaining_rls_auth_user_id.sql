-- ============================================================================
-- Migration: 20260125170000_fix_remaining_rls_auth_user_id.sql
-- Description: Fix RLS policies to use auth_user_id instead of id for auth.uid() comparison
-- Date: 2026-01-25
-- Idempotent: Yes - safe to run multiple times
--
-- BACKGROUND:
-- The project uses a custom `users` table linked to Supabase's `auth.users` via:
--   users.auth_user_id -> auth.users.id
--
-- Previous migrations incorrectly used `users.id = auth.uid()` which never matches
-- because users.id is the application-level ID, not the Supabase auth UUID.
--
-- TABLES FIXED:
-- - devices
-- - units
-- - device_commands
-- ============================================================================


-- ============================================================================
-- FIX: devices table
-- ============================================================================

DROP POLICY IF EXISTS "Employees with manage_production can manage devices" ON devices;

-- Split FOR ALL into separate policies with proper auth_user_id check

CREATE POLICY "Employees can insert devices"
ON devices FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
    AND (u.is_admin = true OR p.name = 'manage_production')
  )
);

CREATE POLICY "Employees can update devices"
ON devices FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
    AND (u.is_admin = true OR p.name = 'manage_production')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
    AND (u.is_admin = true OR p.name = 'manage_production')
  )
);

CREATE POLICY "Employees can delete devices"
ON devices FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
    AND (u.is_admin = true OR p.name = 'manage_production')
  )
);


-- ============================================================================
-- FIX: units table
-- ============================================================================

DROP POLICY IF EXISTS "Authenticated employees can read all units" ON units;
DROP POLICY IF EXISTS "Employees with manage_production can manage units" ON units;

-- Read policy: employees via users table, OR consumers via direct auth.uid() on user_id
CREATE POLICY "Authenticated employees can read all units"
ON units FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
  )
  OR user_id = auth.uid()  -- Consumers can read their own units
);

-- Employee write access (split into separate policies)
CREATE POLICY "Employees can insert units"
ON units FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
    AND (u.is_admin = true OR p.name = 'manage_production')
  )
);

CREATE POLICY "Employees can update units"
ON units FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
    AND (u.is_admin = true OR p.name = 'manage_production')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
    AND (u.is_admin = true OR p.name = 'manage_production')
  )
);

CREATE POLICY "Employees can delete units"
ON units FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users u
    LEFT JOIN user_permissions up ON up.user_id = u.id
    LEFT JOIN permissions p ON p.id = up.permission_id
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
    AND (u.is_admin = true OR p.name = 'manage_production')
  )
);


-- ============================================================================
-- FIX: device_commands table
-- ============================================================================

DROP POLICY IF EXISTS "Employees can create device_commands" ON device_commands;

CREATE POLICY "Employees can create device_commands"
ON device_commands FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM users u
    WHERE u.auth_user_id = auth.uid()
    AND u.is_active = true
  )
);
