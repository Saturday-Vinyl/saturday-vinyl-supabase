-- ============================================================================
-- Migration: 20260425120000_mobile_cratelists.sql
-- Project: saturday-mobile-app
-- Description: Cratelists are user-curated, ordered, named groupings of albums
--              drawn from one or more libraries the user has access to. They
--              parallel the libraries pattern: created by a user, with their
--              own membership and roles, and items that reference
--              library_albums (so the album must be in some library someone
--              has access to). Adds a permissive RLS policy on library_albums
--              so cratelist members can read referenced items even from
--              libraries they aren't members of.
-- Date: 2026-04-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- TABLES
-- ============================================================================

CREATE TABLE IF NOT EXISTS cratelists (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL CHECK (length(trim(name)) > 0),
    description TEXT,
    created_by  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source      TEXT NOT NULL DEFAULT 'manual'
                  CHECK (source IN ('manual', 'smart', 'saturday')),
    rules       JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cratelist_members (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cratelist_id UUID NOT NULL REFERENCES cratelists(id) ON DELETE CASCADE,
    user_id      UUID NOT NULL REFERENCES users(id)     ON DELETE CASCADE,
    role         library_role NOT NULL DEFAULT 'editor',
    added_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by     UUID REFERENCES users(id),
    UNIQUE (cratelist_id, user_id)
);

CREATE TABLE IF NOT EXISTS cratelist_items (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cratelist_id     UUID NOT NULL REFERENCES cratelists(id)     ON DELETE CASCADE,
    library_album_id UUID NOT NULL REFERENCES library_albums(id) ON DELETE CASCADE,
    position         INTEGER NOT NULL,
    added_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by         UUID REFERENCES users(id),
    UNIQUE (cratelist_id, library_album_id)
);

-- Position uniqueness within a cratelist; deferrable so reorders can swap
-- positions inside a single transaction without intermediate conflicts.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'cratelist_items_position_unique'
    ) THEN
        ALTER TABLE cratelist_items
            ADD CONSTRAINT cratelist_items_position_unique
            UNIQUE (cratelist_id, position) DEFERRABLE INITIALLY DEFERRED;
    END IF;
END $$;

-- ============================================================================
-- INDEXES
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_cratelists_created_by
    ON cratelists(created_by);

CREATE INDEX IF NOT EXISTS idx_cratelist_members_user
    ON cratelist_members(user_id);

CREATE INDEX IF NOT EXISTS idx_cratelist_members_cratelist
    ON cratelist_members(cratelist_id);

CREATE INDEX IF NOT EXISTS idx_cratelist_items_cratelist_position
    ON cratelist_items(cratelist_id, position);

CREATE INDEX IF NOT EXISTS idx_cratelist_items_library_album
    ON cratelist_items(library_album_id);

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_cratelist_member(cl_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM cratelist_members
        WHERE cratelist_id = cl_id
        AND user_id = get_user_id_from_auth()
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.can_edit_cratelist(cl_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM cratelist_members
        WHERE cratelist_id = cl_id
        AND user_id = get_user_id_from_auth()
        AND role IN ('owner', 'editor')
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.is_cratelist_owner(cl_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM cratelist_members
        WHERE cratelist_id = cl_id
        AND user_id = get_user_id_from_auth()
        AND role = 'owner'
    );
END;
$function$;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- When a cratelist is created, add the creator as an owner member.
CREATE OR REPLACE FUNCTION public.handle_new_cratelist()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO cratelist_members (cratelist_id, user_id, role, added_by)
    VALUES (NEW.id, NEW.created_by, 'owner', NEW.created_by)
    ON CONFLICT (cratelist_id, user_id) DO NOTHING;
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_handle_new_cratelist ON cratelists;
CREATE TRIGGER trg_handle_new_cratelist
    AFTER INSERT ON cratelists
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_cratelist();

-- Keep updated_at fresh on cratelist updates.
CREATE OR REPLACE FUNCTION public.touch_cratelist_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_touch_cratelist_updated_at ON cratelists;
CREATE TRIGGER trg_touch_cratelist_updated_at
    BEFORE UPDATE ON cratelists
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_cratelist_updated_at();

-- Bump parent cratelist updated_at when items change (add/remove/reorder).
CREATE OR REPLACE FUNCTION public.touch_cratelist_from_item()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    UPDATE cratelists
       SET updated_at = NOW()
     WHERE id = COALESCE(NEW.cratelist_id, OLD.cratelist_id);
    RETURN COALESCE(NEW, OLD);
END;
$function$;

DROP TRIGGER IF EXISTS trg_touch_cratelist_from_item ON cratelist_items;
CREATE TRIGGER trg_touch_cratelist_from_item
    AFTER INSERT OR UPDATE OR DELETE ON cratelist_items
    FOR EACH ROW
    EXECUTE FUNCTION public.touch_cratelist_from_item();

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

ALTER TABLE cratelists        ENABLE ROW LEVEL SECURITY;
ALTER TABLE cratelist_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE cratelist_items   ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- cratelists
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can view cratelists" ON cratelists;
CREATE POLICY "Members can view cratelists"
    ON cratelists FOR SELECT
    USING (is_cratelist_member(id));

DROP POLICY IF EXISTS "Users can create cratelists" ON cratelists;
CREATE POLICY "Users can create cratelists"
    ON cratelists FOR INSERT
    WITH CHECK (get_user_id_from_auth() = created_by);

DROP POLICY IF EXISTS "Editors can update cratelists" ON cratelists;
CREATE POLICY "Editors can update cratelists"
    ON cratelists FOR UPDATE
    USING (can_edit_cratelist(id));

DROP POLICY IF EXISTS "Owners can delete cratelists" ON cratelists;
CREATE POLICY "Owners can delete cratelists"
    ON cratelists FOR DELETE
    USING (is_cratelist_owner(id));

-- ----------------------------------------------------------------------------
-- cratelist_members
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can view co-members" ON cratelist_members;
CREATE POLICY "Members can view co-members"
    ON cratelist_members FOR SELECT
    USING (is_cratelist_member(cratelist_id));

DROP POLICY IF EXISTS "Owners can add members" ON cratelist_members;
CREATE POLICY "Owners can add members"
    ON cratelist_members FOR INSERT
    WITH CHECK (is_cratelist_owner(cratelist_id));

DROP POLICY IF EXISTS "Owners can update member roles" ON cratelist_members;
CREATE POLICY "Owners can update member roles"
    ON cratelist_members FOR UPDATE
    USING (is_cratelist_owner(cratelist_id));

DROP POLICY IF EXISTS "Owners can remove members" ON cratelist_members;
CREATE POLICY "Owners can remove members"
    ON cratelist_members FOR DELETE
    USING (is_cratelist_owner(cratelist_id));

-- Allow users to leave a cratelist they don't own (parallels libraries).
DROP POLICY IF EXISTS "Users can leave cratelists" ON cratelist_members;
CREATE POLICY "Users can leave cratelists"
    ON cratelist_members FOR DELETE
    USING (user_id = get_user_id_from_auth() AND role != 'owner');

-- ----------------------------------------------------------------------------
-- cratelist_items
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can view cratelist items" ON cratelist_items;
CREATE POLICY "Members can view cratelist items"
    ON cratelist_items FOR SELECT
    USING (is_cratelist_member(cratelist_id));

-- Editors can add items, but only items they themselves can read in
-- library_albums (i.e. they're a member of that library, OR a member of some
-- cratelist that already references that library_album). RLS on
-- library_albums enforces this transparently when the row is fetched, but we
-- also gate the INSERT here for clarity.
DROP POLICY IF EXISTS "Editors can add cratelist items" ON cratelist_items;
CREATE POLICY "Editors can add cratelist items"
    ON cratelist_items FOR INSERT
    WITH CHECK (
        can_edit_cratelist(cratelist_id)
        AND EXISTS (
            SELECT 1 FROM library_albums la
            WHERE la.id = cratelist_items.library_album_id
        )
    );

DROP POLICY IF EXISTS "Editors can update cratelist items" ON cratelist_items;
CREATE POLICY "Editors can update cratelist items"
    ON cratelist_items FOR UPDATE
    USING (can_edit_cratelist(cratelist_id));

DROP POLICY IF EXISTS "Editors can remove cratelist items" ON cratelist_items;
CREATE POLICY "Editors can remove cratelist items"
    ON cratelist_items FOR DELETE
    USING (can_edit_cratelist(cratelist_id));

-- ----------------------------------------------------------------------------
-- Cross-library visibility for cratelist members
--
-- Cratelists can reference library_albums from libraries that not every
-- cratelist member belongs to. Add a permissive (additive) SELECT policy on
-- library_albums so cratelist members can read items referenced by any
-- cratelist they belong to. The original "Users can view albums in their
-- libraries" policy still applies; Postgres ORs them together.
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Cratelist members can view referenced library albums" ON library_albums;
CREATE POLICY "Cratelist members can view referenced library albums"
    ON library_albums FOR SELECT
    USING (
        EXISTS (
            SELECT 1
              FROM cratelist_items ci
              JOIN cratelist_members cm ON cm.cratelist_id = ci.cratelist_id
             WHERE ci.library_album_id = library_albums.id
               AND cm.user_id = get_user_id_from_auth()
        )
    );
