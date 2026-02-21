# Audit: Firmware - Unit Heartbeat Refactor

**Date:** 2026-02-16
**Context:** The Supabase backend has been refactored to accept heartbeat telemetry as a single JSONB column (`telemetry`) instead of individual typed columns. The backend is backward compatible - existing firmware that sends individual columns continues to work. However, firmware should migrate to the new format for schema flexibility and to support new telemetry fields without backend migrations.

## What Changed

1. **`device_heartbeats` table has a new `telemetry` JSONB column** - stores the complete telemetry payload
2. **Individual typed columns still exist** during transition (`battery_level`, `wifi_rssi`, etc.) but will be removed once all firmware migrates
3. **The trigger reads from `telemetry` JSONB first**, falls back to individual columns
4. **Command result reporting** now uses the `telemetry` field (the old `heartbeat_data` column never existed - this was a bug that is now fixed)
5. **New telemetry fields** (e.g., `temperature_c`, `humidity_pct`) are supported without any backend migration - just include them in the `telemetry` JSONB

## Audit Checklist

Search the firmware codebase for each of the following patterns. For each match found, describe the file, line number, what it currently does, and what change is needed.

### 1. Heartbeat POST payload construction

Find where the firmware builds the JSON payload for heartbeat HTTP POST requests.

**Search patterns:**
- `device_heartbeats` (the REST endpoint URL)
- `/rest/v1/device_heartbeats`
- JSON construction for heartbeat data
- `battery_level`, `wifi_rssi`, `uptime_sec`, `free_heap`, `min_free_heap`, `largest_free_block` as top-level JSON keys
- `heartbeat_data` (old nested format - should not be in use)

**Current format (still works):**
```json
POST /rest/v1/device_heartbeats
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-HUB-00001",
  "device_type": "hub",
  "firmware_version": "1.2.0",
  "battery_level": 85,
  "wifi_rssi": -55,
  "uptime_sec": 3600,
  "free_heap": 245760,
  "min_free_heap": 200000,
  "largest_free_block": 180000
}
```

**New format (preferred):**
```json
POST /rest/v1/device_heartbeats
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-HUB-00001",
  "device_type": "hub",
  "firmware_version": "1.2.0",
  "telemetry": {
    "uptime_sec": 3600,
    "free_heap": 245760,
    "min_free_heap": 200000,
    "largest_free_block": 180000,
    "wifi_rssi": -55,
    "battery_level": 85,
    "battery_charging": false,
    "temperature_c": 22.5,
    "humidity_pct": 45.2
  }
}
```

**Required change:** Move all telemetry fields into a `telemetry` JSONB object. Keep routing fields (`mac_address`, `unit_id`, `device_type`, `firmware_version`) as top-level keys.

### 2. Command acknowledgement heartbeats

Find where the firmware sends `command_ack` and `command_result` heartbeats.

**Search patterns:**
- `command_ack`
- `command_result`
- `command_id` in the context of heartbeat POST
- `heartbeat_data` (old field name - never actually worked)

**Current format:**
```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-HUB-00001",
  "device_type": "hub",
  "type": "command_ack",
  "command_id": "550e8400-..."
}
```

**New format for command_result:**
```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-HUB-00001",
  "device_type": "hub",
  "firmware_version": "1.2.0",
  "type": "command_result",
  "command_id": "550e8400-...",
  "telemetry": {
    "status": "completed",
    "result": { "firmware_version": "1.3.0" },
    "error_message": null,
    "uptime_sec": 3605,
    "free_heap": 240000
  }
}
```

**Required change:** Command result data (`status`, `result`, `error_message`) should go in the `telemetry` JSONB field. The old `heartbeat_data` field was never functional on the backend (it referenced a nonexistent column). If firmware was using `heartbeat_data`, switch to `telemetry`. Regular telemetry can also be included in command result heartbeats.

### 3. REST PATCH to device_commands

Check if firmware is PATCHing `device_commands` directly in addition to sending command_ack/command_result heartbeats.

**Search patterns:**
- `/rest/v1/device_commands`
- `PATCH` combined with `device_commands`
- Direct status updates to the commands table

**Required change:** The heartbeat trigger now handles updating `device_commands.status` automatically when a `command_ack` or `command_result` heartbeat is received. Direct PATCH is still allowed but redundant. Firmware can simplify by only sending heartbeats for acknowledgement.

### 4. Heartbeat field naming

Verify all telemetry fields use the flat, capability-prefixed naming convention.

**Search patterns:**
- Nested JSON objects in heartbeat payloads (e.g., `"wifi": { "rssi": -55 }`)
- `uptime_ms` (should be `uptime_sec`)
- `rssi` without prefix (should be `wifi_rssi` or `thread_rssi`)
- `temperature` without suffix (should be `temperature_c`)
- `humidity` without suffix (should be `humidity_pct`)
- `charging` without prefix (should be `battery_charging`)

**Correct naming convention:**
| Field | Convention | Example |
|-------|-----------|---------|
| WiFi signal | `wifi_rssi` | `-55` (dBm) |
| WiFi connected | `wifi_connected` | `true` |
| Thread signal | `thread_rssi` | `-70` (dBm) |
| Battery SOC | `battery_level` | `85` (0-100) |
| Battery charging | `battery_charging` | `true` |
| Temperature | `temperature_c` | `22.5` (Celsius) |
| Humidity | `humidity_pct` | `45.2` (percentage) |
| Uptime | `uptime_sec` | `3600` (seconds) |
| Free heap | `free_heap` | `245760` (bytes) |
| Min free heap | `min_free_heap` | `200000` (bytes) |
| Largest block | `largest_free_block` | `180000` (bytes) |

**Required change:** Use flat keys with capability prefix and SI unit suffix. No nested objects.

### 5. New telemetry fields

Check if firmware collects any sensor data that isn't being reported in heartbeats.

**Search patterns:**
- Temperature sensor reads (e.g., `esp_temp_sensor`, I2C sensor drivers)
- Humidity sensor reads
- Battery ADC reads / fuel gauge reads
- Any sensor data that's collected but not included in heartbeats

**Required change:** With the `telemetry` JSONB format, new fields can be added without any backend migration. If firmware reads temperature, humidity, or other sensors, include them in the `telemetry` object using the naming convention above. The backend trigger will automatically propagate `temperature_c` and `humidity_pct` to the `units` table for consumer display.

### 6. Relay heartbeat fields

For devices that relay heartbeats on behalf of other devices (e.g., Hub relaying for Thread devices).

**Search patterns:**
- `relay_device_type`
- `relay_instance_id`
- Relay or forwarding logic for heartbeats

**Required change:** `relay_device_type` and `relay_instance_id` remain as top-level columns (not in `telemetry`). No change needed for relay fields.

## Migration Path

1. **Phase 1 (no firmware change):** Backend deployed. Existing heartbeat format continues to work. Backend trigger handles both formats.
2. **Phase 2 (firmware update):** Move telemetry fields from top-level to `telemetry` JSONB. Keep `mac_address`, `unit_id`, `device_type`, `firmware_version`, `type`, `command_id`, `relay_device_type`, `relay_instance_id` as top-level columns.
3. **Phase 3 (backend cleanup):** After all firmware is updated, backend drops the individual typed columns from `device_heartbeats`.

## Expected Outcome

After this audit, firmware should:
- Send heartbeat telemetry in the `telemetry` JSONB field
- Use flat, capability-prefixed field names (no nesting)
- Include `temperature_c` and `humidity_pct` if sensors are available
- Use `telemetry` for command result data instead of `heartbeat_data`
- Keep routing fields (`mac_address`, `unit_id`, `device_type`, `firmware_version`) as top-level keys
