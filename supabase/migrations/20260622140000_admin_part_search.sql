-- ============================================================================
-- Migration: 20260622140000_admin_part_search.sql
-- Project: saturday-admin-app
-- Description: Functional part search — curated keywords + Postgres full-text
--              search (generated tsvector + GIN index) so parts are findable by
--              function (e.g. "adc", "analog to digital") not just part number.
-- Date: 2026-06-22
-- Idempotent: Yes - safe to run multiple times
-- ============================================================================

-- Curated, human-maintained search terms (functions, aliases, common names).
alter table public.parts
  add column if not exists keywords text[] not null default '{}';

-- Build the weighted search document via an IMMUTABLE helper. A generated
-- column requires a fully IMMUTABLE expression, and array_to_string() is only
-- STABLE -- so inlining it directly fails with "generation expression is not
-- immutable". Wrapping the computation in a function with a declared IMMUTABLE
-- volatility is the standard, safe pattern (inputs are deterministic text).
--   A: part_number, name        (primary identifiers)
--   B: description, keywords    (supporting / functional terms)
create or replace function public.parts_search_document(
  p_part_number text,
  p_name        text,
  p_description text,
  p_keywords    text[]
) returns tsvector
language sql
immutable
parallel safe
as $$
  select setweight(to_tsvector('english', coalesce(p_part_number, '')), 'A')
      || setweight(to_tsvector('english', coalesce(p_name, '')), 'A')
      || setweight(to_tsvector('english', coalesce(p_description, '')), 'B')
      || setweight(to_tsvector('english', array_to_string(coalesce(p_keywords, '{}'), ' ')), 'B');
$$;

-- Weighted full-text search vector, generated/stored so it stays in sync.
alter table public.parts
  add column if not exists search_vector tsvector
  generated always as (
    public.parts_search_document(part_number, name, description, keywords)
  ) stored;

create index if not exists parts_search_vector_idx
  on public.parts using gin (search_vector);
