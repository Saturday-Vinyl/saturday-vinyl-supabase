# Saturday Vinyl Database Schema

> This file should be auto-generated from the live database.
> Generate with: `./scripts/generate-schema-docs.sh`
>
> Requires Docker Desktop to be running (for `supabase db dump`).

## Generation Instructions

From this repo:
```bash
./scripts/generate-schema-docs.sh
```

From a consuming project:
```bash
./shared-supabase/scripts/generate-schema-docs.sh --workdir shared-supabase
```

## Interim Reference

Until this file is generated, refer to:
- `supabase/migrations/README.md` for the full migration history
- `supabase/migrations/*.sql` for table definitions and schema changes
- Run `supabase migration list` to check migration status against the remote
