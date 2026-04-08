# Audit: Admin App - Flat Capability Commands Refactor

**Date:** 2026-02-20
**Context:** The hub firmware and all three protocol specs have been refactored to replace the `run_test` meta-command with flat capability commands. Instead of `{"cmd": "run_test", "capability": "wifi", "test_name": "connect"}`, the new format is simply `{"cmd": "connect"}`. The firmware already accepts both formats (flat preferred, `run_test` as deprecated alias). The `tests` concept has been renamed to `commands` in documentation, though the database column remains `tests` for now. See [Device Command Protocol v1.3.0](../protocols/device_command_protocol.md) and [Capability Schema v1.4.0](../schemas/capability_schema.md) for the full specification.

## What Changed

1. **Capability commands are now flat top-level `cmd` values** — `connect`, `scan`, `get_dataset`, `register`, etc. are dispatched the same as core commands like `reboot` or `get_status`
2. **`run_test` is deprecated** — firmware still accepts `{"cmd": "run_test", "capability": "...", "test_name": "..."}` but normalizes it internally to a flat command. New code should not use this format.
3. **`capability` and `test_name` fields removed from wire format** — the CBOR payload sent to mesh devices no longer includes these fields
4. **`tests` renamed to `commands` conceptually** — documentation uses `commands` throughout; DB column remains `tests` pending migration
5. **New `register` command added to thread capability** — hub-initiated command that tells a mesh node to re-register
6. **`test_not_found` error code replaced with `command_not_found`**
7. **Command categories introduced** — Tests (validate hardware), Queries (read state), Actions (trigger behavior)
8. **Command uniqueness is now the admin app's responsibility** — flat names have no namespace; the admin app must prevent collisions across capabilities on the same device type

## Audit Checklist

Search the codebase for each of the following patterns. For each match found, describe the file, line number, what it currently does, and what change is needed.

### 1. `run_test` command construction

The admin app currently builds command payloads with the `run_test` wrapper when sending capability commands to devices.

**Search patterns:**
- `run_test`
- `test_name`
- `"capability"` in the context of command payloads (not capability schema definitions)

**Current format:**
```json
{
  "id": "uuid",
  "cmd": "run_test",
  "capability": "wifi",
  "test_name": "connect",
  "params": {"ssid": "TestNetwork", "password": "pass123"}
}
```

**New format:**
```json
{
  "id": "uuid",
  "cmd": "connect",
  "params": {"ssid": "TestNetwork", "password": "pass123"}
}
```

**Required change:** When inserting into `device_commands`, use the command's `name` from the capability schema directly as the `cmd` value. Drop the `capability` and `test_name` fields entirely. The `params` field remains unchanged.

### 2. `tests` column reads and capability command display

The admin app reads the `capabilities.tests` JSONB column to display available commands for a device type.

**Search patterns:**
- `.tests` in model/query code
- `tests` as a database column name in queries
- `from('capabilities')` with `.select(` that includes `tests`
- Model properties like `tests`, `testList`, `capabilityTests`

**Current format (DB column):**
```json
[
  {"name": "connect", "display_name": "Connect to Wi-Fi", "parameters_schema": {...}, "result_schema": {...}},
  {"name": "scan", "display_name": "Scan Networks", ...}
]
```

**Required change:** The DB column is still named `tests` — no query changes needed yet. But the Dart model property names and UI labels should be renamed from "test" to "command" terminology. When the DB column is eventually renamed, a migration in `shared-supabase/` will handle the column rename.

### 3. Firmware JSON schema export

The admin app exports a firmware JSON schema file that developers download. The `tests` key in this export should be renamed to `commands`.

**Search patterns:**
- `"tests"` as a JSON key in schema generation/export code
- `tests` in firmware schema builder or serializer
- `toJson`, `toMap`, `serialize` methods on capability models that output `tests`

**Current export format:**
```json
{
  "capabilities": {
    "wifi": {
      "tests": {
        "connect": {"params": {...}, "result": {...}}
      }
    }
  }
}
```

**New export format:**
```json
{
  "capabilities": {
    "wifi": {
      "commands": {
        "connect": {"params": {...}, "result": {...}}
      }
    }
  }
}
```

**Required change:** In the firmware JSON schema export/download flow, change the key from `"tests"` to `"commands"`. This is the only place where the rename happens on the admin app side for now (the DB column stays as `tests`).

### 4. UI labels and terminology

All user-facing text should shift from "test" to "command" terminology.

**Search patterns:**
- `Run Test` / `RunTest` / `run_test` in UI strings
- `Test` as a button label or section header (in the context of capability commands)
- `test_name` / `testName` in UI code
- Localization strings containing "test" in the capability context

**Required change:** Rename as follows:
- "Run Test" → "Run Command" (or "Run" with category sub-label)
- "Tests" section → "Commands" section
- "Test Name" → "Command Name"
- Consider showing the command category (Test / Query / Action) as a badge or sub-label. Categories are informational; see [Capability Schema - Command Categories](../schemas/capability_schema.md#command-categories)

### 5. Command uniqueness validation (NEW)

This is a **new** responsibility. Previously, commands were namespaced by capability (`wifi.connect` vs `rfid.connect` were distinct). With flat commands, both would dispatch as `connect` — a collision the firmware can't resolve.

**Search patterns:**
- `device_type_capabilities` — the junction table where capabilities are linked to device types
- Code that adds/removes capabilities from a device type
- Capability editor or device type configuration screens

**Required change:** When a capability is linked to a device type (INSERT into `device_type_capabilities`), validate that none of the new capability's command names conflict with command names from capabilities already assigned to that device type. Display an error if a collision is detected (e.g., "Command name 'scan' already defined by capability 'rfid' on this device type").

**Implementation approach:**
```
1. Load all capabilities currently linked to this device type
2. Collect all command names from their `tests` arrays
3. Check the new capability's command names against the existing set
4. If any overlap, block the link and show which names conflict
```

### 6. `device_commands` INSERT payload

Verify how the admin app constructs the payload when inserting commands into the `device_commands` table.

**Search patterns:**
- `device_commands` in INSERT/upsert code
- `from('device_commands')` with `.insert(`
- Command payload builders or serializers
- `command` column in `device_commands` table writes

**Required change:** The INSERT payload should use flat `cmd` values. The `device_commands` table row should contain:
```json
{
  "device_id": "...",
  "command": "connect",
  "payload": {"ssid": "TestNetwork", "password": "pass123"}
}
```

Not:
```json
{
  "command": "run_test",
  "payload": {"capability": "wifi", "test_name": "connect", "ssid": "..."}
}
```

Verify the exact column names used in `device_commands` and adjust accordingly — the key point is that the command name should be the flat capability command name, not `run_test`.

### 7. Error code display

The firmware error code `test_not_found` has been replaced with `command_not_found`.

**Search patterns:**
- `test_not_found`
- `testNotFound`
- Error message strings containing "test not found"

**Required change:** Replace with `command_not_found` / `commandNotFound`. Update any error message display strings accordingly.

### 8. `register` command awareness

A new `register` command has been added to the `thread` capability. This is a hub-initiated command (the admin app doesn't send it directly — the hub sends it to mesh nodes). However, the admin app may display it in the commands list.

**Search patterns:**
- Code that filters or hides certain commands from the UI
- Command list rendering for the thread capability

**Required change:** The admin app should display `register` in the thread capability's command list but may want to mark it as "hub-initiated" or "automatic" since it's not typically triggered manually by an admin user. See [Capability Schema - thread commands](../schemas/capability_schema.md#thread) for the full definition.

## Expected Outcome

After this audit, the admin app should:
- Send flat capability commands (`{"cmd": "connect"}`) instead of `run_test` wrapper
- Display "Commands" instead of "Tests" in capability-related UI
- Export firmware JSON schema with `"commands"` key instead of `"tests"`
- Validate command name uniqueness when linking capabilities to device types
- Use `command_not_found` error code instead of `test_not_found`
- Continue reading `capabilities.tests` DB column (rename pending future migration)
- Show the new `register` command in thread capability's command list

## Reference Documents

- [Device Command Protocol v1.3.0](../protocols/device_command_protocol.md) — Flat capability commands, deprecated `run_test`
- [CoAP Mesh Protocol v1.1.0](../protocols/coap_mesh_protocol.md) — Simplified POST /cmd schema
- [Capability Schema v1.4.0](../schemas/capability_schema.md) — `tests`→`commands`, register command, command categories, process guide

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
