-- ============================================================================
-- Migration: 20260426183000_mobile_fix_cratelist_creation_rls.sql
-- Project: saturday-mobile-app
-- Description: Fix the same chicken-and-egg problem the libraries flow had:
--              WITH CHECK clauses calling get_user_id_from_auth() do not
--              reliably resolve auth.uid() in INSERT contexts, so creating
--              a cratelist fails RLS. Mirrors the pattern from
--              20240101000006_mobile_fix_library_creation_rls.sql:
--              simplify the cratelists INSERT policy, broaden SELECT so a
--              creator can see their just-created row before the trigger's
--              member row is visible, and allow the creator to add the
--              first owner member explicitly (in case the trigger doesn't
--              bypass RLS in some environments).
-- Date: 2026-04-26
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- CRATELISTS INSERT
-- ============================================================================
DROP POLICY IF EXISTS "Users can create cratelists" ON cratelists;
CREATE POLICY "Users can create cratelists"
    ON cratelists FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- ============================================================================
-- CRATELISTS SELECT
-- ============================================================================
-- Allow the creator to see their just-created cratelist for the brief moment
-- between INSERT and the trigger inserting the owner-member row.
DROP POLICY IF EXISTS "Members can view cratelists" ON cratelists;
CREATE POLICY "Members can view cratelists"
    ON cratelists FOR SELECT
    TO authenticated
    USING (
        is_cratelist_member(id)
        OR EXISTS (
            SELECT 1 FROM users
             WHERE users.id = created_by
               AND users.auth_user_id = auth.uid()
        )
    );

-- ============================================================================
-- CRATELIST_MEMBERS INSERT
-- ============================================================================
-- Existing owners can still add other members. Additionally, allow the
-- creator to add themselves as the first owner so cratelist creation does
-- not depend on the trigger's SECURITY DEFINER bypass.
DROP POLICY IF EXISTS "Owners can add members" ON cratelist_members;
CREATE POLICY "Owners can add members"
    ON cratelist_members FOR INSERT
    TO authenticated
    WITH CHECK (
        is_cratelist_owner(cratelist_id)
        OR (
            EXISTS (
                SELECT 1 FROM users
                 WHERE users.id = user_id
                   AND users.auth_user_id = auth.uid()
            )
            AND role = 'owner'
            AND EXISTS (
                SELECT 1 FROM cratelists c
                JOIN users u ON u.id = c.created_by
                 WHERE c.id = cratelist_id
                   AND u.auth_user_id = auth.uid()
            )
        )
    );
