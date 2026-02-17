## Project Structure

This repo contains firmware for the Saturday Vinyl Hub, a dual-SoC design (ESP32-S3 master + ESP32-H2 Thread co-processor).

**Active firmware — only make changes in these directories:**
- `s3-master/` — ESP32-S3 master firmware (WiFi, cloud, audio, RFID)
- `h2-thread-br/` — ESP32-H2 Thread Border Router co-processor firmware
- `shared/` — Code shared between the two SoCs (S3-H2 binary protocol, common types)

**Deprecated — do not modify:**
- `components/`, `main/`, `CMakeLists.txt` (root), `sdkconfig.defaults`, `partitions.csv` — Old single-SoC ESP32-C6 prototype firmware. Kept for reference only.

**Documentation and shared resources:**
- `shared-docs/` — Protocols, concepts, and prompt references (git subtree)
- `shared-supabase/` — Centralized Supabase migrations and edge functions (git subtree)
- `docs/` — Developer guides

## Building Firmware

The ESP-IDF toolchain is not on PATH by default. Run `get_idf` in the terminal first to set up the environment, then use `idf.py build` from the target directory (`s3-master/` or `h2-thread-br/`).

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
supabase migration new firmware_description --workdir shared-supabase
```

### Pushing migrations to the central repo

```bash
git subtree push --prefix=shared-supabase shared-supabase main
```
