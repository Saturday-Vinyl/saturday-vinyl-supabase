-- ============================================================================
-- Migration: 20260425130000_mobile_cratelist_reorder_fn.sql
-- Project: saturday-mobile-app
-- Description: RPC to reorder cratelist items atomically. Multi-row position
--              updates need to happen in a single SQL statement so the
--              DEFERRABLE UNIQUE (cratelist_id, position) constraint is
--              satisfied only at the end. The Supabase REST client cannot
--              wrap independent updates in a single transaction, so we
--              expose this via RPC.
-- Date: 2026-04-25
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

CREATE OR REPLACE FUNCTION public.reorder_cratelist_items(
    p_cratelist_id UUID,
    p_item_ids     UUID[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
    IF NOT can_edit_cratelist(p_cratelist_id) THEN
        RAISE EXCEPTION 'Not authorized to reorder cratelist %', p_cratelist_id
            USING ERRCODE = '42501';
    END IF;

    -- Sanity-check: every passed item id must belong to this cratelist, and
    -- the array must contain exactly the cratelist's items.
    IF (
        SELECT COUNT(*) FROM cratelist_items WHERE cratelist_id = p_cratelist_id
    ) <> array_length(p_item_ids, 1) THEN
        RAISE EXCEPTION 'reorder list must contain exactly the cratelist''s items';
    END IF;

    IF EXISTS (
        SELECT 1
          FROM unnest(p_item_ids) AS u(item_id)
          LEFT JOIN cratelist_items ci
                 ON ci.id = u.item_id AND ci.cratelist_id = p_cratelist_id
         WHERE ci.id IS NULL
    ) THEN
        RAISE EXCEPTION 'one or more item ids do not belong to cratelist %', p_cratelist_id;
    END IF;

    -- Single statement so the deferrable unique constraint is checked only
    -- once, at end of statement, against the final positions.
    UPDATE cratelist_items ci
       SET position = sub.new_pos
      FROM (
          SELECT u.item_id,
                 u.ordinality::INTEGER AS new_pos
            FROM unnest(p_item_ids) WITH ORDINALITY AS u(item_id, ordinality)
      ) sub
     WHERE ci.id = sub.item_id
       AND ci.cratelist_id = p_cratelist_id;
END;
$function$;
