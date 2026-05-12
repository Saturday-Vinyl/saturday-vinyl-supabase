# Saturday Vinyl Database Schema

> Generated from live Supabase database on 2026-05-12.
> Regenerate with: `./scripts/generate-schema-docs.sh`

## Table of Contents

- [Users & Authentication](#users-authentication)
- [Products & Variants](#products-variants)
- [Device Types & Capabilities](#device-types-capabilities)
- [Units & Devices](#units-devices)
- [Production & Manufacturing](#production-manufacturing)
- [Firmware](#firmware)
- [Device Communication](#device-communication)
- [Orders & Customers](#orders-customers)
- [RFID Tags](#rfid-tags)
- [Albums & Libraries](#albums-libraries)
- [Notifications](#notifications)
- [Files & GCode](#files-gcode)
- [Networking](#networking)
- [Deprecated Tables](#deprecated-tables)

---

## Users & Authentication

### users
Application-level user accounts (linked to Supabase Auth via `auth_user_id`).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| google_id | text |  |  | UNIQUE |
| email | text | NOT NULL |  | UNIQUE |
| full_name | text |  |  |  |
| is_admin | boolean | NOT NULL | false |  |
| is_active | boolean | NOT NULL | true |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| last_login | timestamp with time zone |  |  |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| avatar_url | text |  |  |  |
| preferences | jsonb |  | {} |  |
| auth_user_id | uuid |  |  | FK -> users(id) |

### permissions
Permission definitions for role-based access control.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL |  | UNIQUE |
| description | text |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### user_permissions
Join table linking users to permissions.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| permission_id | uuid | NOT NULL |  | UNIQUE, FK -> permissions(id) |
| granted_at | timestamp with time zone | NOT NULL | now() |  |
| granted_by | uuid |  |  | FK -> users(id) |

---

## Products & Variants

### products
Product definitions (synced from Shopify).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| shopify_product_id | text | NOT NULL |  | UNIQUE |
| shopify_product_handle | text | NOT NULL |  |  |
| name | text | NOT NULL |  |  |
| product_code | text | NOT NULL |  | UNIQUE |
| description | text |  |  |  |
| is_active | boolean | NOT NULL | true |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| last_synced_at | timestamp with time zone |  |  |  |
| short_name | character varying(50) |  |  |  |

### product_variants
Product variant options (synced from Shopify).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| product_id | uuid | NOT NULL |  | FK -> products(id) |
| shopify_variant_id | text | NOT NULL |  | UNIQUE |
| sku | text | NOT NULL |  |  |
| name | text | NOT NULL |  |  |
| option1_name | text |  |  |  |
| option1_value | text |  |  |  |
| option2_name | text |  |  |  |
| option2_value | text |  |  |  |
| option3_name | text |  |  |  |
| option3_value | text |  |  |  |
| price | numeric(10,2) | NOT NULL |  |  |
| is_active | boolean | NOT NULL | true |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| max_slots | integer |  |  |  |

### product_device_types
Maps products to the device types they contain.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| product_id | uuid | NOT NULL |  | PK, FK -> products(id) |
| device_type_id | uuid | NOT NULL |  | PK, FK -> device_types(id) |
| quantity | integer | NOT NULL | 1 | CHECK quantity > 0 |

---

## Device Types & Capabilities

### device_types
Hardware device type templates (e.g., "Hub", "Satellite").

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL |  |  |
| description | text |  |  |  |
| capabilities | text[] | NOT NULL | {} |  |
| spec_url | text |  |  |  |
| is_active | boolean | NOT NULL | true |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| current_firmware_version | character varying(50) |  |  |  |
| chip_type | character varying(20) |  |  | CHECK chip_type IS NULL OR (chip_type::text = ANY (ARRAY['esp32'::character varying, 'esp32s2'::character varying, 'esp32s3'::character varying, 'esp32c3'::character varying, 'esp32c6'::character varying, 'esp32h2'::character varying]::text[])) |
| soc_types | text[] |  | {} |  |
| master_soc | character varying(50) |  |  |  |
| production_firmware_id | uuid |  |  | FK -> firmware(id) |
| dev_firmware_id | uuid |  |  | FK -> firmware(id) |
| slug | character varying(100) | NOT NULL |  | CHECK slug::text ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text |

### capabilities
Dynamic capability definitions with JSON schemas for provisioning and telemetry.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | character varying(100) | NOT NULL |  | UNIQUE |
| display_name | character varying(100) | NOT NULL |  |  |
| description | text |  |  |  |
| factory_input_schema | jsonb |  | {} |  |
| factory_output_schema | jsonb |  | {} |  |
| consumer_input_schema | jsonb |  | {} |  |
| consumer_output_schema | jsonb |  | {} |  |
| heartbeat_schema | jsonb |  | {} |  |
| commands | jsonb |  | [] |  |
| is_active | boolean |  | true |  |
| created_at | timestamp with time zone |  | now() |  |
| updated_at | timestamp with time zone |  | now() |  |

### device_type_capabilities
Maps device types to their capabilities with configuration.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| device_type_id | uuid | NOT NULL |  | UNIQUE, FK -> device_types(id) |
| capability_id | uuid | NOT NULL |  | UNIQUE, FK -> capabilities(id) |
| configuration | jsonb |  | {} |  |
| display_order | integer |  | 0 |  |
| created_at | timestamp with time zone |  | now() |  |

---

## Units & Devices

### units
Unified table for manufactured product instances (factory + consumer lifecycle).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| serial_number | character varying(100) |  |  | UNIQUE |
| product_id | uuid |  |  | FK -> products(id) |
| variant_id | uuid |  |  | FK -> product_variants(id) |
| order_id | uuid |  |  | FK -> orders(id) |
| factory_provisioned_at | timestamp with time zone |  |  |  |
| factory_provisioned_by | uuid |  |  | FK -> users(id) |
| consumer_user_id | uuid |  |  |  |
| consumer_name | character varying(255) |  |  |  |
| status | unit_status |  | in_production | Enum |
| production_started_at | timestamp with time zone |  |  |  |
| production_completed_at | timestamp with time zone |  |  |  |
| is_completed | boolean |  | false |  |
| qr_code_url | text |  |  |  |
| created_at | timestamp with time zone |  | now() |  |
| updated_at | timestamp with time zone |  | now() |  |
| created_by | uuid |  |  | FK -> users(id) |
| battery_level | integer |  |  | CHECK battery_level IS NULL OR battery_level >= 0 AND battery_level <= 100 |
| is_charging | boolean |  |  |  |
| last_seen_at | timestamp with time zone |  |  |  |
| is_online | boolean |  | false |  |
| wifi_rssi | integer |  |  |  |
| temperature_c | numeric |  |  |  |
| humidity_pct | numeric |  |  |  |
| firmware_version | text |  |  |  |

### devices
Hardware instances (PCBs identified by MAC address).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| mac_address | character varying(17) | NOT NULL |  | UNIQUE |
| unit_id | uuid |  |  | FK -> units(id) |
| firmware_version | character varying(50) |  |  |  |
| firmware_id | uuid |  |  | FK -> firmware(id) |
| factory_provisioned_at | timestamp with time zone |  |  |  |
| factory_provisioned_by | uuid |  |  | FK -> users(id) |
| status | character varying(50) |  | unprovisioned |  |
| last_seen_at | timestamp with time zone |  |  |  |
| created_at | timestamp with time zone |  | now() |  |
| updated_at | timestamp with time zone |  | now() |  |
| provision_data | jsonb |  | {} |  |
| latest_telemetry | jsonb |  | {} |  |
| device_type_slug | character varying(100) |  |  | FK -> device_types(slug) |
| consumer_provisioned_at | timestamp with time zone |  |  |  |
| consumer_provisioned_by | uuid |  |  | FK -> users(id) |
| hub_mac_address | character varying(17) |  |  |  |

### consumer_devices
Consumer-facing device instances (registered by end users in the mobile app).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | FK -> users(id) |
| device_type | consumer_device_type | NOT NULL |  | Enum |
| name | text | NOT NULL |  |  |
| serial_number | text | NOT NULL |  | UNIQUE |
| production_unit_id | uuid |  |  | FK -> production_units(id) |
| firmware_version | text |  |  |  |
| status | consumer_device_status | NOT NULL | offline | Enum |
| battery_level | integer |  |  | CHECK battery_level >= 0 AND battery_level <= 100 |
| last_seen_at | timestamp with time zone |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| settings | jsonb |  | {} |  |

---

## Production & Manufacturing

### production_steps
Step definitions for product assembly workflows.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| product_id | uuid | NOT NULL |  | FK -> products(id) |
| name | text | NOT NULL |  |  |
| description | text |  |  |  |
| step_order | integer | NOT NULL |  | CHECK step_order > 0 |
| file_url | text |  |  |  |
| file_name | text |  |  |  |
| file_type | text |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| generate_label | boolean | NOT NULL | false |  |
| label_text | text |  |  |  |
| step_type | step_type | NOT NULL | general | Enum |
| engrave_qr | boolean | NOT NULL | false |  |
| qr_x_offset | numeric(10,3) |  |  |  |
| qr_y_offset | numeric(10,3) |  |  |  |
| qr_size | numeric(10,3) |  |  | CHECK qr_size IS NULL OR qr_size > 0::numeric |
| qr_power_percent | integer |  |  | CHECK qr_power_percent IS NULL OR qr_power_percent >= 0 AND qr_power_percent <= 100 |
| qr_speed_mm_min | integer |  |  | CHECK qr_speed_mm_min IS NULL OR qr_speed_mm_min > 0 |
| firmware_version_id | uuid |  |  | FK -> firmware(id) |
| provisioning_manifest | jsonb |  |  |  |

### unit_step_completions
Tracks which steps have been completed for each unit.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | extensions.uuid_generate_v4() | PK |
| unit_id | uuid | NOT NULL |  | UNIQUE, FK -> units(id) |
| step_id | uuid | NOT NULL |  | UNIQUE, FK -> production_steps(id) |
| completed_at | timestamp with time zone |  | now() |  |
| completed_by | uuid | NOT NULL |  | FK -> users(id) |
| notes | text |  |  |  |

### step_labels
Labels associated with production steps.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| step_id | uuid | NOT NULL |  | FK -> production_steps(id) |
| label_text | text | NOT NULL |  |  |
| label_order | integer | NOT NULL | 1 | CHECK label_order > 0 |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### step_timers
Timer definitions for production steps (curing, drying, etc.).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| step_id | uuid | NOT NULL |  | FK -> production_steps(id) |
| timer_name | text | NOT NULL |  |  |
| duration_minutes | integer | NOT NULL |  | CHECK duration_minutes > 0 |
| timer_order | integer | NOT NULL | 1 | CHECK timer_order > 0 |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### unit_timers
Active timer instances for specific units.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| unit_id | uuid | NOT NULL |  | FK -> units(id) |
| step_timer_id | uuid | NOT NULL |  | FK -> step_timers(id) |
| started_at | timestamp with time zone | NOT NULL |  |  |
| expires_at | timestamp with time zone | NOT NULL |  |  |
| completed_at | timestamp with time zone |  |  |  |
| status | text | NOT NULL | active | CHECK status = ANY (ARRAY['active'::text, 'completed'::text, 'cancelled'::text]) |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### machine_macros
CNC and laser machine macro definitions.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL |  | CHECK length(TRIM(BOTH FROM name)) > 0 |
| description | text |  |  |  |
| machine_type | text | NOT NULL |  | CHECK machine_type = ANY (ARRAY['cnc'::text, 'laser'::text]) |
| icon_name | text | NOT NULL |  | CHECK length(TRIM(BOTH FROM icon_name)) > 0 |
| gcode_commands | text | NOT NULL |  | CHECK length(TRIM(BOTH FROM gcode_commands)) > 0 |
| execution_order | integer | NOT NULL | 1 | CHECK execution_order > 0 |
| is_active | boolean | NOT NULL | true |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

---

## Firmware

### firmware
Firmware version records.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | extensions.uuid_generate_v4() | PK |
| device_type_id | uuid | NOT NULL |  | UNIQUE, FK -> device_types(id) |
| version | character varying(50) | NOT NULL |  | UNIQUE |
| release_notes | text |  |  |  |
| binary_url | text |  |  |  |
| binary_filename | character varying(255) |  |  |  |
| binary_size | bigint |  |  |  |
| is_production_ready | boolean |  | false |  |
| created_at | timestamp with time zone |  | now() |  |
| created_by | uuid |  |  | FK -> users(id) |
| provisioning_manifest | jsonb |  |  |  |
| is_critical | boolean |  | false |  |
| released_at | timestamp with time zone |  |  |  |

### firmware_files
Per-SoC firmware binary files (for multi-SoC devices).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| firmware_id | uuid | NOT NULL |  | UNIQUE, FK -> firmware(id) |
| soc_type | character varying(50) | NOT NULL |  | UNIQUE |
| is_master | boolean |  | false |  |
| file_url | text | NOT NULL |  |  |
| file_sha256 | text |  |  |  |
| file_size | integer |  |  |  |
| created_at | timestamp with time zone |  | now() |  |
| flash_offset | integer |  | 0 |  |
| purpose | text | NOT NULL | factory | UNIQUE, CHECK purpose = ANY (ARRAY['factory'::text, 'ota'::text]) |

---

## Device Communication

### device_commands
Command queue for device operations (provision, test, reboot, OTA, etc.).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| mac_address | character varying(17) | NOT NULL |  |  |
| command | text | NOT NULL |  |  |
| capability | text |  |  |  |
| test_name | text |  |  |  |
| parameters | jsonb |  | {} |  |
| priority | integer |  | 0 |  |
| status | text |  | pending |  |
| expires_at | timestamp with time zone |  |  |  |
| result | jsonb |  |  |  |
| error_message | text |  |  |  |
| retry_count | integer |  | 0 |  |
| created_at | timestamp with time zone |  | now() |  |
| updated_at | timestamp with time zone |  | now() |  |
| created_by | uuid |  |  | FK -> users(id) |

### device_heartbeats
Device telemetry and status updates.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| device_type | text | NOT NULL |  |  |
| relay_device_type | text |  |  |  |
| relay_instance_id | text |  |  |  |
| firmware_version | text |  |  |  |
| battery_level | integer |  |  | CHECK battery_level IS NULL OR battery_level >= 0 AND battery_level <= 100 |
| battery_charging | boolean |  |  |  |
| wifi_rssi | integer |  |  |  |
| thread_rssi | integer |  |  |  |
| uptime_sec | integer |  |  |  |
| free_heap | integer |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| mac_address | character varying(17) |  |  |  |
| min_free_heap | integer |  |  |  |
| largest_free_block | integer |  |  |  |
| unit_id | text |  |  |  |
| type | text |  | status |  |
| command_id | uuid |  |  | FK -> device_commands(id) |
| telemetry | jsonb |  |  |  |

### now_playing_events
Real-time record placement/removal events from RFID readers.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| unit_id | text | NOT NULL |  |  |
| epc | text | NOT NULL |  |  |
| event_type | text | NOT NULL |  | CHECK event_type = ANY (ARRAY['placed'::text, 'removed'::text]) |
| rssi | integer |  |  |  |
| duration_ms | integer |  |  |  |
| timestamp | timestamp with time zone | NOT NULL | now() |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

---

## Orders & Customers

### orders
Shopify order records.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| shopify_order_id | character varying(255) | NOT NULL |  | UNIQUE |
| shopify_order_number | character varying(50) | NOT NULL |  |  |
| customer_id | uuid |  |  | FK -> customers(id) |
| order_date | timestamp with time zone | NOT NULL |  |  |
| status | character varying(50) | NOT NULL |  |  |
| fulfillment_status | character varying(50) |  |  |  |
| assigned_unit_id | uuid |  |  | FK -> units(id) |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### order_line_items
Individual items within orders.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| order_id | uuid | NOT NULL |  | FK -> orders(id) |
| product_id | uuid |  |  | FK -> products(id) |
| variant_id | uuid |  |  | FK -> product_variants(id) |
| shopify_product_id | character varying(255) | NOT NULL |  |  |
| shopify_variant_id | character varying(255) | NOT NULL |  |  |
| title | character varying(255) | NOT NULL |  |  |
| quantity | integer | NOT NULL | 1 |  |
| price | character varying(50) |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### customers
Shopify customer records.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| shopify_customer_id | character varying(255) | NOT NULL |  | UNIQUE |
| email | character varying(255) | NOT NULL |  |  |
| first_name | character varying(100) |  |  |  |
| last_name | character varying(100) |  |  |  |
| phone | character varying(50) |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

---

## RFID Tags

### rfid_tags
Individual RFID tags with lifecycle tracking.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| epc_identifier | character varying(24) | NOT NULL |  | UNIQUE |
| tid | character varying(48) |  |  |  |
| status | character varying(20) | NOT NULL | generated | CHECK status::text = ANY (ARRAY['generated'::character varying, 'written'::character varying, 'active'::character varying, 'retired'::character varying]::text[]) |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| written_at | timestamp with time zone |  |  |  |
| locked_at | timestamp with time zone |  |  |  |
| created_by | uuid |  |  | FK -> users(id) |
| library_album_id | uuid |  |  | FK -> library_albums(id) |
| associated_at | timestamp with time zone |  |  |  |
| associated_by | uuid |  |  | FK -> users(id) |
| last_seen_at | timestamp with time zone |  |  |  |
| roll_id | uuid |  |  | FK -> rfid_tag_rolls(id) |
| roll_position | integer |  |  | CHECK roll_position IS NULL OR roll_position > 0 |

### rfid_tag_rolls
Batches of RFID tags on physical rolls.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| label_width_mm | numeric(6,2) | NOT NULL |  |  |
| label_height_mm | numeric(6,2) | NOT NULL |  |  |
| label_count | integer | NOT NULL |  | CHECK label_count > 0 |
| status | character varying(20) | NOT NULL | writing | CHECK status::text = ANY (ARRAY['writing'::character varying, 'ready_to_print'::character varying, 'printing'::character varying, 'completed'::character varying]::text[]) |
| last_printed_position | integer | NOT NULL | 0 | CHECK last_printed_position >= 0 |
| manufacturer_url | text |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| created_by | uuid |  |  | FK -> users(id) |

---

## Albums & Libraries

### albums
Album metadata (from Discogs).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| discogs_id | integer |  |  | UNIQUE |
| title | text | NOT NULL |  |  |
| artist | text | NOT NULL |  |  |
| year | integer |  |  |  |
| genres | text[] |  | {} |  |
| styles | text[] |  | {} |  |
| label | text |  |  |  |
| cover_image_url | text |  |  |  |
| tracks | jsonb |  | [] |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| colors | jsonb |  |  |  |

### libraries
User-created album collections.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL |  |  |
| description | text |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| created_by | uuid | NOT NULL |  | FK -> users(id) |

### library_albums
Albums within a library.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| library_id | uuid | NOT NULL |  | UNIQUE, FK -> libraries(id) |
| album_id | uuid | NOT NULL |  | UNIQUE, FK -> albums(id) |
| added_at | timestamp with time zone | NOT NULL | now() |  |
| added_by | uuid | NOT NULL |  | FK -> users(id) |
| notes | text |  |  |  |
| is_favorite | boolean | NOT NULL | false |  |

### library_members
Users with access to a library.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| library_id | uuid | NOT NULL |  | UNIQUE, FK -> libraries(id) |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| role | library_role | NOT NULL | viewer | Enum |
| joined_at | timestamp with time zone | NOT NULL | now() |  |
| invited_by | uuid |  |  | FK -> users(id) |

### library_invitations
Pending invitations to join a library.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| library_id | uuid | NOT NULL |  | FK -> libraries(id) |
| invited_email | text | NOT NULL |  |  |
| invited_user_id | uuid |  |  | FK -> users(id) |
| role | library_role | NOT NULL | viewer | Enum |
| status | invitation_status | NOT NULL | pending | Enum |
| token | text | NOT NULL |  | UNIQUE |
| invited_by | uuid | NOT NULL |  | FK -> users(id) |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| expires_at | timestamp with time zone | NOT NULL | (now() + 7 days |  |
| accepted_at | timestamp with time zone |  |  |  |
| finalized_user_id | uuid |  |  | FK -> users(id) |

### album_locations
Tracks which device an album is currently on.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| library_album_id | uuid | NOT NULL |  | FK -> library_albums(id) |
| device_id | uuid | NOT NULL |  | FK -> units(id) |
| detected_at | timestamp with time zone | NOT NULL | now() |  |
| removed_at | timestamp with time zone |  |  |  |

### listening_history
User listening history (album plays).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | FK -> users(id) |
| library_album_id | uuid | NOT NULL |  | FK -> library_albums(id) |
| played_at | timestamp with time zone | NOT NULL | now() |  |
| play_duration_seconds | integer |  |  |  |
| completed_side | record_side |  |  | Enum |
| device_id | uuid |  |  | FK -> consumer_devices(id) |

---

## Notifications

### push_notification_tokens
Mobile device push notification tokens.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| token | text | NOT NULL |  |  |
| platform | text | NOT NULL |  | CHECK platform = ANY (ARRAY['ios'::text, 'android'::text]) |
| device_identifier | text | NOT NULL |  | UNIQUE |
| app_version | text |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| last_used_at | timestamp with time zone |  |  |  |
| is_active | boolean | NOT NULL | true |  |

### notification_preferences
Per-user notification settings.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| now_playing_enabled | boolean | NOT NULL | true |  |
| flip_reminders_enabled | boolean | NOT NULL | true |  |
| device_offline_enabled | boolean | NOT NULL | true |  |
| device_online_enabled | boolean | NOT NULL | true |  |
| battery_low_enabled | boolean | NOT NULL | true |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### notification_delivery_log
Notification send/delivery tracking.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | FK -> users(id) |
| notification_type | text | NOT NULL |  |  |
| source_id | uuid |  |  |  |
| token_id | uuid |  |  | FK -> push_notification_tokens(id) |
| status | text | NOT NULL |  | CHECK status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text, 'delivered'::text]) |
| error_message | text |  |  |  |
| sent_at | timestamp with time zone |  |  |  |
| delivered_at | timestamp with time zone |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### device_status_notifications
Tracks recent device status notifications to prevent duplicates.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| unit_id | uuid | NOT NULL |  | UNIQUE, FK -> units(id) |
| user_id | uuid | NOT NULL |  | FK -> users(id) |
| notification_type | text | NOT NULL |  | UNIQUE |
| last_sent_at | timestamp with time zone | NOT NULL | now() |  |
| context_data | jsonb |  |  |  |

### user_now_playing_notifications
Pre-enriched now-playing notifications for mobile push.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| source_event_id | uuid | NOT NULL |  | UNIQUE |
| unit_id | text | NOT NULL |  |  |
| epc | text | NOT NULL |  |  |
| event_type | text | NOT NULL |  | CHECK event_type = ANY (ARRAY['placed'::text, 'removed'::text]) |
| library_album_id | uuid |  |  | FK -> library_albums(id) |
| album_title | text |  |  |  |
| album_artist | text |  |  |  |
| cover_image_url | text |  |  |  |
| library_id | uuid |  |  | FK -> libraries(id) |
| library_name | text |  |  |  |
| device_id | uuid |  |  | FK -> units(id) |
| device_name | text |  |  |  |
| event_timestamp | timestamp with time zone | NOT NULL |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| album_colors | jsonb |  |  |  |

---

## Files & GCode

### files
Production file library (PDFs, images, videos for production steps).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| storage_path | text | NOT NULL |  | UNIQUE |
| file_name | text | NOT NULL |  | UNIQUE |
| description | text |  |  |  |
| mime_type | text | NOT NULL |  |  |
| file_size_bytes | integer | NOT NULL |  | CHECK file_size_bytes > 0 AND file_size_bytes <= 52428800 |
| uploaded_by_name | text | NOT NULL |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### step_files
Links production files to production steps.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| step_id | uuid | NOT NULL |  | UNIQUE, FK -> production_steps(id) |
| file_id | uuid | NOT NULL |  | UNIQUE, FK -> files(id) |
| execution_order | integer | NOT NULL |  | UNIQUE, CHECK execution_order > 0 |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### gcode_files
GCode files for CNC/laser operations (sourced from GitHub).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| github_path | text | NOT NULL |  | UNIQUE |
| file_name | text | NOT NULL |  |  |
| description | text |  |  |  |
| machine_type | text | NOT NULL |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### step_gcode_files
Links GCode files to production steps.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| step_id | uuid | NOT NULL |  | UNIQUE, FK -> production_steps(id) |
| gcode_file_id | uuid | NOT NULL |  | UNIQUE, FK -> gcode_files(id) |
| execution_order | integer | NOT NULL |  | UNIQUE, CHECK execution_order > 0 |
| created_at | timestamp with time zone | NOT NULL | now() |  |

---

## Networking

---

## Deprecated Tables

### production_units
**Deprecated** - replaced by `units` table. Kept for backward compatibility during transition.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | extensions.uuid_generate_v4() | PK |
| uuid | uuid | NOT NULL | extensions.uuid_generate_v4() | UNIQUE |
| unit_id | character varying(100) | NOT NULL |  | UNIQUE |
| product_id | uuid | NOT NULL |  | FK -> products(id) |
| variant_id | uuid | NOT NULL |  | FK -> product_variants(id) |
| shopify_order_id | character varying(255) |  |  |  |
| shopify_order_number | character varying(50) |  |  |  |
| customer_name | character varying(255) |  |  |  |
| current_owner_id | uuid |  |  | FK -> users(id) |
| qr_code_url | text | NOT NULL |  |  |
| production_started_at | timestamp with time zone |  |  |  |
| production_completed_at | timestamp with time zone |  |  |  |
| is_completed | boolean |  | false |  |
| created_at | timestamp with time zone |  | now() |  |
| created_by | uuid | NOT NULL |  | FK -> users(id) |
| mac_address | character varying(17) |  |  | CHECK mac_address IS NULL OR mac_address::text ~ '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'::text |

### legacy_qr_code_lookup
Maps old QR code UUIDs to new unit IDs during migration.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| old_uuid | uuid | NOT NULL |  | PK |
| unit_id | uuid | NOT NULL |  | FK -> units(id) |
| notes | text |  |  |  |
| created_at | timestamp with time zone |  | now() |  |

---

## Other Tables

### activity_push_tokens

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| session_id | uuid |  |  | FK -> playback_sessions(id) |
| push_token | text | NOT NULL |  | UNIQUE |
| is_active | boolean | NOT NULL | true |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### album_track_duration_contributions

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| album_id | uuid | NOT NULL |  | FK -> albums(id) |
| contributed_by | uuid | NOT NULL |  | FK -> users(id) |
| track_durations | jsonb | NOT NULL |  |  |
| side | text |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### bom_lines

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| product_id | uuid | NOT NULL |  | FK -> products(id) |
| part_id | uuid | NOT NULL |  | FK -> parts(id) |
| production_step_id | uuid |  |  | FK -> production_steps(id) |
| quantity | numeric | NOT NULL |  |  |
| notes | text |  |  |  |

### bom_variant_overrides

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| bom_line_id | uuid | NOT NULL |  | UNIQUE, FK -> bom_lines(id) |
| variant_id | uuid | NOT NULL |  | UNIQUE, FK -> product_variants(id) |
| part_id | uuid | NOT NULL |  | FK -> parts(id) |
| quantity | numeric |  |  |  |

### crate_inventory_events
RFID inventory snapshots from Thread-connected crates, relayed via the Hub

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| unit_id | text | NOT NULL |  |  |
| mac_address | character varying(17) | NOT NULL |  |  |
| epcs | text[] | NOT NULL |  |  |
| epc_count | integer | NOT NULL |  |  |
| timestamp | timestamp with time zone | NOT NULL |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### cratelist_items

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| cratelist_id | uuid | NOT NULL |  | UNIQUE, FK -> cratelists(id) |
| library_album_id | uuid | NOT NULL |  | UNIQUE, FK -> library_albums(id) |
| position | integer | NOT NULL |  | UNIQUE |
| added_at | timestamp with time zone | NOT NULL | now() |  |
| added_by | uuid |  |  | FK -> users(id) |

### cratelist_members

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| cratelist_id | uuid | NOT NULL |  | UNIQUE, FK -> cratelists(id) |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| role | library_role | NOT NULL | editor | Enum |
| added_at | timestamp with time zone | NOT NULL | now() |  |
| added_by | uuid |  |  | FK -> users(id) |

### cratelists

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL |  | CHECK length(TRIM(BOTH FROM name)) > 0 |
| description | text |  |  |  |
| created_by | uuid | NOT NULL |  | FK -> users(id) |
| source | text | NOT NULL | manual | CHECK source = ANY (ARRAY['manual'::text, 'smart'::text, 'saturday'::text]) |
| rules | jsonb |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### device_auth_codes

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| device_code | text | NOT NULL |  | UNIQUE |
| user_code | text | NOT NULL |  | UNIQUE |
| auth_user_id | uuid |  |  | FK -> users(id) |
| access_token | text |  |  |  |
| refresh_token | text |  |  |  |
| status | text | NOT NULL | pending | CHECK status = ANY (ARRAY['pending'::text, 'claimed'::text, 'expired'::text]) |
| expires_at | timestamp with time zone | NOT NULL |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### device_sessions
Per-device opaque session tokens issued by the adopt_device edge function. Hub firmware uses these for authenticated cloud calls in place of the shared anonymous key.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| device_id | uuid | NOT NULL |  | UNIQUE, FK -> devices(id) |
| auth_user_id | uuid | NOT NULL |  | FK -> users(id) |
| access_token | text | NOT NULL |  |  |
| refresh_token | text | NOT NULL |  |  |
| expires_at | timestamp with time zone | NOT NULL |  |  |
| status | text | NOT NULL | active | CHECK status = ANY (ARRAY['active'::text, 'revoked'::text]) |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### inventory_transactions

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| part_id | uuid | NOT NULL |  | FK -> parts(id) |
| transaction_type | inventory_transaction_type | NOT NULL |  | Enum |
| quantity | numeric | NOT NULL |  |  |
| unit_id | uuid |  |  | FK -> units(id) |
| step_completion_id | uuid |  |  | FK -> unit_step_completions(id) |
| supplier_id | uuid |  |  | FK -> suppliers(id) |
| build_batch_id | uuid |  |  |  |
| reference | text |  |  |  |
| performed_by | uuid | NOT NULL |  | FK -> users(id) |
| performed_at | timestamp with time zone | NOT NULL | now() |  |

### parts

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL |  |  |
| part_number | text | NOT NULL |  | UNIQUE |
| description | text |  |  |  |
| part_type | part_type | NOT NULL |  | Enum |
| category | part_category | NOT NULL |  | Enum |
| unit_of_measure | unit_of_measure | NOT NULL |  | Enum |
| reorder_threshold | numeric |  |  |  |
| is_active | boolean | NOT NULL | true |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### pending_tag_associations

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | FK -> users(id) |
| unit_id | text | NOT NULL |  |  |
| library_album_id | uuid | NOT NULL |  | FK -> library_albums(id) |
| status | text | NOT NULL | pending | CHECK status = ANY (ARRAY['pending'::text, 'fulfilled'::text, 'cancelled'::text]) |
| detected_epc | text |  |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| fulfilled_at | timestamp with time zone |  |  |  |
| cancelled_at | timestamp with time zone |  |  |  |

### playback_events

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| session_id | uuid | NOT NULL |  | FK -> playback_sessions(id) |
| user_id | uuid | NOT NULL |  | FK -> users(id) |
| event_type | text | NOT NULL |  | CHECK event_type = ANY (ARRAY['session_queued'::text, 'side_changed'::text, 'playback_started'::text, 'playback_stopped'::text, 'session_cancelled'::text]) |
| payload | jsonb |  | {} |  |
| source_type | text | NOT NULL | app | CHECK source_type = ANY (ARRAY['app'::text, 'hub'::text, 'web'::text, 'api'::text]) |
| source_device_id | uuid |  |  | FK -> units(id) |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### playback_queue

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| library_album_id | uuid | NOT NULL |  | FK -> library_albums(id) |
| position | integer | NOT NULL |  | UNIQUE |
| added_at | timestamp with time zone | NOT NULL | now() |  |
| added_by | uuid |  |  | FK -> users(id) |

### playback_sessions

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | FK -> users(id) |
| library_album_id | uuid |  |  | FK -> library_albums(id) |
| album_title | text |  |  |  |
| album_artist | text |  |  |  |
| cover_image_url | text |  |  |  |
| status | text | NOT NULL | queued | CHECK status = ANY (ARRAY['queued'::text, 'playing'::text, 'stopped'::text, 'cancelled'::text]) |
| current_side | text | NOT NULL | A | CHECK current_side = ANY (ARRAY['A'::text, 'B'::text, 'C'::text, 'D'::text]) |
| side_started_at | timestamp with time zone |  |  |  |
| current_track_index | integer |  |  |  |
| current_track_position | text |  |  |  |
| current_track_title | text |  |  |  |
| tracks | jsonb |  |  |  |
| side_a_duration_seconds | integer |  |  |  |
| side_b_duration_seconds | integer |  |  |  |
| queued_by_source | text | NOT NULL | app | CHECK queued_by_source = ANY (ARRAY['app'::text, 'hub'::text, 'web'::text, 'api'::text]) |
| queued_by_device_id | uuid |  |  | FK -> units(id) |
| started_by_source | text |  |  | CHECK started_by_source IS NULL OR (started_by_source = ANY (ARRAY['app'::text, 'hub'::text, 'web'::text, 'api'::text])) |
| started_by_device_id | uuid |  |  | FK -> units(id) |
| started_at | timestamp with time zone |  |  |  |
| ended_at | timestamp with time zone |  |  |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### product_image_assets
CAD-rendered product images with optional mask images for album cover compositing

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| variant_id | uuid | NOT NULL |  | UNIQUE, FK -> product_variants(id) |
| angle | text | NOT NULL |  | UNIQUE |
| frame_path | text | NOT NULL |  |  |
| image_width | integer | NOT NULL |  |  |
| image_height | integer | NOT NULL |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### product_image_slots
Defines album cover compositing slots per product/angle/capacity. Shared across all variants of a product.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| product_id | uuid | NOT NULL |  | UNIQUE, FK -> products(id) |
| angle | text | NOT NULL |  | UNIQUE |
| capacity | text | NOT NULL | full | UNIQUE |
| slot_data | jsonb | NOT NULL | {} |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### sub_assembly_lines

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| parent_part_id | uuid | NOT NULL |  | FK -> parts(id) |
| child_part_id | uuid | NOT NULL |  | FK -> parts(id) |
| quantity | numeric | NOT NULL |  |  |
| reference_designator | text |  |  |  |
| notes | text |  |  |  |
| is_board_assembled | boolean | NOT NULL | false |  |

### supplier_api_tokens

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| provider | text | NOT NULL |  | UNIQUE |
| access_token | text | NOT NULL |  |  |
| refresh_token | text |  |  |  |
| token_expires_at | timestamp with time zone |  |  |  |
| scopes | text |  |  |  |
| provider_metadata | jsonb |  | {} |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |

### supplier_parts

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| part_id | uuid | NOT NULL |  | UNIQUE, FK -> parts(id) |
| supplier_id | uuid | NOT NULL |  | UNIQUE, FK -> suppliers(id) |
| supplier_sku | text | NOT NULL |  | UNIQUE |
| barcode_value | text |  |  |  |
| barcode_format | text |  |  |  |
| unit_cost | numeric |  |  |  |
| cost_currency | text | NOT NULL | USD |  |
| is_preferred | boolean | NOT NULL | false |  |
| url | text |  |  |  |
| notes | text |  |  |  |

### suppliers

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL |  |  |
| website | text |  |  |  |
| notes | text |  |  |  |
| is_active | boolean | NOT NULL | true |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |

### thread_networks
Cloud-canonical Thread mesh credentials, one row per user account. Sensitive columns are AES-256-GCM ciphertext produced by edge functions; the DB never sees plaintext.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL |  | UNIQUE, FK -> users(id) |
| network_name | text | NOT NULL |  | CHECK char_length(network_name) >= 1 AND char_length(network_name) <= 16 |
| pan_id | integer | NOT NULL |  | CHECK pan_id >= 0 AND pan_id <= 65534 |
| channel | integer | NOT NULL |  | CHECK channel >= 11 AND channel <= 26 |
| network_key_encrypted | bytea | NOT NULL |  |  |
| extended_pan_id_encrypted | bytea | NOT NULL |  |  |
| mesh_local_prefix_encrypted | bytea | NOT NULL |  |  |
| pskc_encrypted | bytea | NOT NULL |  |  |
| created_at | timestamp with time zone | NOT NULL | now() |  |
| updated_at | timestamp with time zone | NOT NULL | now() |  |
| rotated_at | timestamp with time zone |  |  |  |

---

## Views

### current_now_playing

```sql
 SELECT DISTINCT ON (unit_id) unit_id,
    epc,
    event_type,
    rssi,
    "timestamp" AS last_event_time,
        CASE
            WHEN event_type = 'placed'::text THEN true
            ELSE false
        END AS is_playing
   FROM now_playing_events
  ORDER BY unit_id, "timestamp" DESC;
```

### inventory_levels

```sql
 SELECT part_id,
    sum(quantity) AS quantity_on_hand
   FROM inventory_transactions
  GROUP BY part_id;
```

### latest_crate_inventory

```sql
 SELECT DISTINCT ON (mac_address) mac_address,
    unit_id,
    epcs,
    epc_count,
    "timestamp" AS last_scan_time,
    created_at
   FROM crate_inventory_events
  ORDER BY mac_address, "timestamp" DESC;
```

### production_units_compat

```sql
 SELECT u.id,
    u.serial_number AS unit_id,
    u.product_id,
    u.variant_id,
    u.order_id,
    d.mac_address,
    u.qr_code_url,
    u.production_started_at,
    u.production_completed_at,
    u.is_completed,
    u.created_at,
    u.created_by
   FROM units u
     LEFT JOIN devices d ON d.unit_id = u.id;
```

---

## Functions

### accept_invitation_by_token

```sql
CREATE OR REPLACE FUNCTION public.accept_invitation_by_token(p_token text, p_accepting_user_id uuid)
 RETURNS library_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
```

### associate_rfid_tag

```sql
CREATE OR REPLACE FUNCTION public.associate_rfid_tag(p_epc text, p_library_album_id uuid, p_user_id uuid)
 RETURNS rfid_tags
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_tag rfid_tags;
BEGIN
    -- Update the existing tag with association info
    UPDATE rfid_tags
    SET
        library_album_id = p_library_album_id,
        associated_at = NOW(),
        associated_by = p_user_id,
        updated_at = NOW()
    WHERE epc_identifier = p_epc
    RETURNING * INTO v_tag;

    -- If tag doesn't exist, this is an error (tags must be created by admin app)
    IF v_tag IS NULL THEN
        RAISE EXCEPTION 'Tag with EPC % not found. Tags must be provisioned via admin app.', p_epc;
    END IF;

    RETURN v_tag;
END;
$function$
```

### broadcast_device_command

```sql
CREATE OR REPLACE FUNCTION public.broadcast_device_command()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hub_mac VARCHAR(17);
  channel_name TEXT;
  payload JSONB;
BEGIN
  -- Check if target device connects through a hub
  SELECT hub_mac_address INTO v_hub_mac
  FROM devices
  WHERE mac_address = NEW.mac_address;

  -- Build base command payload
  payload := jsonb_build_object(
    'id', NEW.id,
    'command', NEW.command,
    'capability', NEW.capability,
    'test_name', NEW.test_name,
    'parameters', NEW.parameters
  );

  IF v_hub_mac IS NOT NULL THEN
    -- Route through hub: broadcast to hub's channel with target_mac
    channel_name := 'device:' || REPLACE(v_hub_mac, ':', '-');
    payload := payload || jsonb_build_object('target_mac', NEW.mac_address);
  ELSE
    -- Direct route: broadcast to device's own channel
    channel_name := 'device:' || REPLACE(NEW.mac_address, ':', '-');
  END IF;

  PERFORM realtime.send(payload, 'command', channel_name, false);

  RETURN NEW;
END;
$function$
```

### broadcast_playback_event_to_hubs

```sql
CREATE OR REPLACE FUNCTION public.broadcast_playback_event_to_hubs()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  device_record RECORD;
  channel_name TEXT;
BEGIN
  -- Find all devices belonging to units owned by this user
  FOR device_record IN
    SELECT d.mac_address
    FROM devices d
    JOIN units u ON d.unit_id = u.id
    WHERE u.consumer_user_id = NEW.user_id
      AND u.is_online = true
  LOOP
    channel_name := 'device:' || REPLACE(device_record.mac_address, ':', '-');

    PERFORM pg_notify(
      'realtime:broadcast',
      json_build_object(
        'topic', channel_name,
        'event', 'broadcast',
        'payload', json_build_object(
          'event', 'playback_event',
          'payload', json_build_object(
            'event_type', NEW.event_type,
            'session_id', NEW.session_id,
            'payload', NEW.payload,
            'source_type', NEW.source_type,
            'created_at', NEW.created_at
          )
        )
      )::text
    );
  END LOOP;

  RETURN NEW;
END;
$function$
```

### can_edit_cratelist

```sql
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
$function$
```

### can_edit_library

```sql
CREATE OR REPLACE FUNCTION public.can_edit_library(lib_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM library_members
        WHERE library_id = lib_id
        AND user_id = get_user_id_from_auth()
        AND role IN ('owner', 'editor')
    );
END;
$function$
```

### cleanup_old_heartbeats

```sql
CREATE OR REPLACE FUNCTION public.cleanup_old_heartbeats(retention_hours integer DEFAULT 24)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM device_heartbeats
  WHERE received_at < NOW() - (retention_hours || ' hours')::INTERVAL;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$function$
```

### cleanup_old_notifications

```sql
CREATE OR REPLACE FUNCTION public.cleanup_old_notifications()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM user_now_playing_notifications
    WHERE created_at < NOW() - INTERVAL '24 hours';

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$function$
```

### contribute_track_durations

```sql
CREATE OR REPLACE FUNCTION public.contribute_track_durations(p_album_id uuid, p_contributed_by uuid, p_track_durations jsonb, p_side text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_album_tracks jsonb;
  v_contribution jsonb;
  v_updated_tracks jsonb;
  v_i int;
  v_track jsonb;
  v_pos text;
  v_dur int;
BEGIN
  -- 1. Insert the contribution record
  INSERT INTO album_track_duration_contributions (album_id, contributed_by, track_durations, side)
  VALUES (p_album_id, p_contributed_by, p_track_durations, p_side);

  -- 2. Get the current tracks JSONB from the canonical album
  SELECT tracks INTO v_album_tracks
  FROM albums
  WHERE id = p_album_id;

  IF v_album_tracks IS NULL THEN
    RETURN '{"error": "album not found or has no tracks"}'::jsonb;
  END IF;

  -- 3. Build a lookup from the contributed durations
  --    and update tracks where duration_seconds is null
  v_updated_tracks := '[]'::jsonb;

  FOR v_i IN 0..jsonb_array_length(v_album_tracks) - 1 LOOP
    v_track := v_album_tracks->v_i;
    v_pos := v_track->>'position';

    -- Check if this track has no duration and we have a contribution for it
    IF (v_track->>'duration_seconds') IS NULL THEN
      -- Search the contributed durations for a matching position
      SELECT (elem->>'duration_seconds')::int INTO v_dur
      FROM jsonb_array_elements(p_track_durations) AS elem
      WHERE elem->>'position' = v_pos
      LIMIT 1;

      IF v_dur IS NOT NULL THEN
        v_track := jsonb_set(v_track, '{duration_seconds}', to_jsonb(v_dur));
      END IF;
    END IF;

    v_updated_tracks := v_updated_tracks || jsonb_build_array(v_track);
  END LOOP;

  -- 4. Update the canonical album with merged durations
  UPDATE albums
  SET tracks = v_updated_tracks,
      updated_at = now()
  WHERE id = p_album_id;

  RETURN v_updated_tracks;
END;
$function$
```

### create_library_invitation

```sql
CREATE OR REPLACE FUNCTION public.create_library_invitation(p_library_id uuid, p_email text, p_role library_role, p_invited_by uuid)
 RETURNS library_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
```

### generate_invitation_token

```sql
CREATE OR REPLACE FUNCTION public.generate_invitation_token()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN encode(gen_random_bytes(32), 'hex');
END;
$function$
```

### get_album_play_count

```sql
CREATE OR REPLACE FUNCTION public.get_album_play_count(p_library_album_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*)::INTEGER INTO v_count
    FROM listening_history
    WHERE library_album_id = p_library_album_id;

    RETURN v_count;
END;
$function$
```

### get_device_status_summary

```sql
CREATE OR REPLACE FUNCTION public.get_device_status_summary()
 RETURNS TABLE(status text, count bigint)
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    CASE
      WHEN d.last_seen_at > NOW() - INTERVAL '60 seconds' THEN 'online'
      WHEN d.last_seen_at IS NOT NULL THEN 'offline'
      ELSE 'never_connected'
    END as status,
    COUNT(*) as count
  FROM devices d
  GROUP BY 1
  ORDER BY 1;
END;
$function$
```

### get_invitation_by_token

```sql
CREATE OR REPLACE FUNCTION public.get_invitation_by_token(p_token text)
 RETURNS TABLE(invitation_id uuid, library_id uuid, library_name text, library_description text, invited_email text, role library_role, status invitation_status, inviter_name text, inviter_email text, expires_at timestamp with time zone, created_at timestamp with time zone, is_expired boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
```

### get_library_albums_with_details

```sql
CREATE OR REPLACE FUNCTION public.get_library_albums_with_details(p_library_id uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(library_album_id uuid, library_id uuid, album_id uuid, added_at timestamp with time zone, added_by uuid, notes text, is_favorite boolean, title text, artist text, year integer, genres text[], styles text[], label text, cover_image_url text, tracks jsonb, current_device_id uuid, current_device_name text)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        la.id AS library_album_id,
        la.library_id,
        la.album_id,
        la.added_at,
        la.added_by,
        la.notes,
        la.is_favorite,
        a.title,
        a.artist,
        a.year,
        a.genres,
        a.styles,
        a.label,
        a.cover_image_url,
        a.tracks,
        al.device_id AS current_device_id,
        u.consumer_name AS current_device_name
    FROM library_albums la
    JOIN albums a ON a.id = la.album_id
    LEFT JOIN LATERAL (
        SELECT alock.device_id
        FROM album_locations alock
        WHERE alock.library_album_id = la.id
        AND alock.removed_at IS NULL
        ORDER BY alock.detected_at DESC
        LIMIT 1
    ) al ON true
    LEFT JOIN units u ON u.id = al.device_id
    WHERE la.library_id = p_library_id
    ORDER BY la.added_at DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$function$
```

### get_online_device_count

```sql
CREATE OR REPLACE FUNCTION public.get_online_device_count()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
  RETURN (
    SELECT COUNT(*)
    FROM devices
    WHERE last_seen_at > NOW() - INTERVAL '60 seconds'
  );
END;
$function$
```

### get_or_create_consumer_user

```sql
CREATE OR REPLACE FUNCTION public.get_or_create_consumer_user()
 RETURNS users
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_user users;
    v_auth_user_id UUID;
    v_email TEXT;
BEGIN
    v_auth_user_id := auth.uid();

    IF v_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Try to find existing user by auth_user_id
    SELECT * INTO v_user
    FROM users
    WHERE auth_user_id = v_auth_user_id;

    IF v_user IS NOT NULL THEN
        RETURN v_user;
    END IF;

    -- Get email from auth.users
    SELECT email INTO v_email
    FROM auth.users
    WHERE id = v_auth_user_id;

    -- Try to find by email (existing admin user)
    SELECT * INTO v_user
    FROM users
    WHERE email = v_email;

    IF v_user IS NOT NULL THEN
        -- Link to auth_user_id
        UPDATE users
        SET auth_user_id = v_auth_user_id, last_login = NOW()
        WHERE id = v_user.id
        RETURNING * INTO v_user;
        RETURN v_user;
    END IF;

    -- Create new user
    INSERT INTO users (id, email, auth_user_id, created_at, last_login)
    VALUES (gen_random_uuid(), v_email, v_auth_user_id, NOW(), NOW())
    RETURNING * INTO v_user;

    RETURN v_user;
END;
$function$
```

### get_popular_library_albums

```sql
CREATE OR REPLACE FUNCTION public.get_popular_library_albums(p_library_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(id uuid, library_id uuid, album_id uuid, added_at timestamp with time zone, added_by uuid, notes text, is_favorite boolean, play_count bigint, title text, artist text, year integer, cover_image_url text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
```

### get_recently_played

```sql
CREATE OR REPLACE FUNCTION public.get_recently_played(p_user_id uuid, p_limit integer DEFAULT 10)
 RETURNS TABLE(library_album_id uuid, title text, artist text, cover_image_url text, last_played_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (la.id)
        la.id AS library_album_id,
        a.title,
        a.artist,
        a.cover_image_url,
        lh.played_at AS last_played_at
    FROM listening_history lh
    JOIN library_albums la ON la.id = lh.library_album_id
    JOIN albums a ON a.id = la.album_id
    WHERE lh.user_id = p_user_id
    ORDER BY la.id, lh.played_at DESC
    LIMIT p_limit;
END;
$function$
```

### get_user_album_analytics

```sql
CREATE OR REPLACE FUNCTION public.get_user_album_analytics(p_top_limit integer DEFAULT 5, p_activity_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID := get_user_id_from_auth();
    v_result  JSONB;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated' USING ERRCODE = '42501';
    END IF;

    -- Clamp inputs to defensive ranges.
    p_top_limit     := GREATEST(1, LEAST(p_top_limit, 50));
    p_activity_days := GREATEST(1, LEAST(p_activity_days, 365));

    WITH user_libraries AS (
        SELECT library_id
          FROM library_members
         WHERE user_id = v_user_id
    ),
    user_library_albums AS (
        SELECT la.id          AS library_album_id,
               la.is_favorite,
               a.id            AS album_id,
               a.title,
               a.artist,
               a.year,
               a.genres,
               a.styles,
               a.cover_image_url
          FROM library_albums la
          JOIN albums a ON a.id = la.album_id
         WHERE la.library_id IN (SELECT library_id FROM user_libraries)
    ),
    plays AS (
        SELECT lh.id,
               lh.library_album_id,
               lh.played_at,
               lh.play_duration_seconds
          FROM listening_history lh
         WHERE lh.user_id = v_user_id
    ),
    play_album AS (
        SELECT p.id,
               p.played_at,
               p.play_duration_seconds,
               la.id    AS library_album_id,
               a.id     AS album_id,
               a.title,
               a.artist,
               a.year,
               a.genres,
               a.cover_image_url
          FROM plays p
          JOIN library_albums la ON la.id = p.library_album_id
          JOIN albums a          ON a.id = la.album_id
    ),
    top_albums AS (
        SELECT library_album_id,
               album_id,
               title,
               artist,
               year,
               cover_image_url,
               COUNT(*)::INTEGER AS play_count
          FROM play_album
         GROUP BY library_album_id, album_id, title, artist, year, cover_image_url
         ORDER BY play_count DESC, title ASC
         LIMIT p_top_limit
    ),
    top_artists AS (
        SELECT artist,
               COUNT(*)::INTEGER AS play_count
          FROM play_album
         WHERE artist IS NOT NULL AND length(trim(artist)) > 0
         GROUP BY artist
         ORDER BY play_count DESC, artist ASC
         LIMIT p_top_limit
    ),
    top_genres AS (
        SELECT genre,
               COUNT(*)::INTEGER AS play_count
          FROM play_album,
               LATERAL UNNEST(COALESCE(genres, ARRAY[]::TEXT[])) AS genre
         WHERE genre IS NOT NULL AND length(trim(genre)) > 0
         GROUP BY genre
         ORDER BY play_count DESC, genre ASC
         LIMIT p_top_limit
    ),
    decade_counts AS (
        SELECT ((year / 10) * 10)::INTEGER AS decade,
               COUNT(DISTINCT album_id)::INTEGER AS album_count
          FROM user_library_albums
         WHERE year IS NOT NULL AND year > 0
         GROUP BY ((year / 10) * 10)
         ORDER BY decade
    ),
    activity_range AS (
        SELECT generate_series(
                   (NOW() AT TIME ZONE 'UTC')::date - (p_activity_days - 1),
                   (NOW() AT TIME ZONE 'UTC')::date,
                   INTERVAL '1 day'
               )::date AS day
    ),
    daily_play_counts AS (
        SELECT (played_at AT TIME ZONE 'UTC')::date AS day,
               COUNT(*)::INTEGER                    AS play_count
          FROM plays
         WHERE played_at >= NOW() - make_interval(days => p_activity_days)
         GROUP BY 1
    ),
    daily_activity AS (
        SELECT ar.day,
               COALESCE(dpc.play_count, 0) AS play_count
          FROM activity_range ar
          LEFT JOIN daily_play_counts dpc ON dpc.day = ar.day
         ORDER BY ar.day
    ),
    totals AS (
        SELECT (SELECT COUNT(*)::INTEGER FROM plays)                                  AS total_plays,
               (SELECT COALESCE(SUM(play_duration_seconds), 0)::BIGINT FROM plays)    AS total_seconds,
               (SELECT COUNT(*)::INTEGER FROM user_library_albums)                    AS total_albums,
               (SELECT COUNT(*)::INTEGER FROM user_library_albums WHERE is_favorite)  AS total_favorites,
               (SELECT COUNT(DISTINCT artist)::INTEGER
                  FROM user_library_albums
                 WHERE artist IS NOT NULL AND length(trim(artist)) > 0)               AS total_artists
    )
    SELECT jsonb_build_object(
        'generated_at', to_jsonb(NOW()),
        'totals',       (SELECT to_jsonb(t.*) FROM totals t),
        'top_albums',   (SELECT COALESCE(jsonb_agg(to_jsonb(ta.*)), '[]'::jsonb) FROM top_albums ta),
        'top_artists',  (SELECT COALESCE(jsonb_agg(to_jsonb(ar.*)), '[]'::jsonb) FROM top_artists ar),
        'top_genres',   (SELECT COALESCE(jsonb_agg(to_jsonb(g.*)),  '[]'::jsonb) FROM top_genres g),
        'decades',      (SELECT COALESCE(jsonb_agg(to_jsonb(d.*)),  '[]'::jsonb) FROM decade_counts d),
        'daily_plays',  (SELECT COALESCE(jsonb_agg(to_jsonb(da.*)), '[]'::jsonb) FROM daily_activity da)
    )
      INTO v_result;

    RETURN v_result;
END;
$function$
```

### get_user_id_from_auth

```sql
CREATE OR REPLACE FUNCTION public.get_user_id_from_auth()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
DECLARE
    v_user_id UUID;
BEGIN
    -- First try to find user by auth_user_id (consumer auth flow)
    SELECT id INTO v_user_id
    FROM users
    WHERE auth_user_id = auth.uid();

    -- If not found, try direct id match (for compatibility)
    IF v_user_id IS NULL THEN
        SELECT id INTO v_user_id
        FROM users
        WHERE id = auth.uid();
    END IF;

    RETURN v_user_id;
END;
$function$
```

### get_user_permissions

```sql
CREATE OR REPLACE FUNCTION public.get_user_permissions(user_email text)
 RETURNS TABLE(permission_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    RETURN QUERY
    SELECT p.name
    FROM public.permissions p
    INNER JOIN public.user_permissions up ON p.id = up.permission_id
    INNER JOIN public.users u ON u.id = up.user_id
    WHERE u.email = user_email;
END;
$function$
```

### handle_consumer_auth_signup

```sql
CREATE OR REPLACE FUNCTION public.handle_consumer_auth_signup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_existing_user_id UUID;
BEGIN
    -- Check if a user with this email already exists (e.g., admin user)
    SELECT id INTO v_existing_user_id
    FROM public.users
    WHERE email = NEW.email;

    IF v_existing_user_id IS NOT NULL THEN
        -- Link existing user to auth.users via auth_user_id
        UPDATE public.users
        SET
            auth_user_id = NEW.id,
            avatar_url = COALESCE(users.avatar_url, NEW.raw_user_meta_data->>'avatar_url'),
            full_name = COALESCE(users.full_name, NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'),
            last_login = NOW()
        WHERE id = v_existing_user_id;
    ELSE
        -- Create new user for consumer
        INSERT INTO public.users (
            id,
            email,
            full_name,
            avatar_url,
            auth_user_id,
            created_at,
            last_login
        )
        VALUES (
            gen_random_uuid(),
            NEW.email,
            COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name'),
            NEW.raw_user_meta_data->>'avatar_url',
            NEW.id,
            NOW(),
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$function$
```

### handle_new_cratelist

```sql
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
$function$
```

### handle_new_library

```sql
CREATE OR REPLACE FUNCTION public.handle_new_library()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    INSERT INTO library_members (library_id, user_id, role, joined_at)
    VALUES (NEW.id, NEW.created_by, 'owner', NOW())
    ON CONFLICT (library_id, user_id) DO NOTHING;
    RETURN NEW;
END;
$function$
```

### is_cratelist_member

```sql
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
$function$
```

### is_cratelist_owner

```sql
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
$function$
```

### is_library_member

```sql
CREATE OR REPLACE FUNCTION public.is_library_member(lib_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM library_members
        WHERE library_id = lib_id
        AND user_id = get_user_id_from_auth()
    );
END;
$function$
```

### is_library_owner

```sql
CREATE OR REPLACE FUNCTION public.is_library_owner(lib_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM library_members
        WHERE library_id = lib_id
        AND user_id = get_user_id_from_auth()
        AND role = 'owner'
    );
END;
$function$
```

### populate_heartbeat_telemetry

```sql
CREATE OR REPLACE FUNCTION public.populate_heartbeat_telemetry()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.telemetry IS NOT NULL THEN
    -- Case A: telemetry JSONB provided — extract known fields into typed columns
    -- COALESCE preserves any column value already set by the POST (column wins)
    NEW.firmware_version := COALESCE(NEW.firmware_version, NEW.telemetry->>'firmware_version');
    NEW.battery_level := COALESCE(NEW.battery_level, (NEW.telemetry->>'battery_level')::INTEGER);
    NEW.battery_charging := COALESCE(NEW.battery_charging, (NEW.telemetry->>'battery_charging')::BOOLEAN);
    NEW.wifi_rssi := COALESCE(NEW.wifi_rssi, (NEW.telemetry->>'wifi_rssi')::INTEGER);
    NEW.thread_rssi := COALESCE(NEW.thread_rssi, (NEW.telemetry->>'thread_rssi')::INTEGER);
    NEW.uptime_sec := COALESCE(NEW.uptime_sec, (NEW.telemetry->>'uptime_sec')::INTEGER);
    NEW.free_heap := COALESCE(NEW.free_heap, (NEW.telemetry->>'free_heap')::INTEGER);
    NEW.min_free_heap := COALESCE(NEW.min_free_heap, (NEW.telemetry->>'min_free_heap')::INTEGER);
    NEW.largest_free_block := COALESCE(NEW.largest_free_block, (NEW.telemetry->>'largest_free_block')::INTEGER);

    -- Enrich telemetry with routing fields so it's a complete record.
    -- Use routing_fields || telemetry so telemetry keys take priority on collision.
    NEW.telemetry := jsonb_strip_nulls(jsonb_build_object(
      'mac_address', NEW.mac_address,
      'unit_id', NEW.unit_id,
      'device_type', NEW.device_type,
      'type', NEW.type,
      'relay_device_type', NEW.relay_device_type,
      'relay_instance_id', NEW.relay_instance_id,
      'firmware_version', NEW.firmware_version
    )) || NEW.telemetry;
  ELSE
    -- Case B: No telemetry JSONB — build from individual columns (flat POST)
    NEW.telemetry := jsonb_strip_nulls(jsonb_build_object(
      'mac_address', NEW.mac_address,
      'unit_id', NEW.unit_id,
      'device_type', NEW.device_type,
      'type', NEW.type,
      'relay_device_type', NEW.relay_device_type,
      'relay_instance_id', NEW.relay_instance_id,
      'firmware_version', NEW.firmware_version,
      'battery_level', NEW.battery_level,
      'battery_charging', NEW.battery_charging,
      'wifi_rssi', NEW.wifi_rssi,
      'thread_rssi', NEW.thread_rssi,
      'uptime_sec', NEW.uptime_sec,
      'free_heap', NEW.free_heap,
      'min_free_heap', NEW.min_free_heap,
      'largest_free_block', NEW.largest_free_block,
      'command_id', NEW.command_id
    ));
  END IF;

  RETURN NEW;
END;
$function$
```

### record_play

```sql
CREATE OR REPLACE FUNCTION public.record_play(p_user_id uuid, p_library_album_id uuid, p_device_id uuid DEFAULT NULL::uuid)
 RETURNS listening_history
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_history listening_history;
BEGIN
    INSERT INTO listening_history (user_id, library_album_id, played_at, device_id)
    VALUES (p_user_id, p_library_album_id, NOW(), p_device_id)
    RETURNING * INTO v_history;

    RETURN v_history;
END;
$function$
```

### reject_invitation_by_token

```sql
CREATE OR REPLACE FUNCTION public.reject_invitation_by_token(p_token text)
 RETURNS library_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
```

### reorder_cratelist_items

```sql
CREATE OR REPLACE FUNCTION public.reorder_cratelist_items(p_cratelist_id uuid, p_item_ids uuid[])
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
$function$
```

### reorder_playback_queue

```sql
CREATE OR REPLACE FUNCTION public.reorder_playback_queue(p_item_ids uuid[])
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
$function$
```

### resolve_tag_to_album

```sql
CREATE OR REPLACE FUNCTION public.resolve_tag_to_album(p_epc text)
 RETURNS TABLE(tag_id uuid, epc_identifier character varying, library_album_id uuid, album_id uuid, title text, artist text, cover_image_url text, library_id uuid, library_name text)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        t.id AS tag_id,
        t.epc_identifier,
        t.library_album_id,
        a.id AS album_id,
        a.title,
        a.artist,
        a.cover_image_url,
        l.id AS library_id,
        l.name AS library_name
    FROM rfid_tags t
    LEFT JOIN library_albums la ON la.id = t.library_album_id
    LEFT JOIN albums a ON a.id = la.album_id
    LEFT JOIN libraries l ON l.id = la.library_id
    WHERE t.epc_identifier = p_epc;
END;
$function$
```

### revoke_invitation

```sql
CREATE OR REPLACE FUNCTION public.revoke_invitation(p_invitation_id uuid, p_user_id uuid)
 RETURNS library_invitations
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
$function$
```

### search_albums

```sql
CREATE OR REPLACE FUNCTION public.search_albums(p_query text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS SETOF albums
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN QUERY
    SELECT *
    FROM albums
    WHERE to_tsvector('english', title || ' ' || artist || ' ' || COALESCE(label, ''))
          @@ plainto_tsquery('english', p_query)
    ORDER BY ts_rank(
        to_tsvector('english', title || ' ' || artist || ' ' || COALESCE(label, '')),
        plainto_tsquery('english', p_query)
    ) DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$function$
```

### sync_heartbeat_to_device_and_unit

```sql
CREATE OR REPLACE FUNCTION public.sync_heartbeat_to_device_and_unit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_unit_id UUID;
  v_telemetry JSONB;
  v_battery_level INTEGER;
  v_is_charging BOOLEAN;
  v_wifi_rssi INTEGER;
  v_temperature_c NUMERIC;
  v_humidity_pct NUMERIC;
  v_firmware_version TEXT;
  v_heartbeat_ts TIMESTAMPTZ;
  v_hub_mac VARCHAR(17);
BEGIN
  v_heartbeat_ts := COALESCE(NEW.created_at, NOW());
  v_firmware_version := NEW.firmware_version;

  -- Build telemetry JSONB: prefer new telemetry column, fall back to individual columns
  IF NEW.telemetry IS NOT NULL THEN
    v_telemetry := NEW.telemetry;
  ELSE
    -- Build from individual columns (backward compatibility with current firmware)
    v_telemetry := jsonb_strip_nulls(jsonb_build_object(
      'unit_id', NEW.unit_id,
      'device_type', NEW.device_type,
      'uptime_sec', NEW.uptime_sec,
      'free_heap', NEW.free_heap,
      'min_free_heap', NEW.min_free_heap,
      'largest_free_block', NEW.largest_free_block,
      'wifi_rssi', NEW.wifi_rssi,
      'thread_rssi', NEW.thread_rssi,
      'battery_level', NEW.battery_level,
      'battery_charging', NEW.battery_charging
    ));
  END IF;

  -- Extract consumer-facing telemetry values
  -- COALESCE prefers telemetry JSONB, falls back to individual columns
  v_battery_level := COALESCE(
    (v_telemetry->>'battery_level')::INTEGER,
    NEW.battery_level
  );
  v_is_charging := COALESCE(
    (v_telemetry->>'battery_charging')::BOOLEAN,
    NEW.battery_charging
  );
  v_wifi_rssi := COALESCE(
    (v_telemetry->>'wifi_rssi')::INTEGER,
    NEW.wifi_rssi
  );
  v_temperature_c := (v_telemetry->>'temperature_c')::NUMERIC;
  v_humidity_pct := (v_telemetry->>'humidity_pct')::NUMERIC;

  -- Also extract firmware_version from telemetry if not set as column
  IF v_firmware_version IS NULL THEN
    v_firmware_version := v_telemetry->>'firmware_version';
  END IF;

  -- =========================================================================
  -- Resolve hub_mac_address from relay info
  -- =========================================================================
  IF NEW.relay_device_type = 'hub' AND NEW.relay_instance_id IS NOT NULL THEN
    -- Relayed heartbeat: look up the hub's MAC via its serial number
    -- relay_instance_id contains the hub's unit_id (serial number)
    SELECT d2.mac_address INTO v_hub_mac
    FROM devices d2
    JOIN units u ON d2.unit_id = u.id
    WHERE u.serial_number = NEW.relay_instance_id
    LIMIT 1;
  ELSIF NEW.relay_device_type IS NULL THEN
    -- Direct heartbeat (no relay): clear hub association
    v_hub_mac := NULL;
  END IF;
  -- If relay_device_type is something other than 'hub' (e.g. phone relay),
  -- v_hub_mac stays NULL and hub_mac_address is preserved unchanged below.

  -- =========================================================================
  -- Update devices table (by mac_address)
  -- =========================================================================
  UPDATE devices
  SET
    last_seen_at = v_heartbeat_ts,
    firmware_version = COALESCE(v_firmware_version, firmware_version),
    latest_telemetry = v_telemetry,
    status = CASE WHEN status = 'offline' THEN 'online' ELSE status END,
    hub_mac_address = CASE
      WHEN NEW.relay_device_type = 'hub' AND NEW.relay_instance_id IS NOT NULL THEN v_hub_mac
      WHEN NEW.relay_device_type IS NULL THEN NULL
      ELSE hub_mac_address  -- preserve existing for non-hub relays
    END
  WHERE mac_address = NEW.mac_address;

  -- =========================================================================
  -- Update units table (by serial number stored in heartbeats.unit_id)
  -- Only update fields that are present in this heartbeat's telemetry.
  -- This supports multi-device units where different devices report
  -- different capability data (e.g., main controller has wifi, RFID reader
  -- does not). COALESCE preserves existing values when this heartbeat
  -- doesn't include a particular field.
  -- =========================================================================
  IF NEW.unit_id IS NOT NULL THEN
    UPDATE units
    SET
      last_seen_at = GREATEST(last_seen_at, v_heartbeat_ts),
      is_online = true,
      firmware_version = COALESCE(v_firmware_version, firmware_version),
      battery_level = COALESCE(v_battery_level, battery_level),
      is_charging = COALESCE(v_is_charging, is_charging),
      wifi_rssi = COALESCE(v_wifi_rssi, wifi_rssi),
      temperature_c = COALESCE(v_temperature_c, temperature_c),
      humidity_pct = COALESCE(v_humidity_pct, humidity_pct)
    WHERE serial_number = NEW.unit_id
    RETURNING id INTO v_unit_id;

    IF v_unit_id IS NULL THEN
      RAISE LOG 'Heartbeat: no unit found for serial_number=%, mac=%',
        NEW.unit_id, NEW.mac_address;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$
```

### touch_cratelist_from_item

```sql
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
$function$
```

### touch_cratelist_updated_at

```sql
CREATE OR REPLACE FUNCTION public.touch_cratelist_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$
```

### update_capabilities_updated_at

```sql
CREATE OR REPLACE FUNCTION public.update_capabilities_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
```

### update_command_on_ack

```sql
CREATE OR REPLACE FUNCTION public.update_command_on_ack()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
  v_result JSONB;
  v_error_message TEXT;
BEGIN
  -- Handle command acknowledgement
  IF NEW.type = 'command_ack' AND NEW.command_id IS NOT NULL THEN
    UPDATE device_commands
    SET
      status = 'acknowledged',
      updated_at = NOW()
    WHERE id = NEW.command_id
      AND status IN ('pending', 'sent');

  -- Handle command result (completed or failed)
  ELSIF NEW.type = 'command_result' AND NEW.command_id IS NOT NULL THEN
    IF NEW.telemetry IS NOT NULL THEN
      v_status := COALESCE(NEW.telemetry->>'status', 'completed');
      v_result := NEW.telemetry->'result';
      v_error_message := NEW.telemetry->>'error_message';
    ELSE
      v_status := 'completed';
    END IF;

    UPDATE device_commands
    SET
      status = v_status,
      result = v_result,
      error_message = v_error_message,
      updated_at = NOW()
    WHERE id = NEW.command_id;
  END IF;

  RETURN NEW;
END;
$function$
```

### update_device_commands_updated_at

```sql
CREATE OR REPLACE FUNCTION public.update_device_commands_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
```

### update_devices_updated_at

```sql
CREATE OR REPLACE FUNCTION public.update_devices_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
```

### update_machine_macros_updated_at

```sql
CREATE OR REPLACE FUNCTION public.update_machine_macros_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$function$
```

### update_notification_preferences_updated_at

```sql
CREATE OR REPLACE FUNCTION public.update_notification_preferences_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$
```

### update_parts_updated_at

```sql
CREATE OR REPLACE FUNCTION public.update_parts_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$
```

### update_playback_session_timestamp

```sql
CREATE OR REPLACE FUNCTION public.update_playback_session_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$
```

### update_units_updated_at

```sql
CREATE OR REPLACE FUNCTION public.update_units_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
```

### update_updated_at_column

```sql
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$function$
```

### user_has_permission

```sql
CREATE OR REPLACE FUNCTION public.user_has_permission(user_email text, permission_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    user_is_admin BOOLEAN;
    has_perm BOOLEAN;
BEGIN
    -- Check if user is admin (admins have all permissions)
    SELECT is_admin INTO user_is_admin
    FROM public.users
    WHERE email = user_email;

    IF user_is_admin THEN
        RETURN TRUE;
    END IF;

    -- Check if user has the specific permission
    SELECT EXISTS (
        SELECT 1
        FROM public.user_permissions up
        INNER JOIN public.users u ON u.id = up.user_id
        INNER JOIN public.permissions p ON p.id = up.permission_id
        WHERE u.email = user_email
        AND p.name = permission_name
    ) INTO has_perm;

    RETURN has_perm;
END;
$function$
```

---

## Triggers

```sql
CREATE TRIGGER update_albums_updated_at BEFORE UPDATE ON albums FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_capabilities_updated_at BEFORE UPDATE ON capabilities FOR EACH ROW EXECUTE FUNCTION update_capabilities_updated_at();
CREATE TRIGGER crate_inventory_events_webhook AFTER INSERT ON crate_inventory_events FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request('https://ddhcmhbwppiqrqmefynv.supabase.co/functions/v1/process-crate-inventory', 'POST', '{"Content-type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRkaGNtaGJ3cHBpcXJxbWVmeW52Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1OTk1MDA5MSwiZXhwIjoyMDc1NTI2MDkxfQ.KV7Ro37KMRr6D1zQEPd81hJMOTcLMO97oBbOVXnPPxc"}', '{}', '5000');
CREATE TRIGGER trg_touch_cratelist_from_item AFTER INSERT OR DELETE OR UPDATE ON cratelist_items FOR EACH ROW EXECUTE FUNCTION touch_cratelist_from_item();
CREATE TRIGGER trg_handle_new_cratelist AFTER INSERT ON cratelists FOR EACH ROW EXECUTE FUNCTION handle_new_cratelist();
CREATE TRIGGER trg_touch_cratelist_updated_at BEFORE UPDATE ON cratelists FOR EACH ROW EXECUTE FUNCTION touch_cratelist_updated_at();
CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER on_device_command_created AFTER INSERT ON device_commands FOR EACH ROW WHEN (new.status = 'pending'::text) EXECUTE FUNCTION broadcast_device_command();
CREATE TRIGGER trigger_device_commands_updated_at BEFORE UPDATE ON device_commands FOR EACH ROW EXECUTE FUNCTION update_device_commands_updated_at();
CREATE TRIGGER on_command_ack_heartbeat AFTER INSERT ON device_heartbeats FOR EACH ROW WHEN (new.type = ANY (ARRAY['command_ack'::text, 'command_result'::text])) EXECUTE FUNCTION update_command_on_ack();
CREATE TRIGGER on_heartbeat_populate_telemetry BEFORE INSERT ON device_heartbeats FOR EACH ROW EXECUTE FUNCTION populate_heartbeat_telemetry();
CREATE TRIGGER on_heartbeat_sync AFTER INSERT ON device_heartbeats FOR EACH ROW EXECUTE FUNCTION sync_heartbeat_to_device_and_unit();
CREATE TRIGGER update_device_sessions_updated_at BEFORE UPDATE ON device_sessions FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_device_types_updated_at BEFORE UPDATE ON device_types FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_devices_updated_at BEFORE UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION update_devices_updated_at();
CREATE TRIGGER update_files_updated_at BEFORE UPDATE ON files FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_gcode_files_updated_at BEFORE UPDATE ON gcode_files FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER on_library_created AFTER INSERT ON libraries FOR EACH ROW EXECUTE FUNCTION handle_new_library();
CREATE TRIGGER update_libraries_updated_at BEFORE UPDATE ON libraries FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER machine_macros_updated_at_trigger BEFORE UPDATE ON machine_macros FOR EACH ROW EXECUTE FUNCTION update_machine_macros_updated_at();
CREATE TRIGGER notification_preferences_updated_at BEFORE UPDATE ON notification_preferences FOR EACH ROW EXECUTE FUNCTION update_notification_preferences_updated_at();
CREATE TRIGGER now_playing_events AFTER INSERT ON now_playing_events FOR EACH ROW EXECUTE FUNCTION supabase_functions.http_request('https://ddhcmhbwppiqrqmefynv.supabase.co/functions/v1/process-now-playing-event', 'POST', '{"Content-type":"application/json","Authorization":"Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRkaGNtaGJ3cHBpcXJxbWVmeW52Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc1OTk1MDA5MSwiZXhwIjoyMDc1NTI2MDkxfQ.KV7Ro37KMRr6D1zQEPd81hJMOTcLMO97oBbOVXnPPxc"}', '{}', '5000');
CREATE TRIGGER update_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_parts_updated_at BEFORE UPDATE ON parts FOR EACH ROW EXECUTE FUNCTION update_parts_updated_at();
CREATE TRIGGER on_playback_event_broadcast AFTER INSERT ON playback_events FOR EACH ROW EXECUTE FUNCTION broadcast_playback_event_to_hubs();
CREATE TRIGGER playback_sessions_updated_at BEFORE UPDATE ON playback_sessions FOR EACH ROW EXECUTE FUNCTION update_playback_session_timestamp();
CREATE TRIGGER update_product_variants_updated_at BEFORE UPDATE ON product_variants FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_production_steps_updated_at BEFORE UPDATE ON production_steps FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_products_updated_at BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_rfid_tag_rolls_updated_at BEFORE UPDATE ON rfid_tag_rolls FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_rfid_tags_updated_at BEFORE UPDATE ON rfid_tags FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_step_labels_updated_at BEFORE UPDATE ON step_labels FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_step_timers_updated_at BEFORE UPDATE ON step_timers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER set_supplier_api_tokens_updated_at BEFORE UPDATE ON supplier_api_tokens FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_thread_networks_updated_at BEFORE UPDATE ON thread_networks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_unit_timers_updated_at BEFORE UPDATE ON unit_timers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_units_updated_at BEFORE UPDATE ON units FOR EACH ROW EXECUTE FUNCTION update_units_updated_at();
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

