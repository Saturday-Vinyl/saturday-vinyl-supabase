-- Saturday! Admin App Database Schema
-- This file contains all the table definitions for the admin application

-- ============================================================================
-- USERS TABLE
-- ============================================================================
-- Stores employee user information synced from Google Workspace
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_id TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    full_name TEXT,
    is_admin BOOLEAN NOT NULL DEFAULT false,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_google_id ON public.users(google_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);

-- Enable Row Level Security
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- RLS Policies for users table
-- Allow authenticated users to read all users (we'll handle permissions in app)
-- This avoids infinite recursion when checking if a user is an admin
CREATE POLICY "Authenticated users can read users"
    ON public.users
    FOR SELECT
    TO authenticated
    USING (true);

-- Only allow users to update their own last_login
CREATE POLICY "Users can update own last_login"
    ON public.users
    FOR UPDATE
    USING (auth.jwt() ->> 'email' = email)
    WITH CHECK (auth.jwt() ->> 'email' = email);

-- Allow insert for new users (needed for getOrCreateUser)
CREATE POLICY "Allow insert for authenticated users"
    ON public.users
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.jwt() ->> 'email' = email);

-- ============================================================================
-- PERMISSIONS TABLE
-- ============================================================================
-- Stores available permissions
CREATE TABLE IF NOT EXISTS public.permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Insert default permissions
INSERT INTO public.permissions (name, description) VALUES
    ('manage_products', 'Can create, edit, and delete products'),
    ('manage_firmware', 'Can upload and manage firmware files'),
    ('manage_production', 'Can manage production units and QR codes')
ON CONFLICT (name) DO NOTHING;

-- Enable Row Level Security
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Anyone authenticated can read permissions
CREATE POLICY "Authenticated users can read permissions"
    ON public.permissions
    FOR SELECT
    TO authenticated
    USING (true);

-- ============================================================================
-- USER_PERMISSIONS TABLE (Join table)
-- ============================================================================
-- Maps users to their permissions
CREATE TABLE IF NOT EXISTS public.user_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES public.permissions(id) ON DELETE CASCADE,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    granted_by UUID REFERENCES public.users(id),
    UNIQUE(user_id, permission_id)
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_user_permissions_user_id ON public.user_permissions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_permissions_permission_id ON public.user_permissions(permission_id);

-- Enable Row Level Security
ALTER TABLE public.user_permissions ENABLE ROW LEVEL SECURITY;

-- RLS Policies for user_permissions table
-- Allow authenticated users to read all user permissions
-- (Permission checking is done at the application level)
CREATE POLICY "Authenticated users can read user permissions"
    ON public.user_permissions
    FOR SELECT
    TO authenticated
    USING (true);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Trigger for users table
DROP TRIGGER IF EXISTS update_users_updated_at ON public.users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to get user permissions
CREATE OR REPLACE FUNCTION get_user_permissions(user_email TEXT)
RETURNS TABLE(permission_name TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT p.name
    FROM public.permissions p
    INNER JOIN public.user_permissions up ON p.id = up.permission_id
    INNER JOIN public.users u ON u.id = up.user_id
    WHERE u.email = user_email;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to check if user has permission
CREATE OR REPLACE FUNCTION user_has_permission(user_email TEXT, permission_name TEXT)
RETURNS BOOLEAN AS $$
DECLARE
    user_is_admin BOOLEAN;
    has_perm BOOLEAN;
BEGIN
    -- Check if user is admin (admins have all permissions)
    SELECT is_admin INTO user_is_admin
    FROM public.users
    WHERE email = user_email;

    IF user_is_admin THEN
        RETURN TRUE;
    END IF;

    -- Check if user has the specific permission
    SELECT EXISTS (
        SELECT 1
        FROM public.user_permissions up
        INNER JOIN public.users u ON u.id = up.user_id
        INNER JOIN public.permissions p ON p.id = up.permission_id
        WHERE u.email = user_email
        AND p.name = permission_name
    ) INTO has_perm;

    RETURN has_perm;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- GRANTS
-- ============================================================================

-- Grant usage on tables to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.users TO authenticated;
GRANT SELECT ON public.permissions TO authenticated;
GRANT SELECT ON public.user_permissions TO authenticated;

-- Grant execute on functions
GRANT EXECUTE ON FUNCTION get_user_permissions(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION user_has_permission(TEXT, TEXT) TO authenticated;
