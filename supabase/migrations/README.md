# Supabase Migrations

This directory contains **all** SQL migration files for the Saturday Vinyl database schema, consolidated from all projects.

## Naming Convention

Migration files use timestamp-based naming with a **project prefix**:

```
YYYYMMDDHHMMSS_{project}_description.sql
```

| Project | Prefix |
|---------|--------|
| saturday-admin-app | `admin` |
| saturday-mobile-app | `mobile` |
| sv-hub-firmware | `firmware` |
| cross-project | `shared` |

Example: `20260207143000_admin_add_production_notes.sql`

## How to Apply Migrations

```bash
# From a consuming project (via subtree):
supabase db push --workdir shared-supabase

# From this repo directly:
supabase db push

# Dry-run (preview only):
supabase db push --dry-run

# List migration status:
supabase migration list

# Generate a new migration:
supabase migration new {project}_description
```

## Migration Requirements

**All migrations MUST be idempotent.** See `CLAUDE.md` in the repo root for full conventions.

## Migration History

| Version | Project | Name | Description |
|---------|---------|------|-------------|
| 20251001000000 | admin | users_and_permissions | Users, permissions, and authentication |
| 20251001010000 | admin | products_schema | Products, variants, device types, production steps |
| 20251002000000 | admin | products_and_variants | Additional product/variant features |
| 20251003000000 | admin | device_types | Adds current_firmware_version to device_types |
| 20251009000000 | admin | production_units | Production units and tracking |
| 20251010000000 | admin | firmware_versions | Firmware version management |
| 20251011000000 | admin | unit_firmware_history | Firmware history tracking |
| 20251012000000 | admin | orders_and_customers | Shopify orders integration |
| 20251013000000 | admin | production_step_labels | Step label system |
| 20251014000000 | admin | production_step_types | Step types and machine integration |
| 20251015000000 | admin | machine_macros | CNC/Laser machine macros |
| 20251016000000 | admin | gcode_path_migration | GCode path migration |
| 20251017000000 | admin | file_library | File library system |
| 20251018000000 | admin | step_timers | Step timer tracking |
| 20251019000000 | admin | rfid_tags | RFID tag management |
| 20251020000000 | admin | rfid_tag_rolls | RFID tag roll batching |
| 20260104000000 | admin | firmware_provisioning | Firmware provisioning step type |
| 20260104010000 | admin | add_esp32_chip_types | ESP32-C6 and H2 chip support |
| 20260105000000 | admin | remove_provisioning_manifest | Remove manifest columns |
| 20260107000000 | admin | thread_credentials | Thread Border Router credentials |
| 20260125000000 | admin | create_capabilities_table | Dynamic device capability definitions |
| 20260125010000 | admin | extend_device_types | Device types extensions |
| 20260125020000 | admin | create_units_table | Unified units table |
| 20260125030000 | admin | create_devices_table | Hardware instances (PCBs with MAC addresses) |
| 20260125040000 | admin | migrate_production_units_data | Data migration to new schema |
| 20260125050000 | admin | rename_and_extend_firmware | Firmware table refactoring |
| 20260125060000 | admin | device_commands_and_heartbeats | Command queue and heartbeat telemetry |
| 20260125070000 | admin | deprecate_old_tables | Mark old tables as deprecated |
| 20260125080000 | admin | add_short_name_to_products | Product short_name field |
| 20260125090000 | admin | consolidate_provision_data | Consolidate provisioning data |
| 20260125120000 | admin | fix_capabilities_rls_policies | Fix RLS policies |
| 20260125130000 | admin | fix_capabilities_rls_auth_user_id | Fix RLS auth_user_id references |
| 20260125140000 | admin | fix_device_type_capabilities_rls | Device type capabilities RLS |
| 20260125150000 | admin | make_firmware_binary_fields_nullable | Nullable firmware binary fields |
| 20260125160000 | admin | fix_firmware_files_rls | Firmware files RLS fixes |
| 20260125170000 | admin | fix_remaining_rls_auth_user_id | Fix remaining RLS auth_user_id |
| 20260126100000 | admin | rename_capability_schema_columns | Capability schema column renaming |
| 20260126110000 | admin | add_device_type_slug | Device type slug field |
| 20260126150000 | admin | add_device_telemetry_and_dashboard_view | Device telemetry dashboard |
| 20260127084309 | admin | heartbeat_schema_v1_2_2 | Heartbeat schema version update |
| 20260127111156 | admin | drop_device_timestamp | Remove device timestamp field |
| 20260127111628 | admin | fix_heartbeat_trigger | Fix heartbeat trigger |
| 20260127122404 | admin | fix_heartbeat_trigger_v2 | Fix heartbeat trigger v2 |
| 20260130163344 | admin | add_heartbeat_command_ack | Add command acknowledgment |
| 20260130181155 | admin | replace_device_type_id_with_slug | Replace device_type_id with slug |
| 20260201000000 | admin | legacy_qr_lookup | Legacy QR code lookup table |
| 20260201000001 | admin | migrate_fks_to_units | Migrate foreign keys to units table |

## Storage Buckets

In addition to database migrations, the following storage buckets are required:

1. **production-files** (Private) - Production step files
2. **qr-codes** (Private) - Generated QR codes
3. **firmware-binaries** (Public) - Device firmware files
