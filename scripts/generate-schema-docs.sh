#!/bin/bash
# Generate schema documentation from the live Supabase database using psql
#
# Usage:
#   From the repo root:     ./scripts/generate-schema-docs.sh
#   From a consuming project: ./shared-supabase/scripts/generate-schema-docs.sh --workdir shared-supabase
#
# Prerequisites:
#   - Supabase CLI installed and linked to the project
#   - psql installed (brew install libpq or brew install postgresql)
#
# How it works:
#   1. Extracts database credentials from `supabase db dump --dry-run`
#   2. Connects via psql to query pg_catalog
#   3. Generates schema/schema_dump.sql (reconstructed DDL)
#   4. Generates schema/SCHEMA.md (human-readable reference)
#
# No Docker or pg_dump required.

set -e

# ============================================================================
# Configuration: Table groupings, descriptions, and display order
# ============================================================================

SECTION_ORDER=(
  "Users & Authentication"
  "Products & Variants"
  "Device Types & Capabilities"
  "Units & Devices"
  "Production & Manufacturing"
  "Firmware"
  "Device Communication"
  "Orders & Customers"
  "RFID Tags"
  "Albums & Libraries"
  "Notifications"
  "Files & GCode"
  "Networking"
  "Deprecated Tables"
)

get_table_group() {
    case "$1" in
        users|permissions|user_permissions)
            echo "Users & Authentication" ;;
        products|product_variants|product_device_types)
            echo "Products & Variants" ;;
        device_types|capabilities|device_type_capabilities)
            echo "Device Types & Capabilities" ;;
        units|devices|consumer_devices)
            echo "Units & Devices" ;;
        production_steps|unit_step_completions|step_labels|step_timers|unit_timers|machine_macros)
            echo "Production & Manufacturing" ;;
        firmware|firmware_files)
            echo "Firmware" ;;
        device_commands|device_heartbeats|now_playing_events)
            echo "Device Communication" ;;
        orders|order_line_items|customers)
            echo "Orders & Customers" ;;
        rfid_tags|rfid_tag_rolls)
            echo "RFID Tags" ;;
        albums|libraries|library_albums|library_members|library_invitations|album_locations|listening_history)
            echo "Albums & Libraries" ;;
        push_notification_tokens|notification_preferences|notification_delivery_log|device_status_notifications|user_now_playing_notifications)
            echo "Notifications" ;;
        files|step_files|gcode_files|step_gcode_files)
            echo "Files & GCode" ;;
        thread_credentials)
            echo "Networking" ;;
        production_units|legacy_qr_code_lookup)
            echo "Deprecated Tables" ;;
        *)
            echo "" ;;
    esac
}

get_table_description() {
    case "$1" in
        users) echo 'Application-level user accounts (linked to Supabase Auth via `auth_user_id`).' ;;
        permissions) echo "Permission definitions for role-based access control." ;;
        user_permissions) echo "Join table linking users to permissions." ;;
        products) echo "Product definitions (synced from Shopify)." ;;
        product_variants) echo "Product variant options (synced from Shopify)." ;;
        product_device_types) echo "Maps products to the device types they contain." ;;
        device_types) echo 'Hardware device type templates (e.g., "Hub", "Satellite").' ;;
        capabilities) echo "Dynamic capability definitions with JSON schemas for provisioning and telemetry." ;;
        device_type_capabilities) echo "Maps device types to their capabilities with configuration." ;;
        units) echo "Unified table for manufactured product instances (factory + consumer lifecycle)." ;;
        devices) echo "Hardware instances (PCBs identified by MAC address)." ;;
        consumer_devices) echo "Consumer-facing device instances (registered by end users in the mobile app)." ;;
        production_steps) echo "Step definitions for product assembly workflows." ;;
        unit_step_completions) echo "Tracks which steps have been completed for each unit." ;;
        step_labels) echo "Labels associated with production steps." ;;
        step_timers) echo "Timer definitions for production steps (curing, drying, etc.)." ;;
        unit_timers) echo "Active timer instances for specific units." ;;
        machine_macros) echo "CNC and laser machine macro definitions." ;;
        firmware) echo "Firmware version records." ;;
        firmware_files) echo "Per-SoC firmware binary files (for multi-SoC devices)." ;;
        device_commands) echo "Command queue for device operations (provision, test, reboot, OTA, etc.)." ;;
        device_heartbeats) echo "Device telemetry and status updates." ;;
        now_playing_events) echo "Real-time record placement/removal events from RFID readers." ;;
        orders) echo "Shopify order records." ;;
        order_line_items) echo "Individual items within orders." ;;
        customers) echo "Shopify customer records." ;;
        rfid_tags) echo "Individual RFID tags with lifecycle tracking." ;;
        rfid_tag_rolls) echo "Batches of RFID tags on physical rolls." ;;
        albums) echo "Album metadata (from Discogs)." ;;
        libraries) echo "User-created album collections." ;;
        library_albums) echo "Albums within a library." ;;
        library_members) echo "Users with access to a library." ;;
        library_invitations) echo "Pending invitations to join a library." ;;
        album_locations) echo "Tracks which device an album is currently on." ;;
        listening_history) echo "User listening history (album plays)." ;;
        push_notification_tokens) echo "Mobile device push notification tokens." ;;
        notification_preferences) echo "Per-user notification settings." ;;
        notification_delivery_log) echo "Notification send/delivery tracking." ;;
        device_status_notifications) echo "Tracks recent device status notifications to prevent duplicates." ;;
        user_now_playing_notifications) echo "Pre-enriched now-playing notifications for mobile push." ;;
        files) echo "Production file library (PDFs, images, videos for production steps)." ;;
        step_files) echo "Links production files to production steps." ;;
        gcode_files) echo "GCode files for CNC/laser operations (sourced from GitHub)." ;;
        step_gcode_files) echo "Links GCode files to production steps." ;;
        thread_credentials) echo "Thread Border Router network credentials (one per unit)." ;;
        production_units) echo '**Deprecated** - replaced by `units` table. Kept for backward compatibility during transition.' ;;
        legacy_qr_code_lookup) echo "Maps old QR code UUIDs to new unit IDs during migration." ;;
        *) echo "" ;;
    esac
}

# Returns a sort key for ordering tables within their section
get_table_sort_order() {
    case "$1" in
        users) echo "01" ;; permissions) echo "02" ;; user_permissions) echo "03" ;;
        products) echo "01" ;; product_variants) echo "02" ;; product_device_types) echo "03" ;;
        device_types) echo "01" ;; capabilities) echo "02" ;; device_type_capabilities) echo "03" ;;
        units) echo "01" ;; devices) echo "02" ;; consumer_devices) echo "03" ;;
        production_steps) echo "01" ;; unit_step_completions) echo "02" ;; step_labels) echo "03" ;; step_timers) echo "04" ;; unit_timers) echo "05" ;; machine_macros) echo "06" ;;
        firmware) echo "01" ;; firmware_files) echo "02" ;;
        device_commands) echo "01" ;; device_heartbeats) echo "02" ;; now_playing_events) echo "03" ;;
        orders) echo "01" ;; order_line_items) echo "02" ;; customers) echo "03" ;;
        rfid_tags) echo "01" ;; rfid_tag_rolls) echo "02" ;;
        albums) echo "01" ;; libraries) echo "02" ;; library_albums) echo "03" ;; library_members) echo "04" ;; library_invitations) echo "05" ;; album_locations) echo "06" ;; listening_history) echo "07" ;;
        push_notification_tokens) echo "01" ;; notification_preferences) echo "02" ;; notification_delivery_log) echo "03" ;; device_status_notifications) echo "04" ;; user_now_playing_notifications) echo "05" ;;
        files) echo "01" ;; step_files) echo "02" ;; gcode_files) echo "03" ;; step_gcode_files) echo "04" ;;
        thread_credentials) echo "01" ;;
        production_units) echo "01" ;; legacy_qr_code_lookup) echo "02" ;;
        *) echo "99" ;;
    esac
}

# ============================================================================
# Script setup
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
WORKDIR=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --workdir) WORKDIR="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

SCHEMA_DIR="$REPO_ROOT/schema"
DUMP_FILE="$SCHEMA_DIR/schema_dump.sql"
SCHEMA_MD="$SCHEMA_DIR/SCHEMA.md"

mkdir -p "$SCHEMA_DIR"

SUPA_CMD="supabase"
if [ -n "$WORKDIR" ]; then
    SUPA_CMD="supabase --workdir $WORKDIR"
fi

if ! command -v psql &> /dev/null; then
    echo "Error: psql is not installed."
    echo "Install with: brew install libpq"
    exit 1
fi

# ============================================================================
# Step 1: Extract database connection from Supabase CLI
# ============================================================================

echo "Generating schema documentation..."
echo ""
echo "1. Extracting database credentials from Supabase CLI..."

DRY_RUN_OUTPUT=$($SUPA_CMD db dump --dry-run 2>&1) || {
    echo "Error: Failed to get credentials. Is the project linked?"
    echo "Run: supabase link --project-ref <your-project-ref>"
    exit 1
}

PGHOST=$(echo "$DRY_RUN_OUTPUT" | grep 'export PGHOST=' | sed 's/.*PGHOST="//' | sed 's/".*//')
PGPORT=$(echo "$DRY_RUN_OUTPUT" | grep 'export PGPORT=' | sed 's/.*PGPORT="//' | sed 's/".*//')
PGUSER=$(echo "$DRY_RUN_OUTPUT" | grep 'export PGUSER=' | sed 's/.*PGUSER="//' | sed 's/".*//')
PGPASSWORD=$(echo "$DRY_RUN_OUTPUT" | grep 'export PGPASSWORD=' | sed 's/.*PGPASSWORD="//' | sed 's/".*//')
PGDATABASE=$(echo "$DRY_RUN_OUTPUT" | grep 'export PGDATABASE=' | sed 's/.*PGDATABASE="//' | sed 's/".*//')

if [ -z "$PGHOST" ] || [ -z "$PGUSER" ] || [ -z "$PGPASSWORD" ]; then
    echo "Error: Could not extract database credentials from supabase db dump --dry-run"
    exit 1
fi

CONNSTR="postgresql://${PGUSER}:${PGPASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}?gssencmode=disable"

echo "   Connecting to ${PGHOST}..."
PG_VERSION=$(psql "$CONNSTR" -t -A -c "SELECT version();" 2>&1) || {
    echo "Error: Could not connect to database."
    echo "Output: $PG_VERSION"
    exit 1
}
echo "   Connected: $(echo "$PG_VERSION" | cut -d' ' -f1-2)"

# Helper functions
run_query() {
    psql "$CONNSTR" -t -A -F $'\t' -c "$1" 2>/dev/null
}

run_query_raw() {
    psql "$CONNSTR" -t -A -c "$1" 2>/dev/null
}

# ============================================================================
# Step 2: Generate schema_dump.sql
# ============================================================================

echo ""
echo "2. Generating schema_dump.sql..."

cat > "$DUMP_FILE" << 'HEADER'
-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.
-- Auto-generated by scripts/generate-schema-docs.sh
HEADER

# --- Enum types ---
ENUMS=$(run_query "
SELECT t.typname, string_agg(e.enumlabel, ',' ORDER BY e.enumsortorder)
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON t.typnamespace = n.oid
WHERE n.nspname = 'public'
GROUP BY t.typname
ORDER BY t.typname;
")

if [ -n "$ENUMS" ]; then
    echo "$ENUMS" | while IFS=$'\t' read -r typename labels; do
        [ -z "$typename" ] && continue
        formatted_labels=$(echo "$labels" | sed "s/,/', '/g")
        echo "CREATE TYPE public.${typename} AS ENUM ('${formatted_labels}');"
    done >> "$DUMP_FILE"
fi

# --- Tables ---
ALL_TABLES=$(run_query_raw "
SELECT c.relname
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname;
")
for TABLE in $ALL_TABLES; do
    echo "CREATE TABLE public.${TABLE} (" >> "$DUMP_FILE"

    COLUMNS=$(run_query "
    SELECT
        a.attname AS column_name,
        pg_catalog.format_type(a.atttypid, a.atttypmod) AS col_type,
        CASE WHEN a.attnotnull THEN 'NOT NULL' ELSE '~' END AS nullable,
        COALESCE(NULLIF(pg_get_expr(d.adbin, d.adrelid), ''), '~') AS col_default
    FROM pg_catalog.pg_attribute a
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = '${TABLE}'
      AND a.attnum > 0 AND NOT a.attisdropped
    ORDER BY a.attnum;
    ")

    echo "$COLUMNS" | while IFS=$'\t' read -r col_name col_type nullable col_default; do
        [ -z "$col_name" ] && continue
        [ "$nullable" = "~" ] && nullable=""
        [ "$col_default" = "~" ] && col_default=""
        LINE="  ${col_name} ${col_type}"
        [ -n "$nullable" ] && LINE="${LINE} ${nullable}"
        [ -n "$col_default" ] && LINE="${LINE} DEFAULT ${col_default}"
        echo "$LINE"
    done | awk 'NR>1{printf ",\n"}{printf "%s", $0}' >> "$DUMP_FILE"

    CONSTRAINTS=$(run_query "
    SELECT conname, pg_get_constraintdef(c.oid, true)
    FROM pg_constraint c
    JOIN pg_class r ON c.conrelid = r.oid
    JOIN pg_namespace n ON r.relnamespace = n.oid
    WHERE n.nspname = 'public' AND r.relname = '${TABLE}'
    ORDER BY CASE c.contype WHEN 'p' THEN 0 WHEN 'u' THEN 1 WHEN 'f' THEN 2 WHEN 'c' THEN 3 ELSE 4 END, conname;
    ")

    echo "$CONSTRAINTS" | while IFS=$'\t' read -r conname condef; do
        [ -z "$conname" ] && continue
        printf ",\n  CONSTRAINT %s %s" "$conname" "$condef"
    done >> "$DUMP_FILE"

    printf "\n);\n" >> "$DUMP_FILE"
done

# --- Indexes ---
INDEXES=$(run_query_raw "
SELECT indexdef FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname NOT IN (
    SELECT conname FROM pg_constraint
    JOIN pg_namespace ON pg_constraint.connamespace = pg_namespace.oid
    WHERE pg_namespace.nspname = 'public'
  )
ORDER BY tablename, indexname;
")

if [ -n "$INDEXES" ]; then
    echo "$INDEXES" | while IFS= read -r idx; do
        [ -n "$idx" ] && echo "${idx};"
    done >> "$DUMP_FILE"
fi

# --- Views ---
VIEW_NAMES=$(run_query_raw "
SELECT c.relname
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public' AND c.relkind = 'v'
ORDER BY c.relname;
")

if [ -n "$VIEW_NAMES" ]; then
    for VNAME in $VIEW_NAMES; do
        VDEF=$(run_query_raw "
        SELECT pg_get_viewdef(c.oid, true)
        FROM pg_class c
        JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relname = '${VNAME}';
        ")
        if [ -n "$VDEF" ]; then
            echo "CREATE OR REPLACE VIEW public.${VNAME} AS" >> "$DUMP_FILE"
            echo "${VDEF}" >> "$DUMP_FILE"
            echo "" >> "$DUMP_FILE"
        fi
    done
fi

# --- Functions ---
FUNC_NAMES=$(run_query_raw "
SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.prokind IN ('f', 'p') AND p.prokind != 'a'
ORDER BY p.proname;
")

if [ -n "$FUNC_NAMES" ]; then
    for FNAME in $FUNC_NAMES; do
        FDEF=$(run_query_raw "
        SELECT pg_get_functiondef(p.oid)
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = '${FNAME}'
        LIMIT 1;
        ")
        if [ -n "$FDEF" ]; then
            echo "$FDEF" >> "$DUMP_FILE"
            echo ";" >> "$DUMP_FILE"
            echo "" >> "$DUMP_FILE"
        fi
    done
fi

# --- Triggers ---
TRIGGER_DEFS=$(run_query_raw "
SELECT pg_get_triggerdef(t.oid, true)
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public' AND NOT t.tgisinternal
ORDER BY c.relname, t.tgname;
")

if [ -n "$TRIGGER_DEFS" ]; then
    echo "$TRIGGER_DEFS" | while IFS= read -r trig; do
        [ -n "$trig" ] && echo "${trig};"
    done >> "$DUMP_FILE"
fi

echo "   Saved to: $DUMP_FILE"

# ============================================================================
# Step 3: Generate SCHEMA.md
# ============================================================================

echo ""
echo "3. Generating SCHEMA.md..."

TODAY=$(date +%Y-%m-%d)

cat > "$SCHEMA_MD" << HEADER
# Saturday Vinyl Database Schema

> Generated from live Supabase database on ${TODAY}.
> Regenerate with: \`./scripts/generate-schema-docs.sh\`

## Table of Contents

HEADER

for section in "${SECTION_ORDER[@]}"; do
    anchor=$(echo "$section" | tr '[:upper:]' '[:lower:]' | sed 's/ & / /' | sed 's/ /-/g')
    echo "- [${section}](#${anchor})" >> "$SCHEMA_MD"
done
echo "" >> "$SCHEMA_MD"

# Get enum types for annotation
ENUM_TYPES=$(run_query_raw "
SELECT t.typname FROM pg_type t
JOIN pg_namespace n ON t.typnamespace = n.oid
WHERE n.nspname = 'public' AND t.typtype = 'e';
")

# Function to check if a type is an enum
is_enum_type() {
    local check_type="$1"
    echo "$ENUM_TYPES" | grep -qFx "$check_type"
}

# Function to generate markdown for a table
generate_table_md() {
    local TABLE="$1"
    local desc
    desc=$(get_table_description "$TABLE")

    # If no hardcoded description, try pg_description
    if [ -z "$desc" ]; then
        desc=$(run_query_raw "
        SELECT obj_description(c.oid, 'pg_class')
        FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relname = '${TABLE}';
        ")
    fi

    echo "### ${TABLE}" >> "$SCHEMA_MD"
    [ -n "$desc" ] && echo "$desc" >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"
    echo "| Column | Type | Nullable | Default | Notes |" >> "$SCHEMA_MD"
    echo "|--------|------|----------|---------|-------|" >> "$SCHEMA_MD"

    # Get all annotation data in one query (using pg_catalog only)
    local ANNOTATIONS
    ANNOTATIONS=$(run_query "
    WITH pk_cols AS (
        SELECT a.attname AS column_name
        FROM pg_constraint con
        JOIN pg_class rel ON con.conrelid = rel.oid
        JOIN pg_namespace nsp ON rel.relnamespace = nsp.oid
        JOIN pg_attribute a ON a.attrelid = rel.oid AND a.attnum = ANY(con.conkey)
        WHERE nsp.nspname = 'public' AND rel.relname = '${TABLE}' AND con.contype = 'p'
    ),
    unique_cols AS (
        SELECT a.attname AS column_name
        FROM pg_constraint con
        JOIN pg_class rel ON con.conrelid = rel.oid
        JOIN pg_namespace nsp ON rel.relnamespace = nsp.oid
        JOIN pg_attribute a ON a.attrelid = rel.oid AND a.attnum = ANY(con.conkey)
        WHERE nsp.nspname = 'public' AND rel.relname = '${TABLE}' AND con.contype = 'u'
    ),
    fk_cols AS (
        SELECT a.attname AS column_name,
               ref_cls.relname AS ref_table,
               ref_att.attname AS ref_col
        FROM pg_constraint con
        JOIN pg_class rel ON con.conrelid = rel.oid
        JOIN pg_namespace nsp ON rel.relnamespace = nsp.oid
        JOIN pg_attribute a ON a.attrelid = rel.oid AND a.attnum = ANY(con.conkey)
        JOIN pg_class ref_cls ON con.confrelid = ref_cls.oid
        JOIN pg_attribute ref_att ON ref_att.attrelid = ref_cls.oid AND ref_att.attnum = ANY(con.confkey)
        WHERE nsp.nspname = 'public' AND rel.relname = '${TABLE}' AND con.contype = 'f'
    ),
    check_cols AS (
        SELECT a.attname AS column_name, pg_get_constraintdef(con.oid, true) AS check_def
        FROM pg_constraint con
        JOIN pg_class rel ON con.conrelid = rel.oid
        JOIN pg_namespace nsp ON rel.relnamespace = nsp.oid
        JOIN pg_attribute a ON a.attrelid = rel.oid AND a.attnum = ANY(con.conkey)
        WHERE nsp.nspname = 'public' AND rel.relname = '${TABLE}' AND con.contype = 'c'
            AND array_length(con.conkey, 1) = 1
    ),
    col_info AS (
        SELECT
            a.attname AS column_name,
            pg_catalog.format_type(a.atttypid, a.atttypmod) AS col_type,
            CASE WHEN a.attnotnull THEN 'NOT NULL' ELSE '~' END AS nullable,
            COALESCE(NULLIF(pg_get_expr(d.adbin, d.adrelid), ''), '~') AS col_default,
            a.attnum AS ordinal_position
        FROM pg_catalog.pg_attribute a
        LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
        JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = '${TABLE}'
          AND a.attnum > 0 AND NOT a.attisdropped
    )
    SELECT
        ci.column_name,
        ci.col_type,
        ci.nullable,
        ci.col_default,
        COALESCE(
            (SELECT 'PK' FROM pk_cols pk WHERE pk.column_name = ci.column_name LIMIT 1),
            '~'
        ) AS is_pk,
        COALESCE(
            (SELECT 'UNIQUE' FROM unique_cols uq WHERE uq.column_name = ci.column_name LIMIT 1),
            '~'
        ) AS is_unique,
        COALESCE(
            (SELECT 'FK -> ' || fk.ref_table || '(' || fk.ref_col || ')'
             FROM fk_cols fk WHERE fk.column_name = ci.column_name LIMIT 1),
            '~'
        ) AS fk_ref,
        COALESCE(
            (SELECT ck.check_def FROM check_cols ck WHERE ck.column_name = ci.column_name LIMIT 1),
            '~'
        ) AS check_def
    FROM col_info ci
    ORDER BY ci.ordinal_position;
    ")

    echo "$ANNOTATIONS" | while IFS=$'\t' read -r col_name col_type nullable col_default is_pk is_unique fk_ref check_def; do
        [ -z "$col_name" ] && continue
        # Strip sentinel values
        [ "$nullable" = "~" ] && nullable=""
        [ "$col_default" = "~" ] && col_default=""
        [ "$is_pk" = "~" ] && is_pk=""
        [ "$is_unique" = "~" ] && is_unique=""
        [ "$fk_ref" = "~" ] && fk_ref=""
        [ "$check_def" = "~" ] && check_def=""

        # Clean up default
        local display_default
        display_default=$(echo "$col_default" | sed "s/::.*//g" | sed "s/'//g")

        # Build notes
        local notes=""
        [ -n "$is_pk" ] && notes="$is_pk"

        if [ -n "$is_unique" ]; then
            [ -n "$notes" ] && notes="${notes}, "
            notes="${notes}${is_unique}"
        fi

        if [ -n "$fk_ref" ]; then
            [ -n "$notes" ] && notes="${notes}, "
            notes="${notes}${fk_ref}"
        fi

        if [ -n "$check_def" ]; then
            local short_check
            short_check=$(echo "$check_def" | sed 's/^CHECK //' | sed 's/^(//' | sed 's/)$//')
            [ -n "$notes" ] && notes="${notes}, "
            notes="${notes}CHECK ${short_check}"
        fi

        # Check if type is an enum
        if is_enum_type "$col_type"; then
            [ -n "$notes" ] && notes="${notes}, "
            notes="${notes}Enum"
        fi

        echo "| ${col_name} | ${col_type} | ${nullable} | ${display_default} | ${notes} |"
    done >> "$SCHEMA_MD"

    echo "" >> "$SCHEMA_MD"
}

# Build sorted table lists per section
for section in "${SECTION_ORDER[@]}"; do
    echo "---" >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"
    echo "## ${section}" >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"

    # Collect tables for this section with sort keys
    SECTION_TABLE_LIST=""
    for TABLE in $ALL_TABLES; do
        group=$(get_table_group "$TABLE")
        if [ "$group" = "$section" ]; then
            order=$(get_table_sort_order "$TABLE")
            SECTION_TABLE_LIST="${SECTION_TABLE_LIST}${order}:${TABLE}\n"
        fi
    done

    # Sort and process
    if [ -n "$SECTION_TABLE_LIST" ]; then
        printf "%b" "$SECTION_TABLE_LIST" | sort | while IFS=: read -r _ TABLE; do
            [ -z "$TABLE" ] && continue
            echo "   Processing: ${TABLE}..."
            generate_table_md "$TABLE"
        done
    fi
done

# Tables not in any group
HAS_OTHER=false
for TABLE in $ALL_TABLES; do
    group=$(get_table_group "$TABLE")
    if [ -z "$group" ]; then
        if [ "$HAS_OTHER" = false ]; then
            echo "---" >> "$SCHEMA_MD"
            echo "" >> "$SCHEMA_MD"
            echo "## Other Tables" >> "$SCHEMA_MD"
            echo "" >> "$SCHEMA_MD"
            HAS_OTHER=true
        fi
        echo "   Processing: ${TABLE}..."
        generate_table_md "$TABLE"
    fi
done

# --- Views section ---
if [ -n "$VIEW_NAMES" ]; then
    echo "---" >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"
    echo "## Views" >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"

    for VNAME in $VIEW_NAMES; do
        VDEF=$(run_query_raw "
        SELECT pg_get_viewdef(c.oid, true)
        FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relname = '${VNAME}';
        ")
        echo "### ${VNAME}" >> "$SCHEMA_MD"
        echo "" >> "$SCHEMA_MD"
        echo '```sql' >> "$SCHEMA_MD"
        echo "$VDEF" >> "$SCHEMA_MD"
        echo '```' >> "$SCHEMA_MD"
        echo "" >> "$SCHEMA_MD"
    done
fi

# --- Functions section ---
if [ -n "$FUNC_NAMES" ]; then
    echo "---" >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"
    echo "## Functions" >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"

    for FNAME in $FUNC_NAMES; do
        FDEF=$(run_query_raw "
        SELECT pg_get_functiondef(p.oid)
        FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = '${FNAME}'
        LIMIT 1;
        ")
        if [ -n "$FDEF" ]; then
            echo "### ${FNAME}" >> "$SCHEMA_MD"
            echo "" >> "$SCHEMA_MD"
            echo '```sql' >> "$SCHEMA_MD"
            echo "$FDEF" >> "$SCHEMA_MD"
            echo '```' >> "$SCHEMA_MD"
            echo "" >> "$SCHEMA_MD"
        fi
    done
fi

# --- Triggers section ---
TRIGGER_INFO=$(run_query "
SELECT t.tgname, c.relname, pg_get_triggerdef(t.oid, true)
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public' AND NOT t.tgisinternal
ORDER BY c.relname, t.tgname;
")

if [ -n "$TRIGGER_INFO" ]; then
    echo "---" >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"
    echo "## Triggers" >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"
    echo '```sql' >> "$SCHEMA_MD"
    echo "$TRIGGER_INFO" | while IFS=$'\t' read -r tname trel tdef; do
        [ -z "$tname" ] && continue
        echo "${tdef};"
    done >> "$SCHEMA_MD"
    echo '```' >> "$SCHEMA_MD"
    echo "" >> "$SCHEMA_MD"
fi

echo "   Saved to: $SCHEMA_MD"

# ============================================================================
# Summary
# ============================================================================

TABLE_COUNT=$(echo "$ALL_TABLES" | grep -c . || true)

echo ""
echo "Done! Schema documentation generated."
echo ""
echo "Files:"
echo "  $DUMP_FILE    (reconstructed DDL, ${TABLE_COUNT} tables)"
echo "  $SCHEMA_MD    (human-readable reference)"
