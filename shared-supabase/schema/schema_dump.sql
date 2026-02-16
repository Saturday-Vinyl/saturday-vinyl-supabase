-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.album_locations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  library_album_id uuid NOT NULL,
  device_id uuid NOT NULL,
  detected_at timestamp with time zone NOT NULL DEFAULT now(),
  removed_at timestamp with time zone,
  CONSTRAINT album_locations_pkey PRIMARY KEY (id),
  CONSTRAINT album_locations_library_album_id_fkey FOREIGN KEY (library_album_id) REFERENCES public.library_albums(id),
  CONSTRAINT album_locations_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.consumer_devices(id)
);
CREATE TABLE public.albums (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  discogs_id integer UNIQUE,
  title text NOT NULL,
  artist text NOT NULL,
  year integer,
  genres ARRAY DEFAULT '{}'::text[],
  styles ARRAY DEFAULT '{}'::text[],
  label text,
  cover_image_url text,
  tracks jsonb DEFAULT '[]'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT albums_pkey PRIMARY KEY (id)
);
CREATE TABLE public.capabilities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name character varying NOT NULL UNIQUE,
  display_name character varying NOT NULL,
  description text,
  factory_input_schema jsonb DEFAULT '{}'::jsonb,
  factory_output_schema jsonb DEFAULT '{}'::jsonb,
  consumer_input_schema jsonb DEFAULT '{}'::jsonb,
  consumer_output_schema jsonb DEFAULT '{}'::jsonb,
  heartbeat_schema jsonb DEFAULT '{}'::jsonb,
  tests jsonb DEFAULT '[]'::jsonb,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT capabilities_pkey PRIMARY KEY (id)
);
CREATE TABLE public.consumer_devices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  device_type USER-DEFINED NOT NULL,
  name text NOT NULL,
  serial_number text NOT NULL UNIQUE,
  production_unit_id uuid,
  firmware_version text,
  status USER-DEFINED NOT NULL DEFAULT 'offline'::consumer_device_status,
  battery_level integer CHECK (battery_level >= 0 AND battery_level <= 100),
  last_seen_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  settings jsonb DEFAULT '{}'::jsonb,
  CONSTRAINT consumer_devices_pkey PRIMARY KEY (id),
  CONSTRAINT consumer_devices_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT consumer_devices_production_unit_id_fkey FOREIGN KEY (production_unit_id) REFERENCES public.production_units(id)
);
CREATE TABLE public.customers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  shopify_customer_id character varying NOT NULL UNIQUE,
  email character varying NOT NULL,
  first_name character varying,
  last_name character varying,
  phone character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT customers_pkey PRIMARY KEY (id)
);
CREATE TABLE public.device_commands (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mac_address character varying NOT NULL,
  command text NOT NULL,
  capability text,
  test_name text,
  parameters jsonb DEFAULT '{}'::jsonb,
  priority integer DEFAULT 0,
  status text DEFAULT 'pending'::text,
  expires_at timestamp with time zone,
  result jsonb,
  error_message text,
  retry_count integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  CONSTRAINT device_commands_pkey PRIMARY KEY (id),
  CONSTRAINT device_commands_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)
);
CREATE TABLE public.device_heartbeats (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  device_type text NOT NULL,
  relay_device_type text,
  relay_instance_id text,
  firmware_version text,
  battery_level integer CHECK (battery_level IS NULL OR battery_level >= 0 AND battery_level <= 100),
  battery_charging boolean,
  wifi_rssi integer,
  thread_rssi integer,
  uptime_sec integer,
  free_heap integer,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  mac_address character varying,
  min_free_heap integer,
  largest_free_block integer,
  unit_id text,
  type text DEFAULT 'status'::text,
  command_id uuid,
  CONSTRAINT device_heartbeats_pkey PRIMARY KEY (id),
  CONSTRAINT device_heartbeats_command_id_fkey FOREIGN KEY (command_id) REFERENCES public.device_commands(id)
);
CREATE TABLE public.device_status_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  unit_id uuid NOT NULL,
  user_id uuid NOT NULL,
  notification_type text NOT NULL,
  last_sent_at timestamp with time zone NOT NULL DEFAULT now(),
  context_data jsonb,
  CONSTRAINT device_status_notifications_pkey PRIMARY KEY (id),
  CONSTRAINT device_status_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT device_status_notifications_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id)
);
CREATE TABLE public.device_type_capabilities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  device_type_id uuid NOT NULL,
  capability_id uuid NOT NULL,
  configuration jsonb DEFAULT '{}'::jsonb,
  display_order integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT device_type_capabilities_pkey PRIMARY KEY (id),
  CONSTRAINT device_type_capabilities_device_type_id_fkey FOREIGN KEY (device_type_id) REFERENCES public.device_types(id),
  CONSTRAINT device_type_capabilities_capability_id_fkey FOREIGN KEY (capability_id) REFERENCES public.capabilities(id)
);
CREATE TABLE public.device_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  capabilities ARRAY NOT NULL DEFAULT '{}'::text[],
  spec_url text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  current_firmware_version character varying,
  chip_type character varying CHECK (chip_type IS NULL OR (chip_type::text = ANY (ARRAY['esp32'::character varying, 'esp32s2'::character varying, 'esp32s3'::character varying, 'esp32c3'::character varying, 'esp32c6'::character varying, 'esp32h2'::character varying]::text[]))),
  soc_types ARRAY DEFAULT '{}'::text[],
  master_soc character varying,
  production_firmware_id uuid,
  dev_firmware_id uuid,
  slug character varying NOT NULL CHECK (slug::text ~ '^[a-z0-9]+(-[a-z0-9]+)*$'::text),
  CONSTRAINT device_types_pkey PRIMARY KEY (id),
  CONSTRAINT device_types_production_firmware_id_fkey FOREIGN KEY (production_firmware_id) REFERENCES public.firmware(id),
  CONSTRAINT device_types_dev_firmware_id_fkey FOREIGN KEY (dev_firmware_id) REFERENCES public.firmware(id)
);
CREATE TABLE public.devices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mac_address character varying NOT NULL UNIQUE,
  unit_id uuid,
  firmware_version character varying,
  firmware_id uuid,
  factory_provisioned_at timestamp with time zone,
  factory_provisioned_by uuid,
  status character varying DEFAULT 'unprovisioned'::character varying,
  last_seen_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  provision_data jsonb DEFAULT '{}'::jsonb,
  latest_telemetry jsonb DEFAULT '{}'::jsonb,
  device_type_slug character varying,
  consumer_provisioned_at timestamp with time zone,
  consumer_provisioned_by uuid,
  CONSTRAINT devices_pkey PRIMARY KEY (id),
  CONSTRAINT devices_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id),
  CONSTRAINT devices_factory_provisioned_by_fkey FOREIGN KEY (factory_provisioned_by) REFERENCES public.users(id),
  CONSTRAINT devices_firmware_id_fkey FOREIGN KEY (firmware_id) REFERENCES public.firmware(id),
  CONSTRAINT fk_devices_device_type_slug FOREIGN KEY (device_type_slug) REFERENCES public.device_types(slug),
  CONSTRAINT devices_consumer_provisioned_by_fkey FOREIGN KEY (consumer_provisioned_by) REFERENCES public.users(id)
);
CREATE TABLE public.files (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  storage_path text NOT NULL UNIQUE,
  file_name text NOT NULL UNIQUE,
  description text,
  mime_type text NOT NULL,
  file_size_bytes integer NOT NULL CHECK (file_size_bytes > 0 AND file_size_bytes <= 52428800),
  uploaded_by_name text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT files_pkey PRIMARY KEY (id)
);
CREATE TABLE public.firmware (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  device_type_id uuid NOT NULL,
  version character varying NOT NULL,
  release_notes text,
  binary_url text,
  binary_filename character varying,
  binary_size bigint,
  is_production_ready boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  provisioning_manifest jsonb,
  is_critical boolean DEFAULT false,
  released_at timestamp with time zone,
  CONSTRAINT firmware_pkey PRIMARY KEY (id),
  CONSTRAINT firmware_versions_device_type_id_fkey FOREIGN KEY (device_type_id) REFERENCES public.device_types(id),
  CONSTRAINT firmware_versions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id)
);
CREATE TABLE public.firmware_files (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  firmware_id uuid NOT NULL,
  soc_type character varying NOT NULL,
  is_master boolean DEFAULT false,
  file_url text NOT NULL,
  file_sha256 text,
  file_size integer,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT firmware_files_pkey PRIMARY KEY (id),
  CONSTRAINT firmware_files_firmware_id_fkey FOREIGN KEY (firmware_id) REFERENCES public.firmware(id)
);
CREATE TABLE public.gcode_files (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  github_path text NOT NULL UNIQUE,
  file_name text NOT NULL,
  description text,
  machine_type text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT gcode_files_pkey PRIMARY KEY (id)
);
CREATE TABLE public.legacy_qr_code_lookup (
  old_uuid uuid NOT NULL,
  unit_id uuid NOT NULL,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT legacy_qr_code_lookup_pkey PRIMARY KEY (old_uuid),
  CONSTRAINT legacy_qr_code_lookup_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id)
);
CREATE TABLE public.libraries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid NOT NULL,
  CONSTRAINT libraries_pkey PRIMARY KEY (id),
  CONSTRAINT libraries_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)
);
CREATE TABLE public.library_albums (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  library_id uuid NOT NULL,
  album_id uuid NOT NULL,
  added_at timestamp with time zone NOT NULL DEFAULT now(),
  added_by uuid NOT NULL,
  notes text,
  is_favorite boolean NOT NULL DEFAULT false,
  CONSTRAINT library_albums_pkey PRIMARY KEY (id),
  CONSTRAINT library_albums_library_id_fkey FOREIGN KEY (library_id) REFERENCES public.libraries(id),
  CONSTRAINT library_albums_album_id_fkey FOREIGN KEY (album_id) REFERENCES public.albums(id),
  CONSTRAINT library_albums_added_by_fkey FOREIGN KEY (added_by) REFERENCES public.users(id)
);
CREATE TABLE public.library_invitations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  library_id uuid NOT NULL,
  invited_email text NOT NULL,
  invited_user_id uuid,
  role USER-DEFINED NOT NULL DEFAULT 'viewer'::library_role,
  status USER-DEFINED NOT NULL DEFAULT 'pending'::invitation_status,
  token text NOT NULL UNIQUE,
  invited_by uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  expires_at timestamp with time zone NOT NULL DEFAULT (now() + '7 days'::interval),
  accepted_at timestamp with time zone,
  finalized_user_id uuid,
  CONSTRAINT library_invitations_pkey PRIMARY KEY (id),
  CONSTRAINT library_invitations_library_id_fkey FOREIGN KEY (library_id) REFERENCES public.libraries(id),
  CONSTRAINT library_invitations_invited_user_id_fkey FOREIGN KEY (invited_user_id) REFERENCES public.users(id),
  CONSTRAINT library_invitations_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.users(id),
  CONSTRAINT library_invitations_finalized_user_id_fkey FOREIGN KEY (finalized_user_id) REFERENCES public.users(id)
);
CREATE TABLE public.library_members (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  library_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role USER-DEFINED NOT NULL DEFAULT 'viewer'::library_role,
  joined_at timestamp with time zone NOT NULL DEFAULT now(),
  invited_by uuid,
  CONSTRAINT library_members_pkey PRIMARY KEY (id),
  CONSTRAINT library_members_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.users(id),
  CONSTRAINT library_members_library_id_fkey FOREIGN KEY (library_id) REFERENCES public.libraries(id),
  CONSTRAINT library_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.listening_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  library_album_id uuid NOT NULL,
  played_at timestamp with time zone NOT NULL DEFAULT now(),
  play_duration_seconds integer,
  completed_side USER-DEFINED,
  device_id uuid,
  CONSTRAINT listening_history_pkey PRIMARY KEY (id),
  CONSTRAINT listening_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT listening_history_library_album_id_fkey FOREIGN KEY (library_album_id) REFERENCES public.library_albums(id),
  CONSTRAINT listening_history_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.consumer_devices(id)
);
CREATE TABLE public.machine_macros (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(TRIM(BOTH FROM name)) > 0),
  description text,
  machine_type text NOT NULL CHECK (machine_type = ANY (ARRAY['cnc'::text, 'laser'::text])),
  icon_name text NOT NULL CHECK (length(TRIM(BOTH FROM icon_name)) > 0),
  gcode_commands text NOT NULL CHECK (length(TRIM(BOTH FROM gcode_commands)) > 0),
  execution_order integer NOT NULL DEFAULT 1 CHECK (execution_order > 0),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT machine_macros_pkey PRIMARY KEY (id)
);
CREATE TABLE public.notification_delivery_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  notification_type text NOT NULL,
  source_id uuid,
  token_id uuid,
  status text NOT NULL CHECK (status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text, 'delivered'::text])),
  error_message text,
  sent_at timestamp with time zone,
  delivered_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT notification_delivery_log_pkey PRIMARY KEY (id),
  CONSTRAINT notification_delivery_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT notification_delivery_log_token_id_fkey FOREIGN KEY (token_id) REFERENCES public.push_notification_tokens(id)
);
CREATE TABLE public.notification_preferences (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  now_playing_enabled boolean NOT NULL DEFAULT true,
  flip_reminders_enabled boolean NOT NULL DEFAULT true,
  device_offline_enabled boolean NOT NULL DEFAULT true,
  device_online_enabled boolean NOT NULL DEFAULT true,
  battery_low_enabled boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT notification_preferences_pkey PRIMARY KEY (id),
  CONSTRAINT notification_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.now_playing_events (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  unit_id text NOT NULL,
  epc text NOT NULL,
  event_type text NOT NULL CHECK (event_type = ANY (ARRAY['placed'::text, 'removed'::text])),
  rssi integer,
  duration_ms integer,
  timestamp timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT now_playing_events_pkey PRIMARY KEY (id)
);
CREATE TABLE public.order_line_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL,
  product_id uuid,
  variant_id uuid,
  shopify_product_id character varying NOT NULL,
  shopify_variant_id character varying NOT NULL,
  title character varying NOT NULL,
  quantity integer NOT NULL DEFAULT 1,
  price character varying,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT order_line_items_pkey PRIMARY KEY (id),
  CONSTRAINT order_line_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT order_line_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT order_line_items_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id)
);
CREATE TABLE public.orders (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  shopify_order_id character varying NOT NULL UNIQUE,
  shopify_order_number character varying NOT NULL,
  customer_id uuid,
  order_date timestamp with time zone NOT NULL,
  status character varying NOT NULL,
  fulfillment_status character varying,
  assigned_unit_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT orders_pkey PRIMARY KEY (id),
  CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id),
  CONSTRAINT orders_units_fkey FOREIGN KEY (assigned_unit_id) REFERENCES public.units(id)
);
CREATE TABLE public.permissions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  description text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT permissions_pkey PRIMARY KEY (id)
);
CREATE TABLE public.product_device_types (
  product_id uuid NOT NULL,
  device_type_id uuid NOT NULL,
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
  CONSTRAINT product_device_types_pkey PRIMARY KEY (product_id, device_type_id),
  CONSTRAINT product_device_types_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT product_device_types_device_type_id_fkey FOREIGN KEY (device_type_id) REFERENCES public.device_types(id)
);
CREATE TABLE public.product_variants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  shopify_variant_id text NOT NULL UNIQUE,
  sku text NOT NULL,
  name text NOT NULL,
  option1_name text,
  option1_value text,
  option2_name text,
  option2_value text,
  option3_name text,
  option3_value text,
  price numeric NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT product_variants_pkey PRIMARY KEY (id),
  CONSTRAINT product_variants_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id)
);
CREATE TABLE public.production_steps (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  product_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  step_order integer NOT NULL CHECK (step_order > 0),
  file_url text,
  file_name text,
  file_type text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  generate_label boolean NOT NULL DEFAULT false,
  label_text text,
  step_type USER-DEFINED NOT NULL DEFAULT 'general'::step_type,
  engrave_qr boolean NOT NULL DEFAULT false,
  qr_x_offset numeric,
  qr_y_offset numeric,
  qr_size numeric CHECK (qr_size IS NULL OR qr_size > 0::numeric),
  qr_power_percent integer CHECK (qr_power_percent IS NULL OR qr_power_percent >= 0 AND qr_power_percent <= 100),
  qr_speed_mm_min integer CHECK (qr_speed_mm_min IS NULL OR qr_speed_mm_min > 0),
  firmware_version_id uuid,
  provisioning_manifest jsonb,
  CONSTRAINT production_steps_pkey PRIMARY KEY (id),
  CONSTRAINT production_steps_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT production_steps_firmware_version_id_fkey FOREIGN KEY (firmware_version_id) REFERENCES public.firmware(id)
);
CREATE TABLE public.production_units (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  uuid uuid NOT NULL DEFAULT uuid_generate_v4() UNIQUE,
  unit_id character varying NOT NULL UNIQUE,
  product_id uuid NOT NULL,
  variant_id uuid NOT NULL,
  shopify_order_id character varying,
  shopify_order_number character varying,
  customer_name character varying,
  current_owner_id uuid,
  qr_code_url text NOT NULL,
  production_started_at timestamp with time zone,
  production_completed_at timestamp with time zone,
  is_completed boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  created_by uuid NOT NULL,
  mac_address character varying CHECK (mac_address IS NULL OR mac_address::text ~ '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$'::text),
  CONSTRAINT production_units_pkey PRIMARY KEY (id),
  CONSTRAINT production_units_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT production_units_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id),
  CONSTRAINT production_units_current_owner_id_fkey FOREIGN KEY (current_owner_id) REFERENCES public.users(id),
  CONSTRAINT production_units_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)
);
CREATE TABLE public.products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  shopify_product_id text NOT NULL UNIQUE,
  shopify_product_handle text NOT NULL,
  name text NOT NULL,
  product_code text NOT NULL UNIQUE,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  last_synced_at timestamp with time zone,
  short_name character varying,
  CONSTRAINT products_pkey PRIMARY KEY (id)
);
CREATE TABLE public.push_notification_tokens (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  token text NOT NULL,
  platform text NOT NULL CHECK (platform = ANY (ARRAY['ios'::text, 'android'::text])),
  device_identifier text NOT NULL,
  app_version text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  last_used_at timestamp with time zone,
  is_active boolean NOT NULL DEFAULT true,
  CONSTRAINT push_notification_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT push_notification_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.rfid_tag_rolls (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  label_width_mm numeric NOT NULL,
  label_height_mm numeric NOT NULL,
  label_count integer NOT NULL CHECK (label_count > 0),
  status character varying NOT NULL DEFAULT 'writing'::character varying CHECK (status::text = ANY (ARRAY['writing'::character varying, 'ready_to_print'::character varying, 'printing'::character varying, 'completed'::character varying]::text[])),
  last_printed_position integer NOT NULL DEFAULT 0 CHECK (last_printed_position >= 0),
  manufacturer_url text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid,
  CONSTRAINT rfid_tag_rolls_pkey PRIMARY KEY (id),
  CONSTRAINT rfid_tag_rolls_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)
);
CREATE TABLE public.rfid_tags (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  epc_identifier character varying NOT NULL UNIQUE,
  tid character varying,
  status character varying NOT NULL DEFAULT 'generated'::character varying CHECK (status::text = ANY (ARRAY['generated'::character varying, 'written'::character varying, 'active'::character varying, 'retired'::character varying]::text[])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  written_at timestamp with time zone,
  locked_at timestamp with time zone,
  created_by uuid,
  library_album_id uuid,
  associated_at timestamp with time zone,
  associated_by uuid,
  last_seen_at timestamp with time zone,
  roll_id uuid,
  roll_position integer CHECK (roll_position IS NULL OR roll_position > 0),
  CONSTRAINT rfid_tags_pkey PRIMARY KEY (id),
  CONSTRAINT rfid_tags_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id),
  CONSTRAINT rfid_tags_associated_by_fkey FOREIGN KEY (associated_by) REFERENCES public.users(id),
  CONSTRAINT rfid_tags_library_album_id_fkey FOREIGN KEY (library_album_id) REFERENCES public.library_albums(id),
  CONSTRAINT rfid_tags_roll_id_fkey FOREIGN KEY (roll_id) REFERENCES public.rfid_tag_rolls(id)
);
CREATE TABLE public.step_files (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  step_id uuid NOT NULL,
  file_id uuid NOT NULL,
  execution_order integer NOT NULL CHECK (execution_order > 0),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT step_files_pkey PRIMARY KEY (id),
  CONSTRAINT step_files_step_id_fkey FOREIGN KEY (step_id) REFERENCES public.production_steps(id),
  CONSTRAINT step_files_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.files(id)
);
CREATE TABLE public.step_gcode_files (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  step_id uuid NOT NULL,
  gcode_file_id uuid NOT NULL,
  execution_order integer NOT NULL CHECK (execution_order > 0),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT step_gcode_files_pkey PRIMARY KEY (id),
  CONSTRAINT step_gcode_files_step_id_fkey FOREIGN KEY (step_id) REFERENCES public.production_steps(id),
  CONSTRAINT step_gcode_files_gcode_file_id_fkey FOREIGN KEY (gcode_file_id) REFERENCES public.gcode_files(id)
);
CREATE TABLE public.step_labels (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  step_id uuid NOT NULL,
  label_text text NOT NULL,
  label_order integer NOT NULL DEFAULT 1 CHECK (label_order > 0),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT step_labels_pkey PRIMARY KEY (id),
  CONSTRAINT step_labels_step_id_fkey FOREIGN KEY (step_id) REFERENCES public.production_steps(id)
);
CREATE TABLE public.step_timers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  step_id uuid NOT NULL,
  timer_name text NOT NULL,
  duration_minutes integer NOT NULL CHECK (duration_minutes > 0),
  timer_order integer NOT NULL DEFAULT 1 CHECK (timer_order > 0),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT step_timers_pkey PRIMARY KEY (id),
  CONSTRAINT step_timers_step_id_fkey FOREIGN KEY (step_id) REFERENCES public.production_steps(id)
);
CREATE TABLE public.thread_credentials (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  unit_id uuid NOT NULL UNIQUE,
  network_name character varying NOT NULL,
  pan_id integer NOT NULL CHECK (pan_id >= 0 AND pan_id <= 65534),
  channel integer NOT NULL CHECK (channel >= 11 AND channel <= 26),
  network_key character varying NOT NULL CHECK (length(network_key::text) = 32 AND network_key::text ~ '^[0-9a-fA-F]+$'::text),
  extended_pan_id character varying NOT NULL CHECK (length(extended_pan_id::text) = 16 AND extended_pan_id::text ~ '^[0-9a-fA-F]+$'::text),
  mesh_local_prefix character varying NOT NULL CHECK (length(mesh_local_prefix::text) = 16 AND mesh_local_prefix::text ~ '^[0-9a-fA-F]+$'::text),
  pskc character varying NOT NULL CHECK (length(pskc::text) = 32 AND pskc::text ~ '^[0-9a-fA-F]+$'::text),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT thread_credentials_pkey PRIMARY KEY (id),
  CONSTRAINT thread_credentials_units_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id)
);
CREATE TABLE public.unit_step_completions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  unit_id uuid NOT NULL,
  step_id uuid NOT NULL,
  completed_at timestamp with time zone DEFAULT now(),
  completed_by uuid NOT NULL,
  notes text,
  CONSTRAINT unit_step_completions_pkey PRIMARY KEY (id),
  CONSTRAINT unit_step_completions_step_id_fkey FOREIGN KEY (step_id) REFERENCES public.production_steps(id),
  CONSTRAINT unit_step_completions_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES public.users(id),
  CONSTRAINT unit_step_completions_units_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id)
);
CREATE TABLE public.unit_timers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  unit_id uuid NOT NULL,
  step_timer_id uuid NOT NULL,
  started_at timestamp with time zone NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  completed_at timestamp with time zone,
  status text NOT NULL DEFAULT 'active'::text CHECK (status = ANY (ARRAY['active'::text, 'completed'::text, 'cancelled'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT unit_timers_pkey PRIMARY KEY (id),
  CONSTRAINT unit_timers_step_timer_id_fkey FOREIGN KEY (step_timer_id) REFERENCES public.step_timers(id),
  CONSTRAINT unit_timers_units_fkey FOREIGN KEY (unit_id) REFERENCES public.units(id)
);
CREATE TABLE public.units (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  serial_number character varying UNIQUE,
  product_id uuid,
  variant_id uuid,
  order_id uuid,
  factory_provisioned_at timestamp with time zone,
  factory_provisioned_by uuid,
  consumer_user_id uuid,
  consumer_name character varying,
  status USER-DEFINED DEFAULT 'in_production'::unit_status,
  production_started_at timestamp with time zone,
  production_completed_at timestamp with time zone,
  is_completed boolean DEFAULT false,
  qr_code_url text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  CONSTRAINT units_pkey PRIMARY KEY (id),
  CONSTRAINT units_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT units_variant_id_fkey FOREIGN KEY (variant_id) REFERENCES public.product_variants(id),
  CONSTRAINT units_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT units_factory_provisioned_by_fkey FOREIGN KEY (factory_provisioned_by) REFERENCES public.users(id),
  CONSTRAINT units_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(id)
);
CREATE TABLE public.user_now_playing_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  source_event_id uuid NOT NULL,
  unit_id text NOT NULL,
  epc text NOT NULL,
  event_type text NOT NULL CHECK (event_type = ANY (ARRAY['placed'::text, 'removed'::text])),
  library_album_id uuid,
  album_title text,
  album_artist text,
  cover_image_url text,
  library_id uuid,
  library_name text,
  device_id uuid,
  device_name text,
  event_timestamp timestamp with time zone NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_now_playing_notifications_pkey PRIMARY KEY (id),
  CONSTRAINT user_now_playing_notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT user_now_playing_notifications_library_album_id_fkey FOREIGN KEY (library_album_id) REFERENCES public.library_albums(id),
  CONSTRAINT user_now_playing_notifications_library_id_fkey FOREIGN KEY (library_id) REFERENCES public.libraries(id),
  CONSTRAINT user_now_playing_notifications_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.consumer_devices(id)
);
CREATE TABLE public.user_permissions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  permission_id uuid NOT NULL,
  granted_at timestamp with time zone NOT NULL DEFAULT now(),
  granted_by uuid,
  CONSTRAINT user_permissions_pkey PRIMARY KEY (id),
  CONSTRAINT user_permissions_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT user_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id),
  CONSTRAINT user_permissions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.users(id)
);
CREATE TABLE public.users (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  google_id text UNIQUE,
  email text NOT NULL UNIQUE,
  full_name text,
  is_admin boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  last_login timestamp with time zone,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  avatar_url text,
  preferences jsonb DEFAULT '{}'::jsonb,
  auth_user_id uuid,
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id)
);