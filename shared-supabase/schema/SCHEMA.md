# Saturday Vinyl Database Schema

> Generated from live Supabase database on 2026-02-15.
> Regenerate by exporting schema from Supabase Dashboard > Database > Schema.

## Table of Contents

- [Users & Authentication](#users--authentication)
- [Products & Variants](#products--variants)
- [Device Types & Capabilities](#device-types--capabilities)
- [Units & Devices](#units--devices)
- [Production & Manufacturing](#production--manufacturing)
- [Firmware](#firmware)
- [Device Communication](#device-communication)
- [Orders & Customers](#orders--customers)
- [RFID Tags](#rfid-tags)
- [Albums & Libraries](#albums--libraries)
- [Notifications](#notifications)
- [Files & GCode](#files--gcode)
- [Networking](#networking)
- [Deprecated Tables](#deprecated-tables)

---

## Users & Authentication

### users
Application-level user accounts (linked to Supabase Auth via `auth_user_id`).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| auth_user_id | uuid | | | FK -> auth.users(id) |
| google_id | text | | | UNIQUE |
| email | text | NOT NULL | | UNIQUE |
| full_name | text | | | |
| is_admin | boolean | NOT NULL | false | |
| is_active | boolean | NOT NULL | true | |
| avatar_url | text | | | |
| preferences | jsonb | | '{}' | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |
| last_login | timestamptz | | | |

### permissions
Permission definitions for role-based access control.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL | | UNIQUE |
| description | text | | | |
| created_at | timestamptz | NOT NULL | now() | |

### user_permissions
Join table linking users to permissions.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL | | FK -> users(id) |
| permission_id | uuid | NOT NULL | | FK -> permissions(id) |
| granted_at | timestamptz | NOT NULL | now() | |
| granted_by | uuid | | | FK -> users(id) |

---

## Products & Variants

### products
Product definitions (synced from Shopify).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| shopify_product_id | text | NOT NULL | | UNIQUE |
| shopify_product_handle | text | NOT NULL | | |
| name | text | NOT NULL | | |
| product_code | text | NOT NULL | | UNIQUE |
| short_name | varchar | | | |
| description | text | | | |
| is_active | boolean | NOT NULL | true | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |
| last_synced_at | timestamptz | | | |

### product_variants
Product variant options (synced from Shopify).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| product_id | uuid | NOT NULL | | FK -> products(id) |
| shopify_variant_id | text | NOT NULL | | UNIQUE |
| sku | text | NOT NULL | | |
| name | text | NOT NULL | | |
| option1_name | text | | | |
| option1_value | text | | | |
| option2_name | text | | | |
| option2_value | text | | | |
| option3_name | text | | | |
| option3_value | text | | | |
| price | numeric | NOT NULL | | |
| is_active | boolean | NOT NULL | true | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### product_device_types
Maps products to the device types they contain.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| product_id | uuid | NOT NULL | | PK, FK -> products(id) |
| device_type_id | uuid | NOT NULL | | PK, FK -> device_types(id) |
| quantity | integer | NOT NULL | 1 | CHECK > 0 |

---

## Device Types & Capabilities

### device_types
Hardware device type templates (e.g., "Hub", "Satellite").

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL | | |
| slug | varchar | NOT NULL | | UNIQUE, CHECK lowercase-hyphenated |
| description | text | | | |
| capabilities | text[] | NOT NULL | '{}' | Legacy array |
| chip_type | varchar | | | CHECK esp32 variants |
| soc_types | text[] | | '{}' | Multi-SoC support |
| master_soc | varchar | | | |
| spec_url | text | | | |
| is_active | boolean | NOT NULL | true | |
| current_firmware_version | varchar | | | |
| production_firmware_id | uuid | | | FK -> firmware(id) |
| dev_firmware_id | uuid | | | FK -> firmware(id) |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### capabilities
Dynamic capability definitions with JSON schemas for provisioning and telemetry.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | varchar | NOT NULL | | UNIQUE |
| display_name | varchar | NOT NULL | | |
| description | text | | | |
| factory_input_schema | jsonb | | '{}' | Factory provisioning inputs |
| factory_output_schema | jsonb | | '{}' | Factory provisioning outputs |
| consumer_input_schema | jsonb | | '{}' | Consumer provisioning inputs |
| consumer_output_schema | jsonb | | '{}' | Consumer provisioning outputs |
| heartbeat_schema | jsonb | | '{}' | Telemetry data schema |
| tests | jsonb | | '[]' | Test definitions |
| is_active | boolean | | true | |
| created_at | timestamptz | | now() | |
| updated_at | timestamptz | | now() | |

### device_type_capabilities
Maps device types to their capabilities with configuration.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| device_type_id | uuid | NOT NULL | | FK -> device_types(id) |
| capability_id | uuid | NOT NULL | | FK -> capabilities(id) |
| configuration | jsonb | | '{}' | |
| display_order | integer | | 0 | |
| created_at | timestamptz | | now() | |

---

## Units & Devices

### units
Unified table for manufactured product instances (factory + consumer lifecycle).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| serial_number | varchar | | | UNIQUE |
| product_id | uuid | | | FK -> products(id) |
| variant_id | uuid | | | FK -> product_variants(id) |
| order_id | uuid | | | FK -> orders(id) |
| status | unit_status | | 'in_production' | Enum |
| qr_code_url | text | | | |
| factory_provisioned_at | timestamptz | | | |
| factory_provisioned_by | uuid | | | FK -> users(id) |
| consumer_user_id | uuid | | | |
| consumer_name | varchar | | | |
| production_started_at | timestamptz | | | |
| production_completed_at | timestamptz | | | |
| is_completed | boolean | | false | |
| created_at | timestamptz | | now() | |
| updated_at | timestamptz | | now() | |
| created_by | uuid | | | FK -> users(id) |

### devices
Hardware instances (PCBs identified by MAC address).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| mac_address | varchar | NOT NULL | | UNIQUE |
| unit_id | uuid | | | FK -> units(id) |
| device_type_slug | varchar | | | FK -> device_types(slug) |
| firmware_version | varchar | | | |
| firmware_id | uuid | | | FK -> firmware(id) |
| status | varchar | | 'unprovisioned' | |
| provision_data | jsonb | | '{}' | |
| latest_telemetry | jsonb | | '{}' | |
| factory_provisioned_at | timestamptz | | | |
| factory_provisioned_by | uuid | | | FK -> users(id) |
| consumer_provisioned_at | timestamptz | | | |
| consumer_provisioned_by | uuid | | | FK -> users(id) |
| last_seen_at | timestamptz | | | |
| created_at | timestamptz | | now() | |
| updated_at | timestamptz | | now() | |

### consumer_devices
Consumer-facing device instances (registered by end users in the mobile app).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL | | FK -> users(id) |
| device_type | enum | NOT NULL | | consumer_device_type |
| name | text | NOT NULL | | |
| serial_number | text | NOT NULL | | UNIQUE |
| production_unit_id | uuid | | | FK -> production_units(id) |
| firmware_version | text | | | |
| status | enum | NOT NULL | 'offline' | consumer_device_status |
| battery_level | integer | | | CHECK 0-100 |
| last_seen_at | timestamptz | | | |
| settings | jsonb | | '{}' | |
| created_at | timestamptz | NOT NULL | now() | |

---

## Production & Manufacturing

### production_steps
Step definitions for product assembly workflows.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| product_id | uuid | NOT NULL | | FK -> products(id) |
| name | text | NOT NULL | | |
| description | text | | | |
| step_order | integer | NOT NULL | | CHECK > 0 |
| step_type | step_type | NOT NULL | 'general' | Enum |
| file_url | text | | | |
| file_name | text | | | |
| file_type | text | | | |
| generate_label | boolean | NOT NULL | false | |
| label_text | text | | | |
| engrave_qr | boolean | NOT NULL | false | |
| qr_x_offset | numeric | | | |
| qr_y_offset | numeric | | | |
| qr_size | numeric | | | CHECK > 0 |
| qr_power_percent | integer | | | CHECK 0-100 |
| qr_speed_mm_min | integer | | | CHECK > 0 |
| firmware_version_id | uuid | | | FK -> firmware(id) |
| provisioning_manifest | jsonb | | | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### unit_step_completions
Tracks which steps have been completed for each unit.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | uuid_generate_v4() | PK |
| unit_id | uuid | NOT NULL | | FK -> units(id) |
| step_id | uuid | NOT NULL | | FK -> production_steps(id) |
| completed_at | timestamptz | | now() | |
| completed_by | uuid | NOT NULL | | FK -> users(id) |
| notes | text | | | |

### step_labels
Labels associated with production steps.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| step_id | uuid | NOT NULL | | FK -> production_steps(id) |
| label_text | text | NOT NULL | | |
| label_order | integer | NOT NULL | 1 | CHECK > 0 |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### step_timers
Timer definitions for production steps (curing, drying, etc.).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| step_id | uuid | NOT NULL | | FK -> production_steps(id) |
| timer_name | text | NOT NULL | | |
| duration_minutes | integer | NOT NULL | | CHECK > 0 |
| timer_order | integer | NOT NULL | 1 | CHECK > 0 |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### unit_timers
Active timer instances for specific units.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| unit_id | uuid | NOT NULL | | FK -> units(id) |
| step_timer_id | uuid | NOT NULL | | FK -> step_timers(id) |
| started_at | timestamptz | NOT NULL | | |
| expires_at | timestamptz | NOT NULL | | |
| completed_at | timestamptz | | | |
| status | text | NOT NULL | 'active' | CHECK: active/completed/cancelled |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### machine_macros
CNC and laser machine macro definitions.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL | | CHECK non-empty |
| description | text | | | |
| machine_type | text | NOT NULL | | CHECK: cnc/laser |
| icon_name | text | NOT NULL | | CHECK non-empty |
| gcode_commands | text | NOT NULL | | CHECK non-empty |
| execution_order | integer | NOT NULL | 1 | CHECK > 0 |
| is_active | boolean | NOT NULL | true | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

---

## Firmware

### firmware
Firmware version records (renamed from firmware_versions).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | uuid_generate_v4() | PK |
| device_type_id | uuid | NOT NULL | | FK -> device_types(id) |
| version | varchar | NOT NULL | | |
| release_notes | text | | | |
| binary_url | text | | | Nullable |
| binary_filename | varchar | | | Nullable |
| binary_size | bigint | | | |
| is_production_ready | boolean | | false | |
| is_critical | boolean | | false | |
| released_at | timestamptz | | | |
| provisioning_manifest | jsonb | | | |
| created_at | timestamptz | | now() | |
| created_by | uuid | | | FK -> auth.users(id) |

### firmware_files
Per-SoC firmware binary files (for multi-SoC devices).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| firmware_id | uuid | NOT NULL | | FK -> firmware(id) |
| soc_type | varchar | NOT NULL | | |
| is_master | boolean | | false | |
| file_url | text | NOT NULL | | |
| file_sha256 | text | | | |
| file_size | integer | | | |
| created_at | timestamptz | | now() | |

---

## Device Communication

### device_commands
Command queue for device operations (provision, test, reboot, OTA, etc.).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| mac_address | varchar | NOT NULL | | |
| command | text | NOT NULL | | |
| capability | text | | | |
| test_name | text | | | |
| parameters | jsonb | | '{}' | |
| priority | integer | | 0 | |
| status | text | | 'pending' | |
| expires_at | timestamptz | | | |
| result | jsonb | | | |
| error_message | text | | | |
| retry_count | integer | | 0 | |
| created_at | timestamptz | | now() | |
| updated_at | timestamptz | | now() | |
| created_by | uuid | | | FK -> users(id) |

### device_heartbeats
Device telemetry and status updates.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| mac_address | varchar | | | |
| unit_id | text | | | |
| device_type | text | NOT NULL | | |
| type | text | | 'status' | status/command_ack |
| command_id | uuid | | | FK -> device_commands(id) |
| relay_device_type | text | | | |
| relay_instance_id | text | | | |
| firmware_version | text | | | |
| battery_level | integer | | | CHECK 0-100 |
| battery_charging | boolean | | | |
| wifi_rssi | integer | | | |
| thread_rssi | integer | | | |
| uptime_sec | integer | | | |
| free_heap | integer | | | |
| min_free_heap | integer | | | |
| largest_free_block | integer | | | |
| created_at | timestamptz | NOT NULL | now() | |

### now_playing_events
Real-time record placement/removal events from RFID readers.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| unit_id | text | NOT NULL | | |
| epc | text | NOT NULL | | RFID tag EPC |
| event_type | text | NOT NULL | | CHECK: placed/removed |
| rssi | integer | | | Signal strength |
| duration_ms | integer | | | |
| timestamp | timestamptz | NOT NULL | now() | |
| created_at | timestamptz | NOT NULL | now() | |

---

## Orders & Customers

### orders
Shopify order records.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| shopify_order_id | varchar | NOT NULL | | UNIQUE |
| shopify_order_number | varchar | NOT NULL | | |
| customer_id | uuid | | | FK -> customers(id) |
| order_date | timestamptz | NOT NULL | | |
| status | varchar | NOT NULL | | |
| fulfillment_status | varchar | | | |
| assigned_unit_id | uuid | | | FK -> units(id) |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### order_line_items
Individual items within orders.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| order_id | uuid | NOT NULL | | FK -> orders(id) |
| product_id | uuid | | | FK -> products(id) |
| variant_id | uuid | | | FK -> product_variants(id) |
| shopify_product_id | varchar | NOT NULL | | |
| shopify_variant_id | varchar | NOT NULL | | |
| title | varchar | NOT NULL | | |
| quantity | integer | NOT NULL | 1 | |
| price | varchar | | | |
| created_at | timestamptz | NOT NULL | now() | |

### customers
Shopify customer records.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| shopify_customer_id | varchar | NOT NULL | | UNIQUE |
| email | varchar | NOT NULL | | |
| first_name | varchar | | | |
| last_name | varchar | | | |
| phone | varchar | | | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

---

## RFID Tags

### rfid_tags
Individual RFID tags with lifecycle tracking.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| epc_identifier | varchar | NOT NULL | | UNIQUE |
| tid | varchar | | | Tag ID |
| status | varchar | NOT NULL | 'generated' | CHECK: generated/written/active/retired |
| library_album_id | uuid | | | FK -> library_albums(id) |
| roll_id | uuid | | | FK -> rfid_tag_rolls(id) |
| roll_position | integer | | | CHECK > 0 |
| written_at | timestamptz | | | |
| locked_at | timestamptz | | | |
| associated_at | timestamptz | | | |
| associated_by | uuid | | | FK -> users(id) |
| last_seen_at | timestamptz | | | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |
| created_by | uuid | | | FK -> users(id) |

### rfid_tag_rolls
Batches of RFID tags on physical rolls.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| label_width_mm | numeric | NOT NULL | | |
| label_height_mm | numeric | NOT NULL | | |
| label_count | integer | NOT NULL | | CHECK > 0 |
| status | varchar | NOT NULL | 'writing' | CHECK: writing/ready_to_print/printing/completed |
| last_printed_position | integer | NOT NULL | 0 | CHECK >= 0 |
| manufacturer_url | text | | | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |
| created_by | uuid | | | FK -> users(id) |

---

## Albums & Libraries

### albums
Album metadata (from Discogs).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| discogs_id | integer | | | UNIQUE |
| title | text | NOT NULL | | |
| artist | text | NOT NULL | | |
| year | integer | | | |
| genres | text[] | | '{}' | |
| styles | text[] | | '{}' | |
| label | text | | | |
| cover_image_url | text | | | |
| tracks | jsonb | | '[]' | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### libraries
User-created album collections.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| name | text | NOT NULL | | |
| description | text | | | |
| created_by | uuid | NOT NULL | | FK -> users(id) |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### library_albums
Albums within a library.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| library_id | uuid | NOT NULL | | FK -> libraries(id) |
| album_id | uuid | NOT NULL | | FK -> albums(id) |
| added_by | uuid | NOT NULL | | FK -> users(id) |
| added_at | timestamptz | NOT NULL | now() | |
| notes | text | | | |
| is_favorite | boolean | NOT NULL | false | |

### library_members
Users with access to a library.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| library_id | uuid | NOT NULL | | FK -> libraries(id) |
| user_id | uuid | NOT NULL | | FK -> users(id) |
| role | library_role | NOT NULL | 'viewer' | Enum |
| joined_at | timestamptz | NOT NULL | now() | |
| invited_by | uuid | | | FK -> users(id) |

### library_invitations
Pending invitations to join a library.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| library_id | uuid | NOT NULL | | FK -> libraries(id) |
| invited_email | text | NOT NULL | | |
| invited_user_id | uuid | | | FK -> users(id) |
| role | library_role | NOT NULL | 'viewer' | Enum |
| status | invitation_status | NOT NULL | 'pending' | Enum |
| token | text | NOT NULL | | UNIQUE |
| invited_by | uuid | NOT NULL | | FK -> users(id) |
| finalized_user_id | uuid | | | FK -> users(id) |
| created_at | timestamptz | NOT NULL | now() | |
| expires_at | timestamptz | NOT NULL | now() + 7 days | |
| accepted_at | timestamptz | | | |

### album_locations
Tracks which device an album is currently on.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| library_album_id | uuid | NOT NULL | | FK -> library_albums(id) |
| device_id | uuid | NOT NULL | | FK -> consumer_devices(id) |
| detected_at | timestamptz | NOT NULL | now() | |
| removed_at | timestamptz | | | |

### listening_history
User listening history (album plays).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL | | FK -> users(id) |
| library_album_id | uuid | NOT NULL | | FK -> library_albums(id) |
| played_at | timestamptz | NOT NULL | now() | |
| play_duration_seconds | integer | | | |
| completed_side | enum | | | |
| device_id | uuid | | | FK -> consumer_devices(id) |

---

## Notifications

### push_notification_tokens
Mobile device push notification tokens.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL | | FK -> users(id) |
| token | text | NOT NULL | | |
| platform | text | NOT NULL | | CHECK: ios/android |
| device_identifier | text | NOT NULL | | |
| app_version | text | | | |
| is_active | boolean | NOT NULL | true | |
| last_used_at | timestamptz | | | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### notification_preferences
Per-user notification settings.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL | | UNIQUE, FK -> users(id) |
| now_playing_enabled | boolean | NOT NULL | true | |
| flip_reminders_enabled | boolean | NOT NULL | true | |
| device_offline_enabled | boolean | NOT NULL | true | |
| device_online_enabled | boolean | NOT NULL | true | |
| battery_low_enabled | boolean | NOT NULL | true | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### notification_delivery_log
Notification send/delivery tracking.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL | | FK -> users(id) |
| notification_type | text | NOT NULL | | |
| source_id | uuid | | | |
| token_id | uuid | | | FK -> push_notification_tokens(id) |
| status | text | NOT NULL | | CHECK: pending/sent/failed/delivered |
| error_message | text | | | |
| sent_at | timestamptz | | | |
| delivered_at | timestamptz | | | |
| created_at | timestamptz | NOT NULL | now() | |

### device_status_notifications
Tracks recent device status notifications to prevent duplicates.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| unit_id | uuid | NOT NULL | | FK -> units(id) |
| user_id | uuid | NOT NULL | | FK -> users(id) |
| notification_type | text | NOT NULL | | |
| last_sent_at | timestamptz | NOT NULL | now() | |
| context_data | jsonb | | | |

### user_now_playing_notifications
Pre-enriched now-playing notifications for mobile push.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| user_id | uuid | NOT NULL | | FK -> users(id) |
| source_event_id | uuid | NOT NULL | | |
| unit_id | text | NOT NULL | | |
| epc | text | NOT NULL | | |
| event_type | text | NOT NULL | | CHECK: placed/removed |
| library_album_id | uuid | | | FK -> library_albums(id) |
| album_title | text | | | |
| album_artist | text | | | |
| cover_image_url | text | | | |
| library_id | uuid | | | FK -> libraries(id) |
| library_name | text | | | |
| device_id | uuid | | | FK -> consumer_devices(id) |
| device_name | text | | | |
| event_timestamp | timestamptz | NOT NULL | | |
| created_at | timestamptz | NOT NULL | now() | |

---

## Files & GCode

### files
Production file library (PDFs, images, videos for production steps).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| storage_path | text | NOT NULL | | UNIQUE |
| file_name | text | NOT NULL | | UNIQUE |
| description | text | | | |
| mime_type | text | NOT NULL | | |
| file_size_bytes | integer | NOT NULL | | CHECK > 0, max 50MB |
| uploaded_by_name | text | NOT NULL | | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### step_files
Links production files to production steps.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| step_id | uuid | NOT NULL | | FK -> production_steps(id) |
| file_id | uuid | NOT NULL | | FK -> files(id) |
| execution_order | integer | NOT NULL | | CHECK > 0 |
| created_at | timestamptz | NOT NULL | now() | |

### gcode_files
GCode files for CNC/laser operations (sourced from GitHub).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| github_path | text | NOT NULL | | UNIQUE |
| file_name | text | NOT NULL | | |
| description | text | | | |
| machine_type | text | NOT NULL | | |
| created_at | timestamptz | NOT NULL | now() | |
| updated_at | timestamptz | NOT NULL | now() | |

### step_gcode_files
Links GCode files to production steps.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | gen_random_uuid() | PK |
| step_id | uuid | NOT NULL | | FK -> production_steps(id) |
| gcode_file_id | uuid | NOT NULL | | FK -> gcode_files(id) |
| execution_order | integer | NOT NULL | | CHECK > 0 |
| created_at | timestamptz | NOT NULL | now() | |

---

## Networking

### thread_credentials
Thread Border Router network credentials (one per unit).

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | uuid_generate_v4() | PK |
| unit_id | uuid | NOT NULL | | UNIQUE, FK -> units(id) |
| network_name | varchar | NOT NULL | | |
| pan_id | integer | NOT NULL | | CHECK 0-65534 |
| channel | integer | NOT NULL | | CHECK 11-26 |
| network_key | varchar | NOT NULL | | 32-char hex |
| extended_pan_id | varchar | NOT NULL | | 16-char hex |
| mesh_local_prefix | varchar | NOT NULL | | 16-char hex |
| pskc | varchar | NOT NULL | | 32-char hex |
| created_at | timestamptz | | now() | |
| updated_at | timestamptz | | now() | |

---

## Deprecated Tables

### production_units
**Deprecated** - replaced by `units` table. Kept for backward compatibility during transition.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| id | uuid | NOT NULL | uuid_generate_v4() | PK |
| uuid | uuid | NOT NULL | uuid_generate_v4() | UNIQUE |
| unit_id | varchar | NOT NULL | | UNIQUE |
| product_id | uuid | NOT NULL | | FK -> products(id) |
| variant_id | uuid | NOT NULL | | FK -> product_variants(id) |
| shopify_order_id | varchar | | | |
| shopify_order_number | varchar | | | |
| customer_name | varchar | | | |
| current_owner_id | uuid | | | FK -> users(id) |
| qr_code_url | text | NOT NULL | | |
| mac_address | varchar | | | CHECK MAC format |
| production_started_at | timestamptz | | | |
| production_completed_at | timestamptz | | | |
| is_completed | boolean | | false | |
| created_at | timestamptz | | now() | |
| created_by | uuid | NOT NULL | | FK -> users(id) |

### legacy_qr_code_lookup
Maps old QR code UUIDs to new unit IDs during migration.

| Column | Type | Nullable | Default | Notes |
|--------|------|----------|---------|-------|
| old_uuid | uuid | NOT NULL | | PK |
| unit_id | uuid | NOT NULL | | FK -> units(id) |
| notes | text | | | |
| created_at | timestamptz | | now() | |
