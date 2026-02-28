# Audit: Command Ack/Result Heartbeat — `telemetry` Format Compliance

**Date:** 2026-02-22
**Context:** The Device Command Protocol documentation (v1.2.4–v1.3.0) incorrectly documented command result heartbeats using a `heartbeat_data` field. The actual implementation — in both the Hub firmware (`realtime_client.c:send_command_result_heartbeat()`) and the database trigger (`update_command_on_ack()`) — uses the `telemetry` JSONB column on `device_heartbeats`. The protocol doc has been corrected in v1.3.1. This audit ensures all Saturday firmware and application projects comply with the correct format.

## Correct Format

### Top-level columns (on `device_heartbeats` table)

These fields are stored as **typed columns**, not inside `telemetry`:

| Column | Type | Description |
|--------|------|-------------|
| `mac_address` | VARCHAR(17) | Device MAC address |
| `unit_id` | TEXT | Device serial number (e.g., "SV-CRT-000001") |
| `device_type` | TEXT | Device type slug (e.g., "crate", "hub") |
| `firmware_version` | TEXT | Firmware version string |
| `type` | TEXT | `"command_ack"` or `"command_result"` |
| `command_id` | UUID | The command's `id` from `device_commands` |

### `telemetry` JSONB column

For `command_result` heartbeats, the `telemetry` column contains **both** command result fields and standard telemetry metrics:

```json
{
  "status": "completed",
  "result": {
    "device_type": "crate",
    "firmware_version": "1.2.0",
    "mac_address": "AA:BB:CC:DD:EE:FF"
  },
  "uptime_sec": 123460,
  "free_heap": 245760,
  "min_free_heap": 180224,
  "largest_free_block": 114688,
  "battery_level": 85
}
```

For failed commands:

```json
{
  "status": "failed",
  "error_message": "WiFi connection timed out",
  "uptime_sec": 123460,
  "free_heap": 245760
}
```

For `command_ack` heartbeats, `telemetry` contains only standard telemetry metrics (no `status`/`result`/`error_message`).

### Database trigger expectations

The `update_command_on_ack()` trigger reads:
- `NEW.type` — to distinguish `command_ack` vs `command_result`
- `NEW.command_id` — to find the matching row in `device_commands`
- `NEW.telemetry->>'status'` — to determine `completed` or `failed`
- `NEW.telemetry->'result'` — stored as `device_commands.result` JSONB
- `NEW.telemetry->>'error_message'` — stored as `device_commands.error_message`

## Audit Checklist

Search the codebase for each of the following patterns. For each match found, describe the file, line number, what it currently does, and what change is needed (if any).

### 1. Flag any use of `heartbeat_data` as a field name

The `heartbeat_data` field name was documented in protocol versions 1.2.4–1.3.0 but was never implemented. No column with this name exists on `device_heartbeats`.

**Search patterns:**
- `heartbeat_data` as a JSON key, CBOR key, or variable name
- Any code building a heartbeat object with a `heartbeat_data` sub-object

**Required change:** Replace `heartbeat_data` with `telemetry`. Move the `status`, `result`, and `error_message` fields inside the `telemetry` object.

### 2. Verify `command_id` is a top-level column

The `command_id` must be sent as a top-level field in the heartbeat POST, not nested inside `telemetry`.

**Search patterns:**
- `command_id` in heartbeat construction code
- Check whether it's added to the root object or to a nested telemetry/data object

**Correct:**
```json
{
  "command_id": "550e8400-...",
  "telemetry": { "status": "completed", ... }
}
```

**Incorrect:**
```json
{
  "telemetry": { "command_id": "550e8400-...", "status": "completed", ... }
}
```

**Required change:** If `command_id` is nested inside `telemetry` or `heartbeat_data`, move it to the top level.

### 3. Verify `type` is a top-level column

The heartbeat `type` field (`"command_ack"` or `"command_result"`) must be a top-level field.

**Search patterns:**
- `command_ack` and `command_result` as string literals
- `type` field in heartbeat construction

**Required change:** Ensure `type` is set as a top-level field, not nested inside telemetry.

### 4. Verify command result data uses `telemetry` structure

For `command_result` heartbeats, the result payload must use the `telemetry` JSONB structure:

| Key | Location | Type | Description |
|-----|----------|------|-------------|
| `status` | `telemetry.status` | string | `"completed"` or `"failed"` |
| `result` | `telemetry.result` | object | Command result data (success only) |
| `error_message` | `telemetry.error_message` | string | Error description (failure only) |

**Search patterns:**
- Code that builds result payloads after command execution
- `"completed"` or `"failed"` string literals near heartbeat construction
- `error_message` in heartbeat/result objects

**Required change:** Ensure `status`, `result`, and `error_message` are inside the `telemetry` object, not at the top level or inside a `heartbeat_data` object.

### 5. Verify standard telemetry metrics are included in result heartbeats

The `telemetry` object should contain standard metrics alongside result fields. This is optional but recommended — it gives the cloud a telemetry snapshot at command completion time.

**Search patterns:**
- Heartbeat telemetry construction for `command_result` type
- Whether `uptime_sec`, `free_heap`, `battery_level`, etc. are included

**Recommended:** Include at minimum `uptime_sec` and `free_heap` in all heartbeats, including `command_ack` and `command_result` types.

## Target Projects

### Crate Firmware (Thread/CoAP)

The Crate sends CBOR heartbeats via `POST /heartbeat` to the Hub, which relays them to the cloud. The CBOR heartbeat format uses `cmd_id` (not `command_id`) and a nested `result` map. The Hub's CBOR decoder (`event_reporter.c:event_reporter_queue_crate_telemetry()`) translates:
- CBOR `cmd_id` → JSON `command_id` (top-level column)
- CBOR `result.status` → JSON `telemetry.status`
- CBOR `result.error` → JSON `telemetry.error_message`
- CBOR `result.data` → JSON `telemetry.result`

**Verify:** The Crate's CBOR heartbeat builder includes `cmd_id` (tstr) and `result` (map with `status`, `error`, `data` sub-keys) when sending `command_ack`/`command_result` heartbeats.

### Admin App (Flutter)

The Admin App may construct command result heartbeats during factory provisioning when relaying results from UART-connected devices.

**Search patterns:**
- `device_heartbeats` table inserts
- `command_ack` or `command_result` in Dart code
- `heartbeat_data` in any model or API call

### Consumer App (Flutter)

The Consumer App may relay command results during BLE provisioning.

**Search patterns:**
- Same as Admin App above
- BLE-to-cloud relay code that constructs heartbeats

## Reference Documents

- [Device Command Protocol v1.3.1](../protocols/device_command_protocol.md) — Corrected Command Acknowledgement Protocol section
- [CoAP Mesh Protocol](../protocols/coap_mesh_protocol.md) — CBOR heartbeat format for mesh devices
- Database trigger: `shared-supabase/supabase/migrations/20260216172300_shared_rewrite_heartbeat_triggers.sql` — `update_command_on_ack()` function

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
