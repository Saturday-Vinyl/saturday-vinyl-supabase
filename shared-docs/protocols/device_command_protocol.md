# Saturday Device Command Protocol

**Version:** 1.2.6
**Last Updated:** 2026-02-06
**Audience:** Saturday Admin App developers, Firmware engineers, Consumer App developers

---

## Table of Contents

1. [Overview](#overview)
2. [Transport Layers](#transport-layers)
3. [Message Format](#message-format)
4. [Commands Reference](#commands-reference)
5. [Command Details](#command-details)
   - [factory_provision](#factory_provision)
   - [get_status](#get_status)
   - [run_test](#run_test)
   - [ota_update](#ota_update)
   - [consumer_reset](#consumer_reset)
   - [factory_reset](#factory_reset)
6. [Heartbeat Protocol](#heartbeat-protocol)
7. [Command Acknowledgement Protocol](#command-acknowledgement-protocol)
8. [Capability Model](#capability-model)
9. [Firmware JSON Schema](#firmware-json-schema)
10. [ESP-IDF Implementation Guide](#esp-idf-implementation-guide)
11. [Attribute Schema Reference](#attribute-schema-reference)
12. [Error Codes](#error-codes)
13. [Migration from Service Mode Protocol](#migration-from-service-mode-protocol)
14. [Implementation Reference](#implementation-reference)
15. [Version History](#version-history)

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
5. Device sends command_ack heartbeat (acknowledges receipt)
6. Device executes command
7. Device sends command_result heartbeat (reports completion/failure)
```

**Status Reporting:**
- Device sends heartbeats via REST POST to `device_heartbeats` table
- Device acknowledges commands via `command_ack` heartbeat type
- Device reports command results via `command_result` heartbeat type
- Database trigger automatically updates `device_commands.status` from heartbeats
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
| `factory_provision` | Assign serial number, name, and provision data | `serial_number`, `name`, plus capability-specific fields |
| `set_provision_data` | Update provision data | Capability-specific fields at top level |
| `get_provision_data` | Read all stored provision data | None |

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

Assigns a serial number and product name to a device and stores provision data. This is the primary factory provisioning command.

**Required Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `serial_number` | string | Unique device serial number (e.g., "SV-HUB-000001") |
| `name` | string | Human-friendly product name (e.g., "Crate", "Hub") |

**Additional Parameters:**

All other provisioning data is passed as **top-level fields** in the `params` object. The firmware's capability schemas define what fields are expected. Common fields include:

| Parameter | Type | Description |
|-----------|------|-------------|
| `cloud_url` | string | Cloud API endpoint URL |
| `cloud_anon_key` | string | Cloud API public key |
| `wifi_ssid` | string | Factory WiFi SSID |
| `wifi_password` | string | Factory WiFi password |
| `thread_network_name` | string | Thread network name |
| `thread_channel` | number | Thread radio channel |
| `thread_pan_id` | number | Thread PAN ID |
| `thread_network_key` | string | Thread master key (hex) |

**About the `name` Parameter:**

The `name` is the human-friendly product name (not the company name, not the device type identifier). This is typically the Product name from the admin app (e.g., "Crate", "Hub", "Speaker").

The firmware uses this name to construct user-facing identifiers:
- BLE advertising name: `"Saturday {name} {serial_number last 4}"` → "Saturday Crate 0001"
- mDNS hostname: `"saturday-{name}-{serial_number last 4}"` → "saturday-crate-0001"
- Display labels, etc.

**Request:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "cmd": "factory_provision",
  "params": {
    "serial_number": "SV-CRT-000001",
    "name": "Crate",
    "cloud_url": "https://xxx.supabase.co",
    "cloud_anon_key": "eyJ...",
    "wifi_ssid": "FactoryNetwork",
    "wifi_password": "factory123",
    "thread_network_name": "SaturdayVinyl",
    "thread_pan_id": 21334,
    "thread_channel": 15,
    "thread_network_key": "a1b2c3d4e5f6789012345678abcdef12"
  }
}
```

**Response (Success):**

The device responds with data defined by its `factory_output` capability schemas. The response `data` object contains **only** the fields specified in the firmware's JSON schema under each capability's `factory_output` section.

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "ok",
  "message": "Device provisioned successfully",
  "data": {
    "serial_number": "SV-CRT-000001",
    "name": "Crate",
    "mac_address": "AA:BB:CC:DD:EE:FF",
    "thread_credentials": {
      "pan_id": 21334,
      "channel": 15,
      "network_name": "SaturdayVinyl",
      "network_key": "a1b2c3d4e5f6789012345678abcdef12",
      "extended_pan_id": "0123456789abcdef"
    }
  }
}
```

**Validation:** The admin app **must** validate that the response `data` contains all fields marked as `required` in the device type's `factory_output` schemas. If any required fields are missing, provisioning should fail and the user should be notified. This ensures the device firmware is correctly implementing the capability contract.

**Cloud Storage:** The admin app stores **only** the response `data` (minus `serial_number` and `name`) in the `devices.provision_data` JSONB column. Input parameters sent to the device are **not** stored — only the device's response data is persisted. See [Cloud Provision Data](#cloud-provision-data) for details.

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
    "device_type": "crate",
    "firmware_version": "1.2.0",
    "mac_address": "AA:BB:CC:DD:EE:FF",
    "serial_number": "SV-CRT-000001",
    "name": "Crate",
    "uptime_sec": 123456,
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

**Standard Status Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `device_type` | string | Device type identifier (e.g., "hub", "crate") |
| `firmware_version` | string | Current firmware version |
| `mac_address` | string | Primary MAC address (hardware identifier) |
| `serial_number` | string | Device serial number (null if not provisioned) |
| `name` | string | Human-friendly product name (null if not provisioned) |
| `uptime_sec` | number | Seconds since boot |
| `free_heap` | number | Free heap memory in bytes |
| `capabilities` | object | Capability-specific status (varies by device) |
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

All telemetry fields are at the top level (not nested):

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-CRT-000001",
  "device_type": "crate",
  "firmware_version": "1.2.0",
  "uptime_sec": 123456,
  "free_heap": 245760,
  "min_free_heap": 180224,
  "largest_free_block": 114688,
  "wifi_rssi": -55,
  "rfid_tag_count": 3,
  "temperature_c": 22.5
}
```

### Standard Heartbeat Fields

All devices must include these fields in every heartbeat, regardless of capabilities:

| Field | Type | Description | ESP-IDF Function |
|-------|------|-------------|------------------|
| `mac_address` | string | Primary MAC address (device identifier) | `esp_read_mac()` |
| `unit_id` | string | Serial number of the unit (from provisioning) | NVS lookup |
| `device_type` | string | Device type slug (from firmware schema) | Compile-time constant |
| `firmware_version` | string | Current firmware version | Compile-time constant |
| `uptime_sec` | integer | Seconds since boot | `esp_timer_get_time() / 1000000` |
| `free_heap` | integer | Current free heap memory in bytes | `esp_get_free_heap_size()` |
| `min_free_heap` | integer | Minimum free heap since boot (detects memory leaks) | `esp_get_minimum_free_heap_size()` |
| `largest_free_block` | integer | Largest contiguous free block in bytes (detects fragmentation) | `heap_caps_get_largest_free_block(MALLOC_CAP_8BIT)` |

Additional capability-specific fields are added based on device capabilities. Field names should be descriptive and avoid conflicts with standard fields.

### Known Device-Specific Heartbeat Fields

Devices may include the following capability-specific fields in their heartbeats. Not all fields apply to all devices — include only what the hardware supports.

#### Power / Battery

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `battery_level` | integer | Battery state of charge (0-100%) | Fuel gauge IC (e.g., BQ27441) |
| `battery_charging` | boolean | Whether the battery is currently charging | Fuel gauge current direction |

#### Environmental Sensors

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `temperature_c` | float | Ambient temperature in Celsius | SHT40 or equivalent |
| `humidity_pct` | float | Relative humidity percentage | SHT40 or equivalent |

#### Connectivity

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `wifi_rssi` | integer | WiFi signal strength in dBm | WiFi driver |
| `thread_rloc16` | string | Thread routing locator (mesh address) | Thread stack |

#### Application-Specific

| Field | Type | Description | Source |
|-------|------|-------------|--------|
| `rfid_tag_count` | integer | Number of RFID tags currently detected | RFID reader |

> **Adding new fields:** When introducing new device-specific heartbeat fields, add them to the appropriate category above and follow the naming convention: `capability_metric` (e.g., `battery_level`, `temperature_c`). Use SI units where applicable and include the unit in the field name suffix (`_c`, `_pct`, `_mv`, `_ma`).

### Heartbeat Frequency

- Default: Every 30 seconds
- Recommended minimum: 15 seconds
- Maximum: 60 seconds

### Storage

Heartbeats are stored in the `device_heartbeats` table with automatic cleanup (24-hour retention). The complete telemetry payload is stored as JSONB in the `telemetry` column. Routing fields (`mac_address`, `unit_id`, `device_type`, `type`, `command_id`) are stored as typed columns for indexing.

On each INSERT, a trigger (`sync_heartbeat_to_device_and_unit`) automatically:
1. Updates `devices.latest_telemetry` and `devices.last_seen_at` (matched by `mac_address`)
2. Aggregates consumer-facing fields to typed columns on the `units` table (`battery_level`, `is_online`, `wifi_rssi`, `temperature_c`, `humidity_pct`, etc.) matched by `unit_id` → `units.serial_number`

### Relayed Heartbeats

Some devices lack direct cloud connectivity (e.g., Thread-only devices without WiFi). These devices send heartbeats through a **relay** - another device or application that has cloud access.

**Relay Types:**
- **Hub**: A Saturday Hub with WiFi connectivity relays heartbeats for Thread-connected devices
- **Consumer Phone**: A consumer's mobile app can relay heartbeats for BLE-connected devices during setup

**Relayed Heartbeat Format:**

When a relay forwards a heartbeat, it adds relay identification fields:

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-CRT-000001",
  "device_type": "crate",
  "firmware_version": "1.2.0",
  "uptime_sec": 123456,
  "free_heap": 245760,
  "min_free_heap": 180224,
  "largest_free_block": 114688,
  "relay_device_type": "hub",
  "relay_instance_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Relay Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `relay_device_type` | string | Slug of the relay's device type (e.g., "hub", "crate") |
| `relay_instance_id` | uuid | Instance identifier of the relay (device ID or session ID for non-device relays) |

**Relay Implementation:**

1. The originating device sends its heartbeat via Thread/BLE to the relay
2. The relay receives the heartbeat payload
3. The relay adds `relay_device_type` and `relay_instance_id` fields
4. The relay POSTs the complete payload to the cloud

The originating device's fields (`mac_address`, `unit_id`, etc.) remain unchanged - the relay only adds relay identification.

---

## Command Acknowledgement Protocol

When devices receive commands via WebSocket, they must acknowledge receipt and report results using specialized heartbeat types. This provides a robust two-way communication channel that mirrors the serial monitor experience.

### Heartbeat Types

The `type` field in heartbeats indicates the purpose:

| Type | Description |
|------|-------------|
| `status` | Regular telemetry heartbeat (default) |
| `command_ack` | Acknowledges receipt of a command |
| `command_result` | Reports command completion or failure |

### Command Acknowledgement Flow

```
1. Device receives command via WebSocket (device:{mac_address} channel)
2. Device immediately sends command_ack heartbeat
3. Device executes the command
4. Device sends command_result heartbeat with outcome
```

### Acknowledgement Heartbeat Format

When acknowledging a command, include the `type` and `command_id` fields:

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-CRT-000001",
  "device_type": "crate",
  "firmware_version": "1.2.0",
  "uptime_sec": 123456,
  "free_heap": 245760,
  "min_free_heap": 180224,
  "largest_free_block": 114688,
  "type": "command_ack",
  "command_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Required Fields for Ack:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Must be `"command_ack"` |
| `command_id` | uuid | The `id` field from the received command |

All standard heartbeat fields should also be included.

### Result Heartbeat Format

After command execution, send a result heartbeat:

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-CRT-000001",
  "device_type": "crate",
  "firmware_version": "1.2.0",
  "uptime_sec": 123460,
  "free_heap": 245760,
  "min_free_heap": 180224,
  "largest_free_block": 114688,
  "type": "command_result",
  "command_id": "550e8400-e29b-41d4-a716-446655440000",
  "heartbeat_data": {
    "status": "completed",
    "result": {
      "device_type": "crate",
      "firmware_version": "1.2.0",
      "mac_address": "AA:BB:CC:DD:EE:FF"
    }
  }
}
```

**For failed commands:**

```json
{
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "unit_id": "SV-CRT-000001",
  "device_type": "crate",
  "firmware_version": "1.2.0",
  "uptime_sec": 123460,
  "free_heap": 245760,
  "min_free_heap": 180224,
  "largest_free_block": 114688,
  "type": "command_result",
  "command_id": "550e8400-e29b-41d4-a716-446655440000",
  "heartbeat_data": {
    "status": "failed",
    "error_message": "WiFi connection timed out"
  }
}
```

**Result Heartbeat Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | string | Must be `"command_result"` |
| `command_id` | uuid | The `id` field from the received command |
| `heartbeat_data.status` | string | `"completed"` or `"failed"` |
| `heartbeat_data.result` | object | Command result data (for successful commands) |
| `heartbeat_data.error_message` | string | Error description (for failed commands) |

### Database Status Updates

The cloud automatically updates `device_commands.status` based on heartbeat type:

| Heartbeat Type | Sets device_commands.status to |
|----------------|--------------------------------|
| `command_ack` | `acknowledged` |
| `command_result` with `status: "completed"` | `completed` |
| `command_result` with `status: "failed"` | `failed` |

This is handled by a database trigger, so devices only need to POST heartbeats - no PATCH requests are required.

### ESP-IDF Implementation Example

```c
// Send command acknowledgement
void send_command_ack(const char *command_id) {
    cJSON *heartbeat = create_standard_heartbeat();
    cJSON_AddStringToObject(heartbeat, "type", "command_ack");
    cJSON_AddStringToObject(heartbeat, "command_id", command_id);

    char *json_str = cJSON_PrintUnformatted(heartbeat);
    post_to_supabase("/rest/v1/device_heartbeats", json_str);

    cJSON_free(json_str);
    cJSON_Delete(heartbeat);
}

// Send command result
void send_command_result(const char *command_id, bool success,
                         cJSON *result, const char *error_message) {
    cJSON *heartbeat = create_standard_heartbeat();
    cJSON_AddStringToObject(heartbeat, "type", "command_result");
    cJSON_AddStringToObject(heartbeat, "command_id", command_id);

    cJSON *data = cJSON_CreateObject();
    cJSON_AddStringToObject(data, "status", success ? "completed" : "failed");

    if (success && result) {
        cJSON_AddItemToObject(data, "result", cJSON_Duplicate(result, true));
    }
    if (!success && error_message) {
        cJSON_AddStringToObject(data, "error_message", error_message);
    }

    cJSON_AddItemToObject(heartbeat, "heartbeat_data", data);

    char *json_str = cJSON_PrintUnformatted(heartbeat);
    post_to_supabase("/rest/v1/device_heartbeats", json_str);

    cJSON_free(json_str);
    cJSON_Delete(heartbeat);
}

// Example command handler
void handle_websocket_command(const char *json_str) {
    cJSON *cmd = cJSON_Parse(json_str);
    const char *cmd_id = cJSON_GetStringValue(cJSON_GetObjectItem(cmd, "id"));
    const char *cmd_name = cJSON_GetStringValue(cJSON_GetObjectItem(cmd, "cmd"));

    // Immediately acknowledge receipt
    send_command_ack(cmd_id);

    // Execute command
    cJSON *result = cJSON_CreateObject();
    bool success = execute_command(cmd_name, cJSON_GetObjectItem(cmd, "params"), result);

    // Report result
    send_command_result(cmd_id, success, result,
                        success ? NULL : "Command execution failed");

    cJSON_Delete(result);
    cJSON_Delete(cmd);
}
```

---

## Capability Model

Commands reference capabilities by name. Each capability defines schemas that serve as **firmware dictionaries**:

| Schema | Direction | Phase | Description |
|--------|-----------|-------|-------------|
| `factory_input` | TO device | Factory | Data sent during factory provisioning (UART) |
| `factory_output` | FROM device | Factory | Data returned after factory provisioning |
| `consumer_input` | TO device | Consumer | Data sent during consumer provisioning (BLE) |
| `consumer_output` | FROM device | Consumer | Data returned after consumer provisioning |
| `heartbeat` | FROM device | Runtime | Telemetry data in periodic heartbeats |
| `tests` | Bidirectional | Any | Test commands with parameter/result schemas |

**Data Persistence (Device NVS):**
- **Factory data** persists through consumer reset (stored with `source: "factory"` in NVS)
- **Consumer data** is cleared on consumer reset (stored with `source: "consumer"` in NVS)

**Cloud Provision Data:**

The cloud maintains a snapshot of device-reported provisioning data in the `devices.provision_data` JSONB column. This column stores **only the data returned by the device** (the `_output` schemas), not the input parameters sent to the device.

**Why only output data?**
- Input parameters (cloud_url, wifi_ssid, etc.) are configuration that the app already knows
- Output data (thread_credentials, mac_address, etc.) is device-generated and must be captured
- The firmware JSON schema's `factory_output` and `consumer_output` define exactly what the device returns
- Storing only device responses keeps the data authoritative and avoids redundancy

| Event | Data stored in `provision_data` |
|-------|--------------------------------|
| Factory provisioning | `factory_output` data returned by device |
| Consumer provisioning | `consumer_output` data returned by device (merged with existing) |

**Validation Requirement:**

Before storing provision data, the admin app **must** validate that the device response contains all fields marked as `required` in the applicable `_output` schema. If required fields are missing:
- Provisioning should **fail**
- User should be notified which fields are missing
- No data should be stored in `provision_data`

This ensures firmware correctly implements the capability contract defined in the JSON schema.

**Example: Factory provisioning a Hub with Thread Border Router capability**

The `thread_br` capability defines a `factory_output` schema with required field `thread_credentials`. After successful provisioning:
```json
{
  "mac_address": "DC:B4:D9:05:2C:30",
  "thread_credentials": {
    "pan_id": 21334,
    "channel": 15,
    "network_key": "7f5a4c63a626af7f147b10606d03b0cb",
    "network_name": "SaturdayVinyl",
    "extended_pan_id": "2b22d7cfb4b400c9"
  }
}
```

**Example: After consumer provisioning adds WiFi credentials**

The `wifi` capability defines a `consumer_output` schema. New keys are merged:
```json
{
  "mac_address": "DC:B4:D9:05:2C:30",
  "thread_credentials": { "..." },
  "connected": true,
  "ip_address": "192.168.1.100",
  "rssi": -55
}
```

Note: `serial_number` and `name` are not stored in `provision_data` — they are tracked in `units.serial_number` and the unit's product name respectively.

**Provisioning Phases:**
- **Factory provisioning**: Via UART at the factory. Sets device identity, cloud credentials, Thread network config.
- **Consumer provisioning**: Via BLE when end user sets up device. Sets WiFi credentials, user preferences.

See [Capability Schema](../schemas/capability_schema.md) for full schema specification.

---

## Firmware JSON Schema

When building firmware for a Saturday device, developers receive a **Firmware JSON Schema** file from the admin app. This file defines exactly what capabilities the firmware must implement.

### Schema Format

```json
{
  "version": "0.5.1",
  "device_type": "hub-prototype",
  "capabilities": {
    "wifi": {
      "consumer_input": {
        "type": "object",
        "required": ["ssid", "password"],
        "properties": {
          "ssid": { "type": "string" },
          "password": { "type": "string" }
        }
      },
      "consumer_output": {
        "type": "object",
        "properties": {
          "connected": { "type": "boolean" },
          "ip_address": { "type": "string" },
          "rssi": { "type": "number" }
        }
      },
      "heartbeat": {
        "type": "object",
        "properties": {
          "connected": { "type": "boolean" },
          "rssi": { "type": "integer" }
        }
      },
      "tests": {
        "connect": {
          "params": {
            "type": "object",
            "properties": {
              "ssid": { "type": "string" },
              "password": { "type": "string" },
              "timeout_ms": { "type": "integer", "default": 30000 }
            }
          },
          "result": {
            "type": "object",
            "properties": {
              "connected": { "type": "boolean" },
              "ip_address": { "type": "string" },
              "rssi": { "type": "number" }
            }
          }
        }
      }
    },
    "cloud": {
      "factory_input": {
        "type": "object",
        "required": ["cloud_url", "cloud_anon_key"],
        "properties": {
          "cloud_url": { "type": "string", "format": "uri" },
          "cloud_anon_key": { "type": "string" }
        }
      },
      "heartbeat": {
        "type": "object",
        "properties": {
          "connected": { "type": "boolean" },
          "latency_ms": { "type": "integer" }
        }
      }
    }
  }
}
```

### Top-Level Fields

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Firmware version (semver format) |
| `device_type` | string | Device type slug (e.g., "hub-prototype", "crate") |
| `capabilities` | object | Map of capability name → capability schema |

### Capability Schema Fields

Each capability can include any combination of these schemas (all are optional):

| Field | Description |
|-------|-------------|
| `factory_input` | JSON Schema for data received during factory provisioning |
| `factory_output` | JSON Schema for data returned after factory provisioning |
| `consumer_input` | JSON Schema for data received during consumer provisioning (BLE) |
| `consumer_output` | JSON Schema for data returned after consumer provisioning |
| `heartbeat` | JSON Schema for telemetry data in periodic heartbeats |
| `tests` | Object mapping test name → { params, result } schemas |

### Obtaining the Schema

1. Open the Saturday Admin App
2. Navigate to Device Types → [Your Device Type]
3. Click on the firmware version
4. Click "Download JSON" to get the schema file

---

## ESP-IDF Implementation Guide

This section provides guidance for implementing the Device Command Protocol in ESP-IDF firmware.

### Project Structure

```
components/
├── device_protocol/
│   ├── include/
│   │   ├── device_protocol.h      # Protocol types and functions
│   │   ├── capability_handler.h   # Capability interface
│   │   └── firmware_schema.h      # Generated from JSON schema
│   ├── device_protocol.c          # Command dispatcher
│   ├── provisioning.c             # Provisioning handlers
│   └── Kconfig                    # Configuration options
├── capabilities/
│   ├── wifi_capability.c          # WiFi capability implementation
│   ├── cloud_capability.c         # Cloud capability implementation
│   ├── thread_capability.c        # Thread capability implementation
│   └── ...
└── nvs_schema/
    └── provision_data.c           # NVS key management
```

### Step 1: Parse the Firmware Schema

Convert the JSON schema to C header definitions. You can do this manually or use a code generator.

```c
// firmware_schema.h - Generated or manually created from JSON schema

#define FIRMWARE_VERSION "0.5.1"
#define DEVICE_TYPE "hub-prototype"

// Capability: wifi
#define CAP_WIFI_ENABLED 1
#define CAP_WIFI_HAS_CONSUMER_INPUT 1
#define CAP_WIFI_HAS_CONSUMER_OUTPUT 1
#define CAP_WIFI_HAS_HEARTBEAT 1

// WiFi consumer input fields
typedef struct {
    char ssid[33];
    char password[65];
} wifi_consumer_input_t;

// WiFi consumer output fields
typedef struct {
    bool connected;
    char ip_address[16];
    int rssi;
} wifi_consumer_output_t;

// WiFi heartbeat fields
typedef struct {
    bool connected;
    int rssi;
} wifi_heartbeat_t;

// Capability: cloud
#define CAP_CLOUD_ENABLED 1
#define CAP_CLOUD_HAS_FACTORY_INPUT 1
#define CAP_CLOUD_HAS_HEARTBEAT 1

// Cloud factory input fields
typedef struct {
    char cloud_url[256];
    char cloud_anon_key[256];
} cloud_factory_input_t;
```

### Step 2: Implement NVS Storage

Store provisioning data in NVS with source tagging:

```c
// nvs_schema.c

#include "nvs_flash.h"

#define NVS_NAMESPACE "provision"

// NVS key naming convention: {capability}_{field}
// Source is stored separately: {capability}_{field}_src ("factory" or "consumer")

esp_err_t provision_set_string(const char *key, const char *value, const char *source) {
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &handle);
    if (err != ESP_OK) return err;

    // Store value
    err = nvs_set_str(handle, key, value);
    if (err != ESP_OK) {
        nvs_close(handle);
        return err;
    }

    // Store source tag
    char src_key[32];
    snprintf(src_key, sizeof(src_key), "%s_src", key);
    err = nvs_set_str(handle, src_key, source);

    nvs_commit(handle);
    nvs_close(handle);
    return err;
}

esp_err_t provision_consumer_reset(void) {
    // Iterate all keys, delete those with source="consumer"
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &handle);
    if (err != ESP_OK) return err;

    nvs_iterator_t it = NULL;
    err = nvs_entry_find(NVS_DEFAULT_PART_NAME, NVS_NAMESPACE, NVS_TYPE_ANY, &it);

    while (err == ESP_OK) {
        nvs_entry_info_t info;
        nvs_entry_info(it, &info);

        // Check if this is a _src key
        if (strstr(info.key, "_src") != NULL) {
            char source[16];
            size_t len = sizeof(source);
            if (nvs_get_str(handle, info.key, source, &len) == ESP_OK) {
                if (strcmp(source, "consumer") == 0) {
                    // Delete the value and source keys
                    char value_key[32];
                    strncpy(value_key, info.key, strlen(info.key) - 4);
                    value_key[strlen(info.key) - 4] = '\0';
                    nvs_erase_key(handle, value_key);
                    nvs_erase_key(handle, info.key);
                }
            }
        }
        err = nvs_entry_next(&it);
    }

    nvs_commit(handle);
    nvs_close(handle);
    nvs_release_iterator(it);
    return ESP_OK;
}
```

### Step 3: Implement Command Dispatcher

```c
// device_protocol.c

#include "cJSON.h"
#include "device_protocol.h"

typedef struct {
    const char *cmd;
    esp_err_t (*handler)(const cJSON *params, cJSON *response);
} command_entry_t;

static const command_entry_t commands[] = {
    {"get_status", handle_get_status},
    {"factory_provision", handle_factory_provision},
    {"set_provision_data", handle_set_provision_data},
    {"get_provision_data", handle_get_provision_data},
    {"run_test", handle_run_test},
    {"consumer_reset", handle_consumer_reset},
    {"factory_reset", handle_factory_reset},
    {"ota_update", handle_ota_update},
    {"reboot", handle_reboot},
    {NULL, NULL}
};

esp_err_t device_protocol_handle_command(const char *json_str, char *response_buf, size_t buf_size) {
    cJSON *root = cJSON_Parse(json_str);
    if (!root) {
        snprintf(response_buf, buf_size,
            "{\"status\":\"error\",\"message\":\"parse_error\"}");
        return ESP_ERR_INVALID_ARG;
    }

    const char *cmd_id = cJSON_GetStringValue(cJSON_GetObjectItem(root, "id"));
    const char *cmd = cJSON_GetStringValue(cJSON_GetObjectItem(root, "cmd"));
    cJSON *params = cJSON_GetObjectItem(root, "params");

    cJSON *response = cJSON_CreateObject();
    cJSON_AddStringToObject(response, "id", cmd_id ? cmd_id : "");

    esp_err_t err = ESP_ERR_NOT_FOUND;
    for (int i = 0; commands[i].cmd != NULL; i++) {
        if (strcmp(cmd, commands[i].cmd) == 0) {
            err = commands[i].handler(params, response);
            break;
        }
    }

    if (err == ESP_ERR_NOT_FOUND) {
        cJSON_AddStringToObject(response, "status", "error");
        cJSON_AddStringToObject(response, "message", "invalid_command");
    }

    char *resp_str = cJSON_PrintUnformatted(response);
    strncpy(response_buf, resp_str, buf_size - 1);
    response_buf[buf_size - 1] = '\0';

    cJSON_free(resp_str);
    cJSON_Delete(response);
    cJSON_Delete(root);

    return err;
}
```

### Step 4: Implement Capability Handlers

```c
// capabilities/wifi_capability.c

#include "wifi_capability.h"
#include "esp_wifi.h"

esp_err_t wifi_handle_consumer_input(const cJSON *params) {
    const char *ssid = cJSON_GetStringValue(cJSON_GetObjectItem(params, "ssid"));
    const char *password = cJSON_GetStringValue(cJSON_GetObjectItem(params, "password"));

    if (!ssid || !password) {
        return ESP_ERR_INVALID_ARG;
    }

    // Store with consumer source tag
    provision_set_string("wifi_ssid", ssid, "consumer");
    provision_set_string("wifi_password", password, "consumer");

    // Apply configuration
    wifi_config_t wifi_config = {0};
    strncpy((char *)wifi_config.sta.ssid, ssid, sizeof(wifi_config.sta.ssid));
    strncpy((char *)wifi_config.sta.password, password, sizeof(wifi_config.sta.password));

    esp_wifi_set_config(WIFI_IF_STA, &wifi_config);
    esp_wifi_connect();

    return ESP_OK;
}

esp_err_t wifi_get_consumer_output(cJSON *output) {
    wifi_ap_record_t ap_info;
    esp_netif_ip_info_t ip_info;

    bool connected = (esp_wifi_sta_get_ap_info(&ap_info) == ESP_OK);

    cJSON_AddBoolToObject(output, "connected", connected);

    if (connected) {
        cJSON_AddNumberToObject(output, "rssi", ap_info.rssi);

        esp_netif_t *netif = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
        if (esp_netif_get_ip_info(netif, &ip_info) == ESP_OK) {
            char ip_str[16];
            esp_ip4addr_ntoa(&ip_info.ip, ip_str, sizeof(ip_str));
            cJSON_AddStringToObject(output, "ip_address", ip_str);
        }
    }

    return ESP_OK;
}

esp_err_t wifi_get_heartbeat(cJSON *heartbeat) {
    wifi_ap_record_t ap_info;
    bool connected = (esp_wifi_sta_get_ap_info(&ap_info) == ESP_OK);

    cJSON_AddBoolToObject(heartbeat, "wifi_connected", connected);
    if (connected) {
        cJSON_AddNumberToObject(heartbeat, "wifi_rssi", ap_info.rssi);
    }

    return ESP_OK;
}

esp_err_t wifi_run_test(const char *test_name, const cJSON *params, cJSON *result) {
    if (strcmp(test_name, "connect") == 0) {
        const char *ssid = cJSON_GetStringValue(cJSON_GetObjectItem(params, "ssid"));
        const char *password = cJSON_GetStringValue(cJSON_GetObjectItem(params, "password"));
        int timeout_ms = 30000;

        cJSON *timeout_obj = cJSON_GetObjectItem(params, "timeout_ms");
        if (timeout_obj) timeout_ms = timeout_obj->valueint;

        // Attempt connection with timeout
        // ... implementation ...

        return wifi_get_consumer_output(result);
    }

    return ESP_ERR_NOT_FOUND;
}
```

### Step 5: Implement BLE Provisioning (Consumer Input)

The `consumer_input` schema drives BLE characteristic generation:

```c
// ble_provisioning.c

// Each consumer_input field becomes a BLE characteristic
// Service UUID: Generated from device_type slug
// Characteristic UUIDs: Generated from capability + field names

static const esp_gatts_attr_db_t wifi_gatt_db[] = {
    // WiFi Service Declaration
    [IDX_SVC] = {{ESP_GATT_AUTO_RSP}, {ESP_UUID_LEN_16, ...}},

    // SSID Characteristic
    [IDX_CHAR_SSID] = {{ESP_GATT_AUTO_RSP}, {ESP_UUID_LEN_16, ...}},
    [IDX_CHAR_VAL_SSID] = {{ESP_GATT_RSP_BY_APP}, {ESP_UUID_LEN_128, ...}},

    // Password Characteristic
    [IDX_CHAR_PASSWORD] = {{ESP_GATT_AUTO_RSP}, {ESP_UUID_LEN_16, ...}},
    [IDX_CHAR_VAL_PASSWORD] = {{ESP_GATT_RSP_BY_APP}, {ESP_UUID_LEN_128, ...}},
};

// Handle BLE writes
static void gatts_write_event_handler(esp_gatt_if_t gatts_if, esp_ble_gatts_cb_param_t *param) {
    if (param->write.handle == wifi_handle_table[IDX_CHAR_VAL_SSID]) {
        provision_set_string("wifi_ssid", (char *)param->write.value, "consumer");
    } else if (param->write.handle == wifi_handle_table[IDX_CHAR_VAL_PASSWORD]) {
        provision_set_string("wifi_password", (char *)param->write.value, "consumer");
    }
}
```

### Step 6: Implement Heartbeat Reporting

```c
// heartbeat.c

#include "esp_http_client.h"
#include "esp_heap_caps.h"

#define HEARTBEAT_INTERVAL_MS 30000

static void heartbeat_task(void *arg) {
    while (1) {
        cJSON *heartbeat = cJSON_CreateObject();

        // Standard fields (required for all devices)
        cJSON_AddStringToObject(heartbeat, "mac_address", get_mac_address());
        cJSON_AddStringToObject(heartbeat, "unit_id", get_unit_id());  // From NVS (provisioning)
        cJSON_AddStringToObject(heartbeat, "device_type", DEVICE_TYPE);  // From firmware schema
        cJSON_AddStringToObject(heartbeat, "firmware_version", FIRMWARE_VERSION);
        cJSON_AddNumberToObject(heartbeat, "uptime_sec", esp_timer_get_time() / 1000000);
        cJSON_AddNumberToObject(heartbeat, "free_heap", esp_get_free_heap_size());
        cJSON_AddNumberToObject(heartbeat, "min_free_heap", esp_get_minimum_free_heap_size());
        cJSON_AddNumberToObject(heartbeat, "largest_free_block",
            heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));

        // Capability heartbeat fields (flat structure)
        #if CAP_WIFI_HAS_HEARTBEAT
        wifi_get_heartbeat(heartbeat);
        #endif

        #if CAP_CLOUD_HAS_HEARTBEAT
        cloud_get_heartbeat(heartbeat);
        #endif

        // POST to Supabase
        char *json_str = cJSON_PrintUnformatted(heartbeat);
        post_to_supabase("/rest/v1/device_heartbeats", json_str);

        cJSON_free(json_str);
        cJSON_Delete(heartbeat);

        vTaskDelay(pdMS_TO_TICKS(HEARTBEAT_INTERVAL_MS));
    }
}
```

### Key Implementation Notes

1. **All data is flat**: Protocol messages use flat key-value structures. Capability groupings are organizational only.

2. **Source tagging**: Always store the provisioning source ("factory" or "consumer") alongside each value in NVS.

3. **Consumer reset**: Must only clear data tagged with `source: "consumer"`. Factory data persists.

4. **BLE characteristics**: Map directly from `consumer_input` schema fields. Each property becomes a characteristic.

5. **Tests are capability-scoped**: Use the `capability` and `test_name` fields to route to the correct handler.

6. **Heartbeat fields are prefixed**: Use capability prefixes (e.g., `wifi_rssi`, `cloud_connected`) to avoid conflicts.

---

## Attribute Schema Reference

### Purpose of Attribute Schemas

The capability schemas serve as **firmware dictionaries** - they define what data the firmware must be prepared to handle. The schemas exist to:

1. **Document capability contracts** - What data each capability handles
2. **Enable validation** - Admin app validates payloads against schemas
3. **Drive firmware implementation** - Firmware knows what NVS keys, BLE characteristics, or API fields to implement
4. **Generate BLE services** - Consumer input schema drives BLE characteristic generation

### Data Flow

All commands accept and return flat parameter objects. Capability groupings are organizational:

```json
// factory_provision - all fields at top level in params
{
  "cmd": "factory_provision",
  "params": {
    "serial_number": "SV-CRT-000001",
    "name": "Crate",
    "cloud_url": "https://...",
    "cloud_anon_key": "...",
    "wifi_ssid": "...",
    "wifi_password": "..."
  }
}

// Response - all fields at top level in data
{
  "status": "ok",
  "data": {
    "serial_number": "SV-CRT-000001",
    "name": "Crate",
    "mac_address": "AA:BB:CC:DD:EE:FF",
    "thread_network_key": "...",
    "thread_extended_pan_id": "..."
  }
}
```

### Example: WiFi Capability

**Schema Definition (from JSON file):**
```json
{
  "wifi": {
    "consumer_input": {
      "type": "object",
      "required": ["ssid", "password"],
      "properties": {
        "ssid": { "type": "string" },
        "password": { "type": "string" }
      }
    },
    "consumer_output": {
      "type": "object",
      "properties": {
        "connected": { "type": "boolean" },
        "rssi": { "type": "number" },
        "ip_address": { "type": "string" }
      }
    },
    "heartbeat": {
      "type": "object",
      "properties": {
        "wifi_connected": { "type": "boolean" },
        "wifi_rssi": { "type": "integer" }
      }
    }
  }
}
```

**Firmware Implementation:**
- Store `ssid` and `password` to NVS with `source: "consumer"`
- Expose BLE characteristics for `ssid` and `password`
- Return `connected`, `rssi`, `ip_address` after BLE provisioning completes
- Report `wifi_connected` and `wifi_rssi` in heartbeats

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
- `devices` - Device registry with `last_seen_at` tracking, `provision_data` JSONB

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.2.6 | 2026-02-06 | Clarified that `provision_data` stores only device response data (`_output` schemas), not input params; added validation requirement - provisioning must fail if required `factory_output` fields are missing |
| 1.2.5 | 2026-02-04 | Added Cloud Provision Data section documenting `devices.provision_data` JSONB column |
| 1.2.4 | 2026-01-30 | Added Command Acknowledgement Protocol section; devices must send `command_ack` and `command_result` heartbeat types when receiving commands via WebSocket |
| 1.2.3 | 2026-01-27 | Added Relayed Heartbeats section documenting `relay_device_type` and `relay_instance_id` fields for devices without direct cloud access |
| 1.2.2 | 2026-01-27 | Changed `uptime_ms` to `uptime_sec` (seconds instead of milliseconds); added `unit_id` and `device_type` to standard heartbeat fields |
| 1.2.1 | 2026-01-26 | Added standard heartbeat fields section with required memory health fields (`min_free_heap`, `largest_free_block`) |
| 1.2.0 | 2026-01-26 | Flattened all request/response payloads; capability schemas now use `factory_input`/`factory_output`/`consumer_input`/`consumer_output`/`heartbeat`/`tests`; added Firmware JSON Schema section; added ESP-IDF Implementation Guide |
| 1.1.0 | 2026-01-25 | Added required `name` parameter to `factory_provision`; added `name` to `get_status` response; added Attribute Schema Reference section clarifying schema purpose |
| 1.0.0 | 2026-01-24 | Initial protocol specification (replaces Service Mode Protocol v2.2) |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
