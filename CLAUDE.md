## Database Schema (Centralized)

All database migrations and edge functions are managed centrally in `shared-supabase/`.
This is a git subtree from [saturday-vinyl-supabase](https://github.com/Saturday-Vinyl/saturday-vinyl-supabase),
shared across all Saturday Vinyl projects.

- **Full schema reference:** `shared-supabase/schema/SCHEMA.md`
- **All migrations:** `shared-supabase/supabase/migrations/`
- **Migration conventions & RLS patterns:** `shared-supabase/CLAUDE.md`
- **Data model concepts:** `shared-docs/concepts/data_model.md`

### CLI Commands

```bash
# List migration status against remote
supabase migration list --workdir shared-supabase

# Check for schema drift
supabase db diff --workdir shared-supabase

# Dry-run pending migrations
supabase db push --workdir shared-supabase --dry-run

# Create a new migration (use your project prefix)
supabase migration new mobile_description --workdir shared-supabase
```

### Pushing migrations to the central repo

```bash
git subtree push --prefix=shared-supabase shared-supabase main
```
