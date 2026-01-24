# Saturday Device Command Protocol

**Version:** 1.0.0
**Last Updated:** 2026-01-24
**Audience:** Saturday Admin App developers, Firmware engineers, Consumer App developers

---

## Overview

This document defines the **Device Command Protocol** for Saturday devices. This protocol provides a unified interface for sending commands to devices and receiving status updates, replacing the legacy Service Mode Protocol's entry-window architecture with an always-listening model.

### Key Concepts

- **Always-Listening**: Devices continuously listen for commands when connected (no entry window required)
- **MAC Address Identification**: Devices are identified by their MAC address (primary SoC)
- **Unified Commands**: Same command set works across UART (factory) and Supabase Realtime (remote)
- **Capability-Driven**: Commands are scoped to device capabilities defined in the admin app

### Design Principles

1. **Device-Agnostic**: Protocol applies to all Saturday hardware (Hub, Crate, Speaker, etc.)
2. **Transport-Agnostic**: Same commands work over UART and Supabase Realtime
3. **Always Available**: No timed entry windows - devices accept commands when connected
4. **Capability-Scoped**: Commands reference capabilities with user-definable schemas
5. **Idempotent**: Commands can be safely retried without side effects

---

## Transport Layers

### UART (Factory/Local Provisioning)

For factory provisioning and local diagnostics via USB serial connection.

| Parameter | Value |
|-----------|-------|
| Interface | USB Serial (CDC ACM) |
| Baud Rate | 115200 |
| Data Bits | 8 |
| Parity | None |
| Stop Bits | 1 |
| Flow Control | None |

### Supabase Realtime (Remote Commands)

For remote device management via cloud WebSocket.

**Channel Subscription:**
- Device subscribes to: `device:{mac_address}` (colons replaced with dashes)
- Example: `device:AA-BB-CC-DD-EE-01` for MAC `AA:BB:CC:DD:EE:01`
- Uses Phoenix protocol over WebSocket

**Command Flow:**
```
1. Admin App → INSERT into device_commands table
2. Database Trigger → pg_notify to Supabase Realtime
3. Supabase Realtime → Broadcast to device:{mac_address} channel
4. Device receives command via WebSocket
5. Device executes command
6. Device → PATCH device_commands with status/result via REST API
```

**Status Reporting:**
- Device sends heartbeats via REST POST to `device_heartbeats` table
- Device updates command status via PATCH to `device_commands`
- Device updates `devices.last_seen_at` on each heartbeat

---

## Message Format

All messages are JSON objects terminated by a newline character (`\n`) for UART, or as structured payloads for Realtime.

### Command Message (Host → Device)

```json
{
  "id": "uuid",
  "cmd": "<command>",
  "capability": "<capability_name>",
  "test_name": "<test_name>",
  "params": {...}
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | uuid | Yes | Unique command identifier for tracking |
| `cmd` | string | Yes | Command name |
| `capability` | string | Conditional | Capability name (required for capability-specific commands) |
| `test_name` | string | Conditional | Test name (required for `run_test` command) |
| `params` | object | No | Command parameters |

### Response Message (Device → Host)

```json
{
  "id": "uuid",
  "status": "<status>",
  "message": "<optional message>",
  "data": {...}
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | uuid | Yes | Command ID being responded to |
| `status` | string | Yes | Status code (see below) |
| `message` | string | No | Human-readable message |
| `data` | object | No | Response data |

**Status Codes:**

| Status | Description |
|--------|-------------|
| `ok` | Command succeeded |
| `error` | Command failed |
| `acknowledged` | Command received, execution in progress |
| `completed` | Long-running command completed |
| `failed` | Test or operation failed |

---

## Commands Reference

### Core Commands

All devices support these commands regardless of capabilities.

| Command | Description |
|---------|-------------|
| `get_status` | Get current device status |
| `get_capabilities` | Get device capability manifest |
| `reboot` | Restart the device |
| `consumer_reset` | Clear consumer data, preserve factory config |
| `factory_reset` | Full reset including factory data |

### Provisioning Commands

| Command | Description | Parameters |
|---------|-------------|------------|
| `factory_provision` | Assign serial number and factory attributes | `serial_number`, `factory_attributes` |
| `set_factory_attributes` | Update factory attributes | `attributes` (JSON matching capability schema) |
| `get_factory_attributes` | Read factory attributes | None |
| `set_consumer_attributes` | Update consumer attributes | `attributes` (JSON matching capability schema) |
| `get_consumer_attributes` | Read consumer attributes | None |

### Testing Commands

| Command | Description | Parameters |
|---------|-------------|------------|
| `run_test` | Execute a capability test | `capability`, `test_name`, test-specific params |

### OTA Commands

| Command | Description | Parameters |
|---------|-------------|------------|
| `ota_update` | Trigger firmware update | `firmware_id`, `target_version`, `firmware_url` |

---

## Command Details

### factory_provision

Assigns a serial number to a device and stores factory attributes. This is the primary factory provisioning command.

**Request:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "cmd": "factory_provision",
  "params": {
    "serial_number": "SV-HUB-000001",
    "factory_attributes": {
      "cloud_url": "https://xxx.supabase.co",
      "cloud_anon_key": "eyJ...",
      "wifi": {
        "ssid": "FactoryNetwork",
        "password": "factory123"
      },
      "thread": {
        "network_name": "SaturdayVinyl",
        "pan_id": 21334,
        "channel": 15,
        "network_key": "a1b2c3d4e5f6789012345678abcdef12"
      }
    }
  }
}
```

**Response (Success):**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "ok",
  "message": "Device provisioned successfully",
  "data": {
    "serial_number": "SV-HUB-000001",
    "mac_address": "AA:BB:CC:DD:EE:FF",
    "factory_provision_attributes": {
      "thread": {
        "network_key": "a1b2c3d4e5f6789012345678abcdef12",
        "extended_pan_id": "0123456789abcdef"
      }
    }
  }
}
```

The `factory_provision_attributes` in the response contains data generated by the device during provisioning that should be stored in the cloud (e.g., Thread credentials generated by a Border Router).

### get_status

Returns current device status including firmware version, connectivity state, and capability status.

**Request:**
```json
{
  "id": "uuid",
  "cmd": "get_status"
}
```

**Response:**
```json
{
  "id": "uuid",
  "status": "ok",
  "data": {
    "device_type": "hub",
    "firmware_version": "1.2.0",
    "mac_address": "AA:BB:CC:DD:EE:FF",
    "serial_number": "SV-HUB-000001",
    "uptime_ms": 123456,
    "free_heap": 245760,
    "capabilities": {
      "wifi": {
        "configured": true,
        "connected": true,
        "ssid": "HomeNetwork",
        "rssi": -55
      },
      "thread": {
        "configured": true,
        "connected": true,
        "role": "leader"
      },
      "rfid": {
        "module_firmware": "YRM100-V2.1",
        "last_scan_count": 3
      }
    }
  }
}
```

### run_test

Executes a test defined by a capability. Test definitions come from the admin app's capability configuration.

**Request:**
```json
{
  "id": "uuid",
  "cmd": "run_test",
  "capability": "wifi",
  "test_name": "connect",
  "params": {
    "ssid": "TestNetwork",
    "password": "TestPass123",
    "timeout_ms": 30000
  }
}
```

**Response (Success):**
```json
{
  "id": "uuid",
  "status": "ok",
  "message": "Wi-Fi connected",
  "data": {
    "connected": true,
    "ssid": "TestNetwork",
    "ip": "192.168.1.100",
    "rssi": -55,
    "duration_ms": 3500
  }
}
```

**Response (Failure):**
```json
{
  "id": "uuid",
  "status": "failed",
  "message": "Wi-Fi connection timed out",
  "data": {
    "error_code": "timeout",
    "duration_ms": 30000
  }
}
```

### ota_update

Triggers an over-the-air firmware update.

**Request:**
```json
{
  "id": "uuid",
  "cmd": "ota_update",
  "params": {
    "firmware_id": "660e8400-e29b-41d4-a716-446655440001",
    "target_version": "1.3.0",
    "firmware_url": "https://xxx.supabase.co/storage/v1/object/firmware/hub_1.3.0.bin"
  }
}
```

**Response (Acknowledged):**
```json
{
  "id": "uuid",
  "status": "acknowledged",
  "message": "Starting OTA update to v1.3.0"
}
```

Device will reboot after successful update. The new firmware should report completion via heartbeat.

### consumer_reset

Clears consumer-provisioned data while preserving factory configuration.

**Request:**
```json
{
  "id": "uuid",
  "cmd": "consumer_reset"
}
```

**Clears:**
- Wi-Fi credentials (if consumer-provisioned)
- Consumer attributes from all capabilities
- BLE pairings
- User preferences

**Preserves:**
- Serial number
- Factory attributes (cloud URL, factory Wi-Fi, etc.)
- Thread credentials (if factory-provisioned)

### factory_reset

Complete factory reset - erases ALL data including serial number.

**Request:**
```json
{
  "id": "uuid",
  "cmd": "factory_reset"
}
```

**Warning:** Device will need re-provisioning after factory reset.

---

## Heartbeat Protocol

Devices send periodic heartbeats to indicate online status and report telemetry.

### Heartbeat Format

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "firmware_version": "1.2.0",
  "heartbeat_data": {
    "uptime_ms": 123456,
    "free_heap": 245760,
    "wifi_rssi": -55,
    "rfid_tag_count": 3,
    "temperature_c": 22.5
  }
}
```

### Heartbeat Frequency

- Default: Every 30 seconds
- Recommended minimum: 15 seconds
- Maximum: 60 seconds

### Storage

Heartbeats are stored in the `device_heartbeats` table with automatic cleanup (24-hour retention).

---

## Capability Model

Commands reference capabilities by name. Each capability defines:

1. **factory_attributes** - Data stored during factory provisioning (persists consumer reset)
2. **factory_provision_attributes** - Data returned by device after factory provisioning
3. **consumer_attributes** - Data stored during consumer provisioning (cleared on consumer reset)
4. **consumer_provision_attributes** - Data returned by device after consumer provisioning
5. **heartbeat_attributes** - Data included in periodic heartbeats
6. **tests** - Available test commands with parameter schemas

See [Capability Schema](../schemas/capability_schema.md) for full schema specification.

---

## Error Codes

| Code | Description |
|------|-------------|
| `parse_error` | Invalid JSON received |
| `invalid_command` | Unknown command |
| `missing_params` | Required parameters missing |
| `invalid_params` | Parameter validation failed |
| `not_provisioned` | Device not factory-provisioned |
| `already_provisioned` | Cannot re-provision without factory reset |
| `capability_not_found` | Referenced capability not supported |
| `test_not_found` | Referenced test not defined |
| `timeout` | Operation timed out |
| `busy` | Device busy with another operation |
| `internal_error` | Unexpected device error |

---

## Migration from Service Mode Protocol

### Key Changes

| Service Mode Protocol | Device Command Protocol |
|----------------------|------------------------|
| 10-second entry window | Always listening (no window) |
| `enter_service_mode` command | Not needed |
| `exit_service_mode` command | Not needed |
| `provision` command | `factory_provision` command |
| `get_manifest` command | `get_capabilities` command |
| `test_wifi`, `test_cloud`, etc. | `run_test` with capability/test_name |
| `unit_id` field | `serial_number` field |
| UART only | UART + Supabase Realtime |

### Firmware Migration Steps

1. Remove entry window logic and state machine
2. Replace `enter_service_mode`/`exit_service_mode` handlers with always-on listening
3. Update provisioning to use `factory_provision` command format
4. Implement `get_capabilities` to return capability manifest
5. Implement `run_test` dispatcher with capability/test_name routing
6. Add Supabase Realtime client for remote command reception
7. Implement heartbeat reporting to `device_heartbeats` table

---

## Implementation Reference

### Supabase Realtime Client

Reference implementation: `saturday-player-hub/s3-master/components/cloud/realtime_client.c`

Key components:
- Phoenix protocol WebSocket client
- Channel subscription to `device:{mac_address}`
- Heartbeat timer (30-second interval)
- JSON command parsing
- REST API for status reporting

### Database Tables

- `device_commands` - Command queue with broadcast trigger
- `device_heartbeats` - Heartbeat storage with 24-hour retention
- `devices` - Device registry with `last_seen_at` tracking

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-24 | Initial protocol specification (replaces Service Mode Protocol v2.2) |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
