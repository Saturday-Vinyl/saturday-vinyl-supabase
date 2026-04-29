-- ============================================================================
-- Migration: 20260426200000_mobile_playback_queue.sql
-- Project: saturday-mobile-app
-- Description: Per-user, persisted, ordered playback queue. Cratelists and
--              the library "Add to queue" action seed it; users can edit
--              the queue independently afterwards. Realtime-published so
--              the same user across devices stays in sync. Duplicates are
--              allowed (no UNIQUE on (user_id, library_album_id)) so the
--              same album can appear twice in a queue.
-- Date: 2026-04-26
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- ============================================================================
-- TABLE
-- ============================================================================
CREATE TABLE IF NOT EXISTS playback_queue (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID NOT NULL REFERENCES users(id)          ON DELETE CASCADE,
    library_album_id UUID NOT NULL REFERENCES library_albums(id) ON DELETE CASCADE,
    position         INTEGER NOT NULL,
    added_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    added_by         UUID REFERENCES users(id)
);

-- Position uniqueness within a user's queue, deferrable so reorder RPC can
-- swap positions in a single statement without intermediate violations.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'playback_queue_user_position_unique'
    ) THEN
        ALTER TABLE playback_queue
            ADD CONSTRAINT playback_queue_user_position_unique
            UNIQUE (user_id, position) DEFERRABLE INITIALLY DEFERRED;
    END IF;
END $$;

-- ============================================================================
-- INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_playback_queue_user_position
    ON playback_queue(user_id, position);

CREATE INDEX IF NOT EXISTS idx_playback_queue_library_album
    ON playback_queue(library_album_id);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
ALTER TABLE playback_queue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own queue" ON playback_queue;
CREATE POLICY "Users can read own queue"
    ON playback_queue FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users
             WHERE users.id = user_id
               AND users.auth_user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can insert into own queue" ON playback_queue;
CREATE POLICY "Users can insert into own queue"
    ON playback_queue FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM users
             WHERE users.id = user_id
               AND users.auth_user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can update own queue" ON playback_queue;
CREATE POLICY "Users can update own queue"
    ON playback_queue FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users
             WHERE users.id = user_id
               AND users.auth_user_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM users
             WHERE users.id = user_id
               AND users.auth_user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can delete from own queue" ON playback_queue;
CREATE POLICY "Users can delete from own queue"
    ON playback_queue FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM users
             WHERE users.id = user_id
               AND users.auth_user_id = auth.uid()
        )
    );

-- ============================================================================
-- REORDER RPC
-- ============================================================================
-- Single-statement positional update so the deferrable unique constraint is
-- satisfied at end-of-statement. Caller must own all item ids.
CREATE OR REPLACE FUNCTION public.reorder_playback_queue(
    p_item_ids UUID[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID;
BEGIN
    v_user_id := get_user_id_from_auth();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    IF (
        SELECT COUNT(*) FROM playback_queue WHERE user_id = v_user_id
    ) <> array_length(p_item_ids, 1) THEN
        RAISE EXCEPTION 'reorder list must contain exactly the queue''s items';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM unnest(p_item_ids) AS u(item_id)
          LEFT JOIN playback_queue pq
                 ON pq.id = u.item_id AND pq.user_id = v_user_id
         WHERE pq.id IS NULL
    ) THEN
        RAISE EXCEPTION 'one or more item ids do not belong to caller''s queue';
    END IF;

    UPDATE playback_queue pq
       SET position = sub.new_pos
      FROM (
          SELECT u.item_id,
                 u.ordinality::INTEGER AS new_pos
            FROM unnest(p_item_ids) WITH ORDINALITY AS u(item_id, ordinality)
      ) sub
     WHERE pq.id = sub.item_id
       AND pq.user_id = v_user_id;
END;
$function$;

-- ============================================================================
-- REALTIME
-- ============================================================================
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables
             WHERE pubname = 'supabase_realtime'
               AND tablename = 'playback_queue'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE playback_queue;
            RAISE NOTICE 'Added playback_queue to supabase_realtime publication';
        END IF;
    END IF;
END$$;
