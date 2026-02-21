# Audit: Admin App - Unit Heartbeat Refactor

**Date:** 2026-02-16
**Context:** The Supabase backend has been refactored. Consumer-facing telemetry now lives as typed columns on the `units` table (auto-updated by heartbeat trigger). The `units_dashboard` and `units_with_devices` views have been dropped. Device-level telemetry (`devices.latest_telemetry`) is still maintained for admin/engineering use.

## What Changed

1. **`units` table has new columns:** `last_seen_at`, `is_online`, `battery_level`, `is_charging`, `wifi_rssi`, `temperature_c`, `humidity_pct`, `firmware_version`
2. **`units_dashboard` view dropped** - query `units` directly
3. **`units_with_devices` view dropped** - use `units` with `.select('*, devices(*)')`
4. **Heartbeat triggers consolidated** - `update_device_last_seen()` and `sync_heartbeat_to_device()` replaced by single `sync_heartbeat_to_device_and_unit()`
5. **`device_heartbeats` has new `telemetry` JSONB column** - stores complete payload (individual typed columns still exist during transition)
6. **`devices.latest_telemetry`** is still updated by the trigger (unchanged for admin use)

## Audit Checklist

Search the codebase for each of the following patterns. For each match found, describe the file, line number, what it currently does, and what change is needed.

### 1. References to `units_dashboard` view

This view has been dropped.

**Search patterns:**
- `units_dashboard`
- `from('units_dashboard')` or `from("units_dashboard")`

**Required change:** Replace with a direct query to `units`. The view's columns now live directly on the `units` table. For the primary device info that the view included (mac_address, device_type_slug), use a joined query:
```
supabase.from('units').select('*, devices(*)')
```
Or for just the primary device:
```
supabase.from('units').select(`
  *,
  devices (id, mac_address, device_type_slug, firmware_version, last_seen_at, latest_telemetry)
`)
```

### 2. References to `units_with_devices` view

This view has also been dropped.

**Search patterns:**
- `units_with_devices`
- `from('units_with_devices')` or `from("units_with_devices")`

**Required change:** Same as above - use `units` with a device join.

### 3. `is_connected` computed column

The old `units_dashboard` view had a computed `is_connected` column (`last_seen_at > NOW() - 5 min`). This is replaced by the stored `is_online` boolean on `units`.

**Search patterns:**
- `is_connected`
- `isConnected`

**Required change:** Replace with `is_online` / `isOnline`. This is now a stored boolean updated by trigger (true) and cron (false), not computed at query time.

### 4. Reading telemetry from `devices.latest_telemetry` for display

If the admin app reads `devices.latest_telemetry` to show consumer-facing metrics (battery, signal, temperature), it can now use the typed columns on `units` instead.

**Search patterns:**
- `latest_telemetry` used for display (battery indicators, signal bars, temperature readings)
- `latestTelemetry` in model/view code
- JSON key access for `battery_level`, `wifi_rssi`, `temperature_c`, `humidity_pct`, `battery_charging`

**Required change:** For consumer-facing metrics, use `units.battery_level`, `units.wifi_rssi`, etc. For engineering-level telemetry (heap stats, uptime, thread RSSI), continue using `devices.latest_telemetry` JSONB.

### 5. Online/offline status logic

Search for any code computing online/offline from `devices.last_seen_at` or `devices.status`.

**Search patterns:**
- Time comparisons with `last_seen_at` (e.g., "5 minutes", "300 seconds")
- `device.status == 'offline'` or `device.status == 'online'`
- `devices.status` in queries (`.eq('status', 'offline')`)

**Required change:** Use `units.is_online` for the consumer-facing online/offline state. `devices.status` still tracks provisioning state ('unprovisioned', 'provisioned') and can be used for admin purposes, but online/offline is now on `units.is_online`.

### 6. Factory provisioning flows

Factory provisioning should NOT be affected by this refactor, but verify nothing references dropped views or changed columns.

**Search patterns:**
- `factory_provision` in the context of database writes
- INSERT/UPDATE to `units` or `devices` during provisioning
- Any code that sets `devices.status` to 'online' or 'offline' (the trigger now handles this)

**Required change:** Should be minimal. Verify that provisioning code does not set telemetry columns on `units` (the trigger handles that). Provisioning should continue to write to `units` (serial_number, product_id, etc.) and `devices` (mac_address, unit_id, provision_data, etc.) as before.

### 7. Realtime subscriptions

Check what tables the admin app subscribes to for realtime updates.

**Search patterns:**
- `postgres_changes` combined with table names
- `.channel(` and `.subscribe()`
- Subscriptions on `devices` table for connectivity/telemetry

**Required change:** For unit-level telemetry (battery, online, signal), subscribe to `units` table changes. For device-level engineering data, `devices` subscription is still valid. The admin app may want both:
```
// Unit-level telemetry (battery, online status, etc.)
supabase.channel('units').on('postgres_changes', {
  event: 'UPDATE', schema: 'public', table: 'units'
}, handleUnitUpdate)

// Device-level engineering data (if still needed)
supabase.channel('devices').on('postgres_changes', {
  event: 'UPDATE', schema: 'public', table: 'devices'
}, handleDeviceUpdate)
```

### 8. Data model / type definitions

**Search patterns:**
- `class Unit`, `struct Unit`, model definitions
- Properties like `isConnected`, `primaryDeviceId`, `primaryDeviceMac`
- Any type that mirrors the `units_dashboard` view schema

**Required change:** Add telemetry properties to the Unit model. Remove any `isConnected` computed property (replaced by `isOnline` stored field). Remove view-specific properties if they existed.

## Expected Outcome

After this audit, the admin app should:
- Have no references to `units_dashboard` or `units_with_devices` views
- Use `units.is_online` instead of computing connectivity from timestamps
- Use typed unit columns for consumer-facing telemetry display
- Continue using `devices.latest_telemetry` for engineering-level metrics (heap, uptime, etc.)
- Have updated type definitions
