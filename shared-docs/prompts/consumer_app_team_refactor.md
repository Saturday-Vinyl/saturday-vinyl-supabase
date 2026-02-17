# Consumer App Team: Unified Device Architecture Migration

**Version:** 1.0.0
**Date:** 2026-01-24
**From:** Admin App Team
**To:** Consumer App Team

---

## Executive Summary

We are migrating to a unified device architecture that consolidates production units and consumer devices into a single `units` table. This change simplifies the data model and provides a single source of truth for device information across factory and consumer contexts.

**Key changes for consumer app:**

1. **Use `units` table** instead of creating separate `consumer_devices` entries
2. **Write to `units` table** for consumer provisioning data
3. **Reference `devices` table** for hardware instances (MAC addresses, firmware)
4. **Update heartbeat reporting** to use new `device_heartbeats` table
5. **BLE provisioning updates** for new attribute schemas

---

## Timeline

| Phase | Target | Deliverables |
|-------|--------|--------------|
| 1 | Week of 2026-02-03 | Update data models to new schema |
| 2 | Week of 2026-02-10 | Update BLE provisioning flow |
| 3 | Week of 2026-02-17 | Integration testing |

---

## Database Schema Changes

### Old Model

```
consumer_devices (created by consumer app)
├── id
├── serial_number
├── user_id
├── device_name
├── firmware_version
├── last_seen_at
└── ...
```

### New Model

```
units (created during factory provisioning)
├── id
├── serial_number
├── product_id, variant_id
├── user_id (updated by consumer app)
├── consumer_provisioned_at (updated by consumer app)
├── device_name (updated by consumer app)
├── consumer_attributes (updated by consumer app)
└── status

devices (hardware instances, linked to units)
├── id
├── mac_address
├── device_type_id
├── unit_id → units.id
├── firmware_version
├── last_seen_at
└── factory_attributes
```

---

## Detailed Changes

### 1. Device Registration

**Old flow:**
1. User scans QR code on device
2. App extracts serial number
3. App creates new row in `consumer_devices`
4. App writes user_id to link device to account

**New flow:**
1. User scans QR code on device
2. App extracts serial number
3. App queries `units` table by serial_number
4. Unit already exists (created during factory provisioning)
5. App updates `units` row with consumer data:
   - `user_id` = current user's ID
   - `consumer_provisioned_at` = now
   - `device_name` = user-provided name
   - `consumer_attributes` = BLE provisioning data
   - `status` = 'user_provisioned'

**API call:**
```sql
UPDATE units
SET
  user_id = :user_id,
  consumer_provisioned_at = NOW(),
  device_name = :device_name,
  consumer_attributes = :consumer_attributes,
  status = 'user_provisioned'
WHERE serial_number = :serial_number
RETURNING *;
```

### 2. Consumer Attributes

Consumer attributes are now organized by capability, matching the firmware schema.

**Old format:**
```json
{
  "wifi_ssid": "HomeNetwork",
  "wifi_password": "...",
  "custom_name": "Living Room Hub"
}
```

**New format:**
```json
{
  "wifi": {
    "ssid": "HomeNetwork",
    "password": "..."
  },
  "thread": {
    "network_name": "SaturdayVinyl",
    "network_key": "..."
  }
}
```

### 3. BLE Provisioning Updates

**Device Info characteristic (0x0001)** now returns:

```json
{
  "device_type": "hub",
  "serial_number": "SV-HUB-000123",  // Was "unit_id"
  "firmware_version": "1.2.0",
  "protocol_version": "1.0",
  "capabilities": ["wifi", "thread_br", "rfid"],
  "needs_provisioning": true,
  "has_wifi": false,
  "has_thread": false
}
```

**Key change:** `unit_id` field renamed to `serial_number`

### 4. Device Status & Firmware

Device hardware information (MAC address, firmware version, online status) now lives in the `devices` table, not `units`.

**Querying device info:**
```sql
SELECT
  u.serial_number,
  u.device_name,
  u.consumer_provisioned_at,
  d.mac_address,
  d.firmware_version,
  d.last_seen_at,
  d.status as device_status
FROM units u
JOIN devices d ON d.unit_id = u.id
WHERE u.user_id = :current_user_id;
```

**Online/offline status:**
- `units.is_online` is a boolean column updated automatically
- Set to `true` by a database trigger on each heartbeat
- Set to `false` by a cron job when `last_seen_at` exceeds 10 minutes

### 5. Unit Telemetry

Consumer-facing telemetry lives directly on the `units` table as typed columns. These are updated automatically by a database trigger when device heartbeats arrive. You never need to query `device_heartbeats` or `devices` directly.

**Available telemetry columns on `units`:**

| Column | Type | Description |
|--------|------|-------------|
| `last_seen_at` | TIMESTAMPTZ | Most recent heartbeat from any device |
| `is_online` | BOOLEAN | Whether any device has heartbeated within threshold |
| `battery_level` | INTEGER | Battery SOC 0-100 (NULL if no battery) |
| `is_charging` | BOOLEAN | Whether connected to power (NULL if no battery) |
| `wifi_rssi` | INTEGER | WiFi signal strength in dBm |
| `temperature_c` | NUMERIC | Ambient temperature in Celsius |
| `humidity_pct` | NUMERIC | Relative humidity percentage |
| `firmware_version` | TEXT | Primary device firmware version |

### 6. Real-time Subscriptions

Subscribe to the `units` table for all telemetry and status updates. This is the only subscription consumer apps need:

```javascript
supabase
  .channel('unit-updates')
  .on(
    'postgres_changes',
    {
      event: 'UPDATE',
      schema: 'public',
      table: 'units',
      filter: `consumer_user_id=eq.${currentUserId}`
    },
    (payload) => {
      const unit = payload.new
      // All telemetry is directly on the unit row:
      // unit.is_online, unit.battery_level, unit.is_charging,
      // unit.wifi_rssi, unit.temperature_c, unit.humidity_pct,
      // unit.last_seen_at, unit.firmware_version
      handleUnitUpdate(unit)
    }
  )
  .subscribe()
```

> **Note:** Do NOT subscribe to `devices` or `device_heartbeats` in the consumer app. The `units` table has everything you need.

---

## Data Model Reference

### units Table

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `serial_number` | VARCHAR | Unit serial number (e.g., SV-HUB-000001) |
| `product_id` | UUID | Link to products table |
| `variant_id` | UUID | Link to product_variants table |
| `consumer_user_id` | UUID | **Consumer app writes this** (via claim-unit) |
| `consumer_provisioned_at` | TIMESTAMPTZ | **Set by claim-unit edge function** |
| `consumer_name` | VARCHAR | **Consumer app writes this** |
| `status` | unit_status enum | in_production → factory_provisioned → claimed |
| `last_seen_at` | TIMESTAMPTZ | Most recent heartbeat (auto-updated by trigger) |
| `is_online` | BOOLEAN | Online status (auto-updated by trigger + cron) |
| `battery_level` | INTEGER | Battery 0-100 (auto-updated by trigger) |
| `is_charging` | BOOLEAN | Charging state (auto-updated by trigger) |
| `wifi_rssi` | INTEGER | WiFi signal dBm (auto-updated by trigger) |
| `temperature_c` | NUMERIC | Temperature Celsius (auto-updated by trigger) |
| `humidity_pct` | NUMERIC | Humidity percentage (auto-updated by trigger) |
| `firmware_version` | TEXT | Primary device firmware (auto-updated by trigger) |

---

## Row Level Security (RLS)

### units Table

Users can only read/update units they own:

```sql
-- Read policy
CREATE POLICY "Users can view own units"
ON units FOR SELECT
USING (user_id = auth.uid());

-- Update policy
CREATE POLICY "Users can update own units"
ON units FOR UPDATE
USING (user_id = auth.uid());
```

**Registration flow:**
- Initial registration requires a service role or anon key that can update unclaimed units
- Consider using a Supabase Edge Function for registration:

```typescript
// Edge Function: register-device
const { serial_number, device_name, consumer_attributes } = request.body;

// Verify unit exists and is unclaimed
const { data: unit } = await supabase
  .from('units')
  .select('*')
  .eq('serial_number', serial_number)
  .is('user_id', null)
  .single();

if (!unit) throw new Error('Device not found or already claimed');

// Claim the device
await supabase
  .from('units')
  .update({
    user_id: auth.uid(),
    consumer_provisioned_at: new Date().toISOString(),
    device_name,
    consumer_attributes,
    status: 'user_provisioned'
  })
  .eq('id', unit.id);
```

---

## Migration Checklist

### Data Models
- [ ] Update `Device` model to use new schema
- [ ] Add `Unit` model if not already present
- [ ] Update foreign key relationships

### API Calls
- [ ] Change device registration to UPDATE units instead of INSERT consumer_devices
- [ ] Update device listing queries to JOIN units and devices
- [ ] Update heartbeat queries to use device_heartbeats table

### BLE Provisioning
- [ ] Update Device Info parsing for `serial_number` field
- [ ] Update consumer attribute format to capability-scoped structure

### UI Updates
- [ ] Device status now comes from `devices.last_seen_at`
- [ ] Firmware version comes from `devices.firmware_version`
- [ ] Product info comes from `units.product_id` JOIN

### Real-time
- [ ] Update subscriptions to watch new tables

---

## Backwards Compatibility

During migration, both tables may exist:

1. **Phase 1:** Consumer app reads from `consumer_devices` (if exists) OR `units`
2. **Phase 2:** Data migration copies consumer_devices → units
3. **Phase 3:** Consumer app writes only to `units`
4. **Phase 4:** Remove `consumer_devices` table

---

## Questions & Support

**Contact:** Admin App Team
**Slack:** #saturday-admin-app

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
