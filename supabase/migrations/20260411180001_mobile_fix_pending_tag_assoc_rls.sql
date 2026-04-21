-- ============================================================================
-- Migration: 20260411180001_mobile_fix_pending_tag_assoc_rls.sql
-- Project: saturday-mobile-app
-- Description: Fix INSERT RLS policy on pending_tag_associations. The original
--              policy's subquery against units was blocked by RLS on the units
--              table. Simplified to just check user_id ownership.
-- Date: 2026-04-11
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Drop the old policy (may have either name depending on which migration ran)
DROP POLICY IF EXISTS "Users can create pending associations for own hubs" ON pending_tag_associations;
DROP POLICY IF EXISTS "Users can create pending associations" ON pending_tag_associations;

CREATE POLICY "Users can create pending associations"
    ON pending_tag_associations FOR INSERT
    WITH CHECK (user_id = get_user_id_from_auth());
