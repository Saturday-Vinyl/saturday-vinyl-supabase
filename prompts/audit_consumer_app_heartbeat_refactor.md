# Audit: Consumer App - Unit Heartbeat Refactor

**Date:** 2026-02-16
**Context:** The Supabase backend has been refactored so that consumer-facing telemetry (battery level, online status, wifi signal, temperature, humidity) now lives as typed columns directly on the `units` table. Previously, this data was only available through `devices.latest_telemetry` (JSONB) which required joining through the `devices` table and parsing JSON.

## What Changed

1. **`units` table has new telemetry columns:** `last_seen_at`, `is_online`, `battery_level`, `is_charging`, `wifi_rssi`, `temperature_c`, `humidity_pct`, `firmware_version`
2. **These columns are auto-updated** by a database trigger on each device heartbeat
3. **`is_online`** is set `true` by the trigger, set `false` by a 1-minute cron job
4. **`units_dashboard` view has been dropped** - use `units` table directly
5. **`units_with_devices` view has been dropped** - use `units` table with `.select('*, devices(*)')` if device-level detail is needed

## Audit Checklist

Search the codebase for each of the following patterns. For each match found, describe the file, line number, what it currently does, and what change is needed.

### 1. Realtime subscriptions to `devices` table

Search for any Supabase Realtime subscription on the `devices` table. These should be replaced with subscriptions to the `units` table.

**Search patterns:**
- `table: 'devices'` or `table: "devices"`
- `.channel(` combined with `devices`
- `postgres_changes` combined with `devices`
- Any subscription filtering by `devices.last_seen_at` or `devices.latest_telemetry`

**Required change:** Replace with a subscription on the `units` table filtered by `consumer_user_id`:
```
supabase.channel('unit-updates')
  .on('postgres_changes', {
    event: 'UPDATE',
    schema: 'public',
    table: 'units',
    filter: 'consumer_user_id=eq.{userId}'
  }, callback)
  .subscribe()
```

### 2. Realtime subscriptions to `device_heartbeats` table

Search for any subscription to `device_heartbeats`. Consumer apps should never subscribe to this table directly.

**Search patterns:**
- `device_heartbeats`
- `heartbeats` in the context of realtime channels

**Required change:** Remove entirely. The `units` table subscription provides all consumer-facing telemetry.

### 3. Queries joining `devices` for telemetry

Search for any Supabase query that joins through `devices` to get telemetry data like battery level, online status, signal strength, etc.

**Search patterns:**
- `.from('units')` combined with `devices` in `.select()`
- `devices!inner` or `devices(` in select strings
- `latest_telemetry` in any query
- `devices.last_seen_at`

**Required change:** Read telemetry directly from the `units` row:
- `unit.battery_level` instead of `device.latest_telemetry.battery_level`
- `unit.is_online` instead of computing from `device.last_seen_at`
- `unit.wifi_rssi` instead of `device.latest_telemetry.wifi_rssi`
- `unit.temperature_c` instead of `device.latest_telemetry.temperature_c`
- `unit.humidity_pct` instead of `device.latest_telemetry.humidity_pct`
- `unit.is_charging` instead of `device.latest_telemetry.battery_charging`
- `unit.last_seen_at` instead of `device.last_seen_at`
- `unit.firmware_version` instead of `device.firmware_version`

### 4. References to `units_dashboard` or `units_with_devices` views

These views have been dropped.

**Search patterns:**
- `units_dashboard`
- `units_with_devices`

**Required change:** Replace with direct queries to `units` table. If device-level detail is needed (e.g., MAC address), use `.select('*, devices(*)')`.

### 5. Online/offline computation in app code

Search for any client-side logic that computes online/offline status from `last_seen_at` timestamps.

**Search patterns:**
- Time comparisons against `last_seen_at` (e.g., "5 minutes", "60 seconds", "300")
- `isOnline`, `is_online`, `isConnected`, `is_connected` computed properties
- Date arithmetic involving heartbeat timestamps

**Required change:** Use `unit.is_online` boolean directly. No client-side computation needed.

### 6. JSONB parsing of telemetry data

Search for any code that parses `latest_telemetry` or `heartbeat_data` JSONB objects.

**Search patterns:**
- `latest_telemetry`
- `heartbeat_data`
- JSON key access patterns for `battery_level`, `wifi_rssi`, `temperature`, `humidity`, `battery_charging`

**Required change:** Replace with typed column access. The `units` table now has these as first-class columns.

### 7. Data model / type definitions

Search for model classes or type definitions that represent units or devices with telemetry.

**Search patterns:**
- `class Unit`, `struct Unit`, `interface Unit`
- `class Device`, `struct Device`
- Model files in a `models/` or `entities/` directory
- Any type that has a `latestTelemetry` or `latest_telemetry` property

**Required change:** Add new telemetry properties to the Unit model:
- `lastSeenAt: DateTime?`
- `isOnline: Bool`
- `batteryLevel: Int?`
- `isCharging: Bool?`
- `wifiRssi: Int?`
- `temperatureC: Double?`
- `humidityPct: Double?`
- `firmwareVersion: String?`

## Expected Outcome

After this audit, the consumer app should:
- Have a single realtime subscription on `units` for all telemetry updates
- Never query `devices` or `device_heartbeats` directly
- Never parse JSONB for telemetry data
- Use `is_online` boolean directly instead of computing from timestamps
- Have updated type definitions with the new unit telemetry fields
