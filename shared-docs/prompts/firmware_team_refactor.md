# Firmware Team: Unified Device Architecture Migration

**Version:** 1.0.0
**Date:** 2026-01-24
**From:** Admin App Team
**To:** Firmware Team

---

## Executive Summary

We are migrating to a new unified device architecture that consolidates production units and consumer devices, introduces a dynamic capabilities model, and replaces the Service Mode entry-window pattern with always-listening devices.

**Key changes for firmware:**

1. **Remove entry window** - Devices should always listen for commands when connected
2. **Implement new command protocol** - Replace Service Mode commands with Device Command Protocol
3. **Add Supabase Realtime client** - Enable remote commands via WebSocket
4. **Use dynamic capabilities** - Device behavior driven by capability schemas from Admin App
5. **Multi-SoC firmware architecture** - Firmware versions now include files for each SoC

---

## Timeline

| Phase | Target | Deliverables |
|-------|--------|--------------|
| 1 | Week of 2026-01-27 | Remove entry window, implement always-listening |
| 2 | Week of 2026-02-03 | Implement Device Command Protocol over UART |
| 3 | Week of 2026-02-10 | Add Supabase Realtime client for remote commands |
| 4 | Week of 2026-02-17 | Integration testing with Admin App |

---

## Detailed Changes

### 1. Remove Service Mode Entry Window

**Current behavior:**
```
Power on → Has unit_id → Listen for enter_service_mode (10 seconds)
                                    ↓                    ↓
                             Command received      Timeout (no command)
                                    ↓                    ↓
                            Enter Service Mode     Continue to Standard Mode
```

**New behavior:**
```
Power on → Initialize command listener → Accept commands immediately
```

**Implementation:**
- Remove `SERVICE_MODE_ENTRY_TIMEOUT` constant
- Remove `service_mode_entry_task` and state machine
- Initialize UART command handler on boot (always active)
- Initialize Realtime WebSocket client after network connection

### 2. Device Command Protocol

Replace current Service Mode commands with new protocol.

**Reference:** `shared-docs/protocols/device_command_protocol.md`

**Command mapping:**

| Old Command | New Command | Notes |
|-------------|-------------|-------|
| `enter_service_mode` | *Removed* | Not needed |
| `exit_service_mode` | *Removed* | Not needed |
| `get_manifest` | `get_capabilities` | Returns capability manifest |
| `get_status` | `get_status` | Same, with capability-scoped data |
| `provision` | `factory_provision` | New field structure |
| `test_wifi` | `run_test` | `capability: "wifi", test_name: "connect"` |
| `test_cloud` | `run_test` | `capability: "cloud", test_name: "ping"` |
| `test_rfid` | `run_test` | `capability: "rfid", test_name: "scan"` |
| `test_all` | *Iterate run_test* | Admin App handles sequencing |
| `customer_reset` | `consumer_reset` | Renamed |
| `factory_reset` | `factory_reset` | Same |
| `reboot` | `reboot` | Same |

**New command format:**

```json
{
  "id": "uuid",
  "cmd": "run_test",
  "capability": "wifi",
  "test_name": "connect",
  "params": {
    "ssid": "TestNetwork",
    "password": "TestPass"
  }
}
```

**Response format:**

```json
{
  "id": "uuid",
  "status": "ok",
  "message": "Wi-Fi connected",
  "data": { ... }
}
```

### 3. Factory Provisioning Changes

**Old `provision` command:**
```json
{
  "cmd": "provision",
  "data": {
    "unit_id": "SV-HUB-000001",
    "cloud_url": "https://xxx.supabase.co",
    "cloud_anon_key": "eyJ..."
  }
}
```

**New `factory_provision` command:**
```json
{
  "id": "uuid",
  "cmd": "factory_provision",
  "params": {
    "serial_number": "SV-HUB-000001",
    "factory_attributes": {
      "cloud": {
        "cloud_url": "https://xxx.supabase.co",
        "cloud_anon_key": "eyJ..."
      },
      "wifi": {
        "ssid": "FactoryNetwork",
        "password": "factory123"
      }
    }
  }
}
```

**Key changes:**
- `unit_id` renamed to `serial_number`
- Attributes organized by capability
- Response includes `factory_provision_attributes` (e.g., generated Thread credentials)

### 4. Supabase Realtime Integration

Devices must connect to Supabase Realtime for remote commands.

**Reference implementation:** `saturday-player-hub/s3-master/components/cloud/realtime_client.c`

**Channel subscription:**
```
Channel: device:{mac_address}
Example: device:AA-BB-CC-DD-EE-01
```

**Protocol:** Phoenix over WebSocket

**Message handling:**
1. Connect to `wss://{cloud_url}/realtime/v1/websocket`
2. Send `phx_join` for channel `device:{mac}` (colons → dashes)
3. Receive `broadcast` events containing commands
4. Execute command
5. Report result via REST PATCH to `device_commands` table

**Heartbeat reporting:**
```json
POST /rest/v1/device_heartbeats
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-HUB-00001",
  "device_type": "hub",
  "firmware_version": "1.2.0",
  "telemetry": {
    "uptime_sec": 123456,
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

> **Note:** All telemetry goes in the `telemetry` JSONB field. Routing fields (`mac_address`, `unit_id`, `device_type`, `firmware_version`) remain as top-level columns. Field names use flat capability-prefixed naming (e.g., `wifi_rssi`, not `wifi.rssi`). See the [Device Command Protocol](../protocols/device_command_protocol.md) for the full heartbeat field specification.

**Frequency:** Every 30 seconds

### 5. Device Capabilities

Firmware must implement the `get_capabilities` command to return the device's capability manifest. See the [Device Command Protocol](../protocols/device_command_protocol.md) for the command format and response schema.

**Key fields returned:**
- `soc_types` - Array of SoC types on this PCB (e.g., `["esp32s3", "esp32h2"]`)
- `master_soc` - Which SoC has network connectivity
- `capabilities` - Full capability definitions with attribute schemas

### 6. Multi-SoC Firmware

For boards with multiple SoCs (e.g., Hub with S3 + H2, Crate with S3 + H2):

**Firmware structure:**
```
firmware/
├── esp32s3/
│   └── hub_master_v1.2.0.bin  (master - has WiFi, receives OTA)
└── esp32h2/
    └── hub_thread_v1.2.0.bin  (secondary - master pulls after update)
```

**OTA flow:**
1. Admin App triggers OTA with master firmware URL
2. Device downloads and flashes master SoC
3. Master SoC reboots
4. Master SoC pulls secondary firmware(s) from cloud
5. Master SoC flashes secondary SoC(s) via internal interface (UART/SPI)
6. Reports completion via heartbeat

---

## Database Tables

New tables you'll interact with:

### device_commands

```sql
CREATE TABLE device_commands (
  id UUID PRIMARY KEY,
  mac_address VARCHAR(17) NOT NULL,
  command TEXT NOT NULL,
  capability TEXT,
  test_name TEXT,
  parameters JSONB,
  status TEXT DEFAULT 'pending',  -- pending, sent, acknowledged, completed, failed
  result JSONB,
  error_message TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
);
```

**Your responsibilities:**
- Receive commands via Realtime broadcast
- Update `status` to `acknowledged` when starting execution
- Update `status` to `completed` or `failed` with `result` when done
- Use `id` field to track which command you're responding to

### device_heartbeats

```sql
CREATE TABLE device_heartbeats (
  id UUID PRIMARY KEY,
  mac_address VARCHAR(17) NOT NULL,
  unit_id TEXT,                    -- serial number (e.g., SV-HUB-00001)
  device_type TEXT NOT NULL,       -- device type slug (e.g., hub, crate)
  firmware_version TEXT,
  type TEXT DEFAULT 'status',      -- 'status', 'command_ack', 'command_result'
  command_id UUID,                 -- for command_ack/command_result types
  telemetry JSONB,                 -- all capability-specific telemetry
  created_at TIMESTAMPTZ
);
```

**Your responsibilities:**
- POST heartbeat every 30 seconds when connected to cloud
- Include all capability-specific data in the `telemetry` JSONB field
- Use flat field names with capability prefixes (e.g., `wifi_rssi`, `battery_level`)
- For command acknowledgements, set `type` to `command_ack` and include `command_id`
- For command results, set `type` to `command_result` with `status`, `result`, and `error_message` in `telemetry`

### devices

```sql
CREATE TABLE devices (
  id UUID PRIMARY KEY,
  mac_address VARCHAR(17) UNIQUE NOT NULL,
  device_type_id UUID,
  unit_id UUID,
  firmware_version VARCHAR(50),
  firmware_id UUID,
  factory_attributes JSONB,
  status VARCHAR(50),
  last_seen_at TIMESTAMPTZ
);
```

**Your responsibilities:**
- Device row is created by Admin App during provisioning
- Update `last_seen_at` on each heartbeat (Admin App can do this via trigger)

---

## Testing Requirements

### Unit Tests

1. Command parser correctly handles all command types
2. Capability schema validation works for factory/consumer attributes
3. Heartbeat generation includes correct data

### Integration Tests

1. UART command round-trip (send command, receive response)
2. Realtime subscription and command reception
3. Heartbeat delivery to cloud
4. OTA update flow including secondary SoC

### Admin App Integration Tests

We will provide test fixtures for:
- Sample commands in new format
- Expected responses
- Capability manifests for your device types

---

## Migration Checklist

- [ ] Remove entry window logic
- [ ] Implement always-listening command handler
- [ ] Update command parser for new format
- [ ] Implement `factory_provision` with capability-scoped attributes
- [ ] Implement `get_capabilities` returning manifest
- [ ] Implement `run_test` dispatcher
- [ ] Add Supabase Realtime client
- [ ] Implement heartbeat reporting
- [ ] Update OTA handler for multi-SoC
- [ ] Implement `get_capabilities` response with capability manifest
- [ ] Integration test with Admin App

---

## Questions & Support

**Contact:** Admin App Team
**Slack:** #saturday-admin-app
**Documentation:** `shared-docs/protocols/device_command_protocol.md`

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
