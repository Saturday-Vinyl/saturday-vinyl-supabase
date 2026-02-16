#!/bin/bash
# Generate schema documentation from the live Supabase database
#
# Usage:
#   From the repo root:     ./scripts/generate-schema-docs.sh
#   From a consuming project: ./shared-supabase/scripts/generate-schema-docs.sh --workdir shared-supabase
#
# Prerequisites:
#   - Supabase CLI installed and linked to the project
#   - Database access credentials configured

set -e

# Determine the working directory
WORKDIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --workdir) WORKDIR="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Set output paths relative to the repo root
SCHEMA_DIR="$REPO_ROOT/schema"
DUMP_FILE="$SCHEMA_DIR/schema_dump.sql"
SCHEMA_MD="$SCHEMA_DIR/SCHEMA.md"

mkdir -p "$SCHEMA_DIR"

echo "Generating schema documentation..."
echo ""

# Build supabase command with optional workdir
SUPA_CMD="supabase"
if [ -n "$WORKDIR" ]; then
    SUPA_CMD="supabase --workdir $WORKDIR"
fi

# Dump the schema (DDL only, no data)
echo "1. Dumping schema from remote database..."
$SUPA_CMD db dump --schema public > "$DUMP_FILE" 2>/dev/null || {
    echo "Error: Failed to dump schema. Is the project linked?"
    echo "Run: supabase link --project-ref <your-project-ref>"
    exit 1
}

echo "   Saved to: $DUMP_FILE"

# Generate SCHEMA.md from the dump
echo "2. Generating SCHEMA.md..."

cat > "$SCHEMA_MD" << 'HEADER'
# Saturday Vinyl Database Schema

> Auto-generated from the live Supabase database. Do not edit manually.
> Regenerate with: `./scripts/generate-schema-docs.sh`

HEADER

# Extract and format tables
echo "## Tables" >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"

# Parse CREATE TABLE statements from the dump
awk '
/^CREATE TABLE/ {
    # Extract table name
    match($0, /CREATE TABLE[^.]*\.([^ (]+)/, arr)
    if (arr[1] != "") {
        table = arr[1]
        gsub(/"/, "", table)
        printf "### %s\n\n", table
        printf "```sql\n"
        print
        in_table = 1
        next
    }
}
in_table {
    print
    if (/\);/) {
        printf "```\n\n"
        in_table = 0
    }
}
' "$DUMP_FILE" >> "$SCHEMA_MD"

# Extract indexes
echo "## Indexes" >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"
echo '```sql' >> "$SCHEMA_MD"
grep -E "^CREATE (UNIQUE )?INDEX" "$DUMP_FILE" >> "$SCHEMA_MD" 2>/dev/null || echo "-- No custom indexes found" >> "$SCHEMA_MD"
echo '```' >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"

# Extract RLS policies
echo "## RLS Policies" >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"
echo '```sql' >> "$SCHEMA_MD"
grep -A2 "^CREATE POLICY" "$DUMP_FILE" >> "$SCHEMA_MD" 2>/dev/null || echo "-- No RLS policies found" >> "$SCHEMA_MD"
echo '```' >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"

# Extract custom types/enums
echo "## Custom Types" >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"
echo '```sql' >> "$SCHEMA_MD"
grep -A5 "^CREATE TYPE" "$DUMP_FILE" >> "$SCHEMA_MD" 2>/dev/null || echo "-- No custom types found" >> "$SCHEMA_MD"
echo '```' >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"

# Extract functions
echo "## Functions" >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"

awk '
/^CREATE.*FUNCTION/ {
    match($0, /FUNCTION[^.]*\.([^ (]+)/, arr)
    if (arr[1] != "") {
        func = arr[1]
        gsub(/"/, "", func)
        printf "### %s\n\n```sql\n", func
        print
        in_func = 1
        next
    }
}
in_func {
    print
    if (/^\$\$;/ || /^END;/ || /LANGUAGE [a-z]+;$/) {
        if (/LANGUAGE/) {
            printf "```\n\n"
            in_func = 0
        }
    }
}
' "$DUMP_FILE" >> "$SCHEMA_MD"

# Extract triggers
echo "## Triggers" >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"
echo '```sql' >> "$SCHEMA_MD"
grep -A2 "^CREATE TRIGGER" "$DUMP_FILE" >> "$SCHEMA_MD" 2>/dev/null || echo "-- No triggers found" >> "$SCHEMA_MD"
echo '```' >> "$SCHEMA_MD"
echo "" >> "$SCHEMA_MD"

echo "   Saved to: $SCHEMA_MD"
echo ""
echo "Done! Schema documentation generated."
echo ""
echo "Files:"
echo "  $DUMP_FILE    (raw SQL dump)"
echo "  $SCHEMA_MD    (human-readable reference)"
