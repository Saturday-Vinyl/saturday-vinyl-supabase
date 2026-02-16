-- Migration: Library Invitations for Saturday Consumer App
-- This migration creates the invitation system for sharing libraries
-- Depends on: 20240101000003_create_rls_policies.sql (for helper functions)

-- ============================================================================
-- INVITATION STATUS ENUM
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'invitation_status') THEN
        CREATE TYPE invitation_status AS ENUM ('pending', 'accepted', 'rejected', 'expired', 'revoked');
    END IF;
END$$;

-- ============================================================================
-- LIBRARY_INVITATIONS TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS library_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    library_id UUID NOT NULL REFERENCES libraries(id) ON DELETE CASCADE,
    invited_email TEXT NOT NULL,
    invited_user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- NULL if user doesn't exist yet
    role library_role NOT NULL DEFAULT 'viewer',
    status invitation_status NOT NULL DEFAULT 'pending',
    token TEXT NOT NULL UNIQUE, -- Secure random token for deep link
    invited_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
    accepted_at TIMESTAMPTZ,
    finalized_user_id UUID REFERENCES users(id) ON DELETE SET NULL -- User who actually accepted (may differ from invited_user_id)
);

-- ============================================================================
-- INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_library_invitations_token ON library_invitations(token);
CREATE INDEX IF NOT EXISTS idx_library_invitations_email ON library_invitations(invited_email);
CREATE INDEX IF NOT EXISTS idx_library_invitations_library ON library_invitations(library_id);
CREATE INDEX IF NOT EXISTS idx_library_invitations_pending ON library_invitations(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_library_invitations_invited_user ON library_invitations(invited_user_id) WHERE invited_user_id IS NOT NULL;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE library_invitations ENABLE ROW LEVEL SECURITY;

-- Library owners can view all invitations for their libraries
DROP POLICY IF EXISTS "Library owners can view invitations" ON library_invitations;
CREATE POLICY "Library owners can view invitations"
    ON library_invitations FOR SELECT
    USING (is_library_owner(library_id));

-- Library owners can create invitations
DROP POLICY IF EXISTS "Library owners can create invitations" ON library_invitations;
CREATE POLICY "Library owners can create invitations"
    ON library_invitations FOR INSERT
    WITH CHECK (is_library_owner(library_id) AND get_user_id_from_auth() = invited_by);

-- Library owners can update invitations (e.g., revoke)
DROP POLICY IF EXISTS "Library owners can update invitations" ON library_invitations;
CREATE POLICY "Library owners can update invitations"
    ON library_invitations FOR UPDATE
    USING (is_library_owner(library_id));

-- Library owners can delete invitations
DROP POLICY IF EXISTS "Library owners can delete invitations" ON library_invitations;
CREATE POLICY "Library owners can delete invitations"
    ON library_invitations FOR DELETE
    USING (is_library_owner(library_id));

-- Invited users can view their own invitations (by email match)
DROP POLICY IF EXISTS "Invited users can view their invitations by email" ON library_invitations;
CREATE POLICY "Invited users can view their invitations by email"
    ON library_invitations FOR SELECT
    USING (
        invited_email = (SELECT email FROM users WHERE id = get_user_id_from_auth())
    );

-- Invited users can view their own invitations (by user_id match)
DROP POLICY IF EXISTS "Invited users can view their invitations by user_id" ON library_invitations;
CREATE POLICY "Invited users can view their invitations by user_id"
    ON library_invitations FOR SELECT
    USING (invited_user_id = get_user_id_from_auth());

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to generate secure invitation token (64 hex characters = 256 bits)
CREATE OR REPLACE FUNCTION generate_invitation_token()
RETURNS TEXT AS $$
BEGIN
    RETURN encode(gen_random_bytes(32), 'hex');
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- INVITATION MANAGEMENT FUNCTIONS
-- ============================================================================

-- Function to create a library invitation
-- This validates inputs and creates the invitation record
CREATE OR REPLACE FUNCTION create_library_invitation(
    p_library_id UUID,
    p_email TEXT,
    p_role library_role,
    p_invited_by UUID
)
RETURNS library_invitations AS $$
DECLARE
    v_invitation library_invitations;
    v_existing_user_id UUID;
    v_library_name TEXT;
BEGIN
    -- Normalize email to lowercase
    p_email := lower(trim(p_email));

    -- Validate email format
    IF p_email !~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$' THEN
        RAISE EXCEPTION 'Invalid email format';
    END IF;

    -- Cannot invite as owner
    IF p_role = 'owner' THEN
        RAISE EXCEPTION 'Cannot invite someone as owner';
    END IF;

    -- Verify inviter is library owner
    IF NOT EXISTS (
        SELECT 1 FROM library_members
        WHERE library_id = p_library_id
        AND user_id = p_invited_by
        AND role = 'owner'
    ) THEN
        RAISE EXCEPTION 'Only library owners can send invitations';
    END IF;

    -- Check if user already exists
    SELECT id INTO v_existing_user_id FROM users WHERE lower(email) = p_email;

    -- Check if user is already a member
    IF v_existing_user_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM library_members
        WHERE library_id = p_library_id AND user_id = v_existing_user_id
    ) THEN
        RAISE EXCEPTION 'User is already a member of this library';
    END IF;

    -- Check for existing pending invitation
    IF EXISTS (
        SELECT 1 FROM library_invitations
        WHERE library_id = p_library_id
        AND lower(invited_email) = p_email
        AND status = 'pending'
        AND expires_at > NOW()
    ) THEN
        RAISE EXCEPTION 'A pending invitation already exists for this email';
    END IF;

    -- Expire any old pending invitations for this email/library combo
    UPDATE library_invitations
    SET status = 'expired'
    WHERE library_id = p_library_id
    AND lower(invited_email) = p_email
    AND status = 'pending';

    -- Create invitation
    INSERT INTO library_invitations (
        library_id,
        invited_email,
        invited_user_id,
        role,
        status,
        token,
        invited_by,
        expires_at
    )
    VALUES (
        p_library_id,
        p_email,
        v_existing_user_id,
        p_role,
        'pending',
        generate_invitation_token(),
        p_invited_by,
        NOW() + INTERVAL '7 days'
    )
    RETURNING * INTO v_invitation;

    RETURN v_invitation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get invitation details by token (public access for deep link preview)
-- This returns enriched data with library and inviter info
CREATE OR REPLACE FUNCTION get_invitation_by_token(p_token TEXT)
RETURNS TABLE (
    invitation_id UUID,
    library_id UUID,
    library_name TEXT,
    library_description TEXT,
    invited_email TEXT,
    role library_role,
    status invitation_status,
    inviter_name TEXT,
    inviter_email TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    is_expired BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        li.id AS invitation_id,
        li.library_id,
        l.name AS library_name,
        l.description AS library_description,
        li.invited_email,
        li.role,
        li.status,
        u.full_name AS inviter_name,
        u.email AS inviter_email,
        li.expires_at,
        li.created_at,
        (li.expires_at < NOW()) AS is_expired
    FROM library_invitations li
    JOIN libraries l ON l.id = li.library_id
    JOIN users u ON u.id = li.invited_by
    WHERE li.token = p_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to accept an invitation by token
-- The accepting user is specified (allows token holder to accept regardless of original email)
CREATE OR REPLACE FUNCTION accept_invitation_by_token(
    p_token TEXT,
    p_accepting_user_id UUID
)
RETURNS library_invitations AS $$
DECLARE
    v_invitation library_invitations;
BEGIN
    -- Find and lock the invitation
    SELECT * INTO v_invitation
    FROM library_invitations
    WHERE token = p_token
    FOR UPDATE;

    IF v_invitation IS NULL THEN
        RAISE EXCEPTION 'Invitation not found';
    END IF;

    IF v_invitation.status != 'pending' THEN
        RAISE EXCEPTION 'Invitation is no longer pending (status: %)', v_invitation.status;
    END IF;

    IF v_invitation.expires_at < NOW() THEN
        -- Mark as expired
        UPDATE library_invitations SET status = 'expired' WHERE id = v_invitation.id;
        RAISE EXCEPTION 'Invitation has expired';
    END IF;

    -- Verify accepting user exists
    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_accepting_user_id) THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    -- Check if user is already a member
    IF EXISTS (
        SELECT 1 FROM library_members
        WHERE library_id = v_invitation.library_id AND user_id = p_accepting_user_id
    ) THEN
        RAISE EXCEPTION 'User is already a member of this library';
    END IF;

    -- Update invitation
    UPDATE library_invitations
    SET
        status = 'accepted',
        accepted_at = NOW(),
        finalized_user_id = p_accepting_user_id
    WHERE id = v_invitation.id
    RETURNING * INTO v_invitation;

    -- Add user to library members
    INSERT INTO library_members (library_id, user_id, role, joined_at, invited_by)
    VALUES (v_invitation.library_id, p_accepting_user_id, v_invitation.role, NOW(), v_invitation.invited_by);

    RETURN v_invitation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to reject an invitation by token
CREATE OR REPLACE FUNCTION reject_invitation_by_token(p_token TEXT)
RETURNS library_invitations AS $$
DECLARE
    v_invitation library_invitations;
BEGIN
    UPDATE library_invitations
    SET status = 'rejected'
    WHERE token = p_token AND status = 'pending'
    RETURNING * INTO v_invitation;

    IF v_invitation IS NULL THEN
        RAISE EXCEPTION 'Invitation not found or not pending';
    END IF;

    RETURN v_invitation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to revoke an invitation (owner action)
CREATE OR REPLACE FUNCTION revoke_invitation(
    p_invitation_id UUID,
    p_user_id UUID
)
RETURNS library_invitations AS $$
DECLARE
    v_invitation library_invitations;
BEGIN
    -- Get invitation and verify ownership
    SELECT li.* INTO v_invitation
    FROM library_invitations li
    JOIN library_members lm ON lm.library_id = li.library_id
    WHERE li.id = p_invitation_id
    AND lm.user_id = p_user_id
    AND lm.role = 'owner'
    FOR UPDATE;

    IF v_invitation IS NULL THEN
        RAISE EXCEPTION 'Invitation not found or you do not have permission to revoke it';
    END IF;

    IF v_invitation.status != 'pending' THEN
        RAISE EXCEPTION 'Only pending invitations can be revoked';
    END IF;

    UPDATE library_invitations
    SET status = 'revoked'
    WHERE id = p_invitation_id
    RETURNING * INTO v_invitation;

    RETURN v_invitation;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- ADDITIONAL HELPER: GET POPULAR ALBUMS
-- ============================================================================

-- Function to get most played albums in a library (for library details screen)
CREATE OR REPLACE FUNCTION get_popular_library_albums(
    p_library_id UUID,
    p_limit INTEGER DEFAULT 5
)
RETURNS TABLE (
    id UUID,
    library_id UUID,
    album_id UUID,
    added_at TIMESTAMPTZ,
    added_by UUID,
    notes TEXT,
    is_favorite BOOLEAN,
    play_count BIGINT,
    -- Album fields
    title TEXT,
    artist TEXT,
    year INTEGER,
    cover_image_url TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        la.id,
        la.library_id,
        la.album_id,
        la.added_at,
        la.added_by,
        la.notes,
        la.is_favorite,
        COALESCE(COUNT(lh.id), 0) AS play_count,
        a.title,
        a.artist,
        a.year,
        a.cover_image_url
    FROM library_albums la
    JOIN albums a ON a.id = la.album_id
    LEFT JOIN listening_history lh ON lh.library_album_id = la.id
    WHERE la.library_id = p_library_id
    GROUP BY la.id, la.library_id, la.album_id, la.added_at, la.added_by,
             la.notes, la.is_favorite, a.title, a.artist, a.year, a.cover_image_url
    ORDER BY play_count DESC, la.added_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
