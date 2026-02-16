-- Migration: Fix RLS policies for library creation flow
-- This migration is idempotent - safe to run multiple times
-- Depends on: 20240101000003_create_rls_policies.sql
--
-- Fixes the chicken-and-egg problem where:
-- 1. User creates a library (needs INSERT on libraries)
-- 2. User needs to add themselves as owner (needs INSERT on library_members)
-- 3. But the library_members INSERT policy requires is_library_owner(library_id)
--    which fails because the membership doesn't exist yet

-- ============================================================================
-- FIX LIBRARY_MEMBERS INSERT POLICY
-- ============================================================================
-- Allow users to add themselves as owner when they create the library
-- (i.e., when they are the creator of the library)

DROP POLICY IF EXISTS "Library owners can manage members" ON library_members;

-- Allow library owners to add members
-- Uses direct auth.uid() lookup instead of get_user_id_from_auth() function
-- because auth.uid() is properly available in RLS policy context
CREATE POLICY "Library owners can manage members"
    ON library_members FOR INSERT
    TO authenticated
    WITH CHECK (
        -- Existing owners can add members
        is_library_owner(library_id)
        -- OR the user is adding themselves as owner of a library they created
        OR (
            EXISTS (
                SELECT 1 FROM users WHERE users.id = user_id AND users.auth_user_id = auth.uid()
            )
            AND role = 'owner'
            AND EXISTS (
                SELECT 1 FROM libraries l
                JOIN users u ON u.id = l.created_by
                WHERE l.id = library_id
                AND u.auth_user_id = auth.uid()
            )
        )
    );

-- ============================================================================
-- SIMPLIFIED LIBRARIES INSERT POLICY
-- ============================================================================
-- Any authenticated user can create a library.
-- We don't need ownership verification on INSERT because:
-- 1. The user is authenticated (TO authenticated)
-- 2. The created_by column is set by the app to the user's ID
-- 3. SELECT/UPDATE/DELETE policies enforce ownership for subsequent operations
DROP POLICY IF EXISTS "Users can create libraries" ON libraries;
CREATE POLICY "Users can create libraries"
    ON libraries FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- ============================================================================
-- FIX LIBRARIES SELECT POLICY
-- ============================================================================
-- The existing SELECT policy only allows users to view libraries they are members of.
-- But when creating a library, the .select() call happens BEFORE the user is added
-- as a member. We need to also allow creators to see their libraries.
DROP POLICY IF EXISTS "Users can view libraries they are members of" ON libraries;
CREATE POLICY "Users can view libraries they are members of"
    ON libraries FOR SELECT
    TO authenticated
    USING (
        -- User is a member of the library
        is_library_member(id)
        -- OR user is the creator (for the brief moment between library creation and membership creation)
        OR EXISTS (
            SELECT 1 FROM users
            WHERE users.id = created_by
            AND users.auth_user_id = auth.uid()
        )
    );
