# Saturday Service Mode Protocol

**Version:** 2.2.0
**Last Updated:** 2026-01-14
**Audience:** Saturday Admin App developers, Firmware engineers

---

## Overview

This document defines the **Service Mode Protocol** for Saturday devices. Service Mode provides a standardized serial interface for factory provisioning, device testing, diagnostics, and servicing of all Saturday hardware products.

This is the **canonical reference** for all service mode commands, fields, and behaviors across all Saturday devices. Device-specific capabilities are documented here with notes on which devices support them.

### Key Concepts

- **Service Mode**: A device state where the unit accepts commands via USB serial for provisioning, testing, and maintenance
- **Standard Mode**: Normal device operation (customer-facing functionality)
- **Fresh Device**: A device with no `unit_id` stored (never provisioned)
- **Provisioned Device**: A device with a `unit_id` stored (has been through factory provisioning)
- **unit_id**: The device serial number - the core identifier linking the physical device to inventory

### Design Principles

1. **Device-Agnostic**: This protocol applies to all Saturday hardware (Hub, Speaker, etc.)
2. **Secure by Default**: End users cannot accidentally trigger service operations
3. **Factory & Service Friendly**: Technicians can easily access service mode on any device
4. **Explicit Entry/Exit**: Service mode requires explicit commands to enter and exit
5. **Backend-Agnostic**: Protocol does not assume specific cloud providers or connectivity methods
6. **Capability-Driven**: Devices declare what they support via a Service Mode Manifest

---

## Service Mode Entry

### Fresh Device (First Boot)

A device with no `unit_id` stored automatically enters service mode on boot and remains there until explicitly exited via `exit_service_mode` command.

```
Power on → No unit_id? → Enter Service Mode → Wait for commands
```

### Provisioned Device (Service Entry)

A provisioned device briefly listens for the `enter_service_mode` command at boot. This allows technicians to access service mode on devices returned for repair or diagnostics.

```
Power on → Has unit_id → Listen for enter_service_mode (10 seconds)
                                    ↓                    ↓
                             Command received      Timeout (no command)
                                    ↓                    ↓
                            Enter Service Mode     Continue to Standard Mode
```

**Entry Window:** The device listens for `enter_service_mode` for **10 seconds** after boot. The Admin app should begin sending this command immediately upon detecting a device connection (port open).

**Implementation Note:** The Admin app should send `enter_service_mode` repeatedly (e.g., every 200ms) until it receives a response or times out. This accounts for USB enumeration delay and ensures the command is received within the window.

**Why This Works:** End users typically connect devices to power-only USB cables or wall adapters. Even if connected to a computer, no software sends the entry command, so the device proceeds to standard operation after the 10-second window.

**Trade-off:** The device cannot enter standard mode until the service mode window expires. A 10-second boot delay is acceptable for Saturday devices which typically stay powered on continuously and are not time-critical at startup.

---

## Connection Parameters

| Parameter | Value |
|-----------|-------|
| Interface | USB Serial (CDC ACM) |
| Baud Rate | 115200 |
| Data Bits | 8 |
| Parity | None |
| Stop Bits | 1 |
| Flow Control | None |

The device appears as a standard USB serial device when connected via data-capable USB-C cable.

---

## Message Format

All messages are JSON objects terminated by a newline character (`\n`).

### Device → Host Messages

```json
{"status": "<status>", "message": "<optional message>", "data": {...}}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | string | Yes | Status code (see below) |
| `message` | string | No | Human-readable message |
| `data` | object | No | Additional response data |

**Status Codes:**

| Status | Description |
|--------|-------------|
| `ok` | Command succeeded |
| `error` | Command failed |
| `service_mode` | Device is in service mode (periodic beacon) |
| `provisioned` | Provisioning completed successfully |
| `failed` | Test(s) failed |

### Host → Device Messages

```json
{"cmd": "<command>", "data": {...}}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `cmd` | string | Yes | Command name |
| `data` | object | No | Command parameters |

---

## Commands Reference

All commands are documented here. Devices only respond to commands they support. Unsupported commands return an `unsupported_command` error.

### Mode Control

| Command | Description | Support |
|---------|-------------|---------|
| `enter_service_mode` | Enter service mode (only valid during boot window) | All devices |
| `exit_service_mode` | Exit service mode and continue to standard operation | All devices |
| `reboot` | Reboot the device | All devices |

### Status & Diagnostics

| Command | Description | Support |
|---------|-------------|---------|
| `get_status` | Get device status, config state, and test results | All devices |
| `get_manifest` | Get the device's Service Mode Manifest | All devices |

### Provisioning

| Command | Description | Support |
|---------|-------------|---------|
| `provision` | Store unit_id and cloud credentials | All devices |

### Testing

| Command | Description | Support |
|---------|-------------|---------|
| `test_wifi` | Test Wi-Fi connectivity | Devices with Wi-Fi |
| `test_bluetooth` | Test Bluetooth functionality | Devices with Bluetooth |
| `test_thread` | Test Thread connectivity | Devices with Thread |
| `test_cloud` | Test cloud API connectivity | Devices with cloud connectivity |
| `test_rfid` | Test RFID tag scanning | Devices with RFID |
| `test_audio` | Test audio output | Devices with audio |
| `test_display` | Test display output | Devices with display |
| `test_led` | Test LED strip output | Devices with addressable LEDs |
| `test_motion` | Test motion sensor input | Devices with accelerometer |
| `test_environment` | Test temperature/humidity sensor | Devices with environmental sensor |
| `test_button` | Test button input | Devices with buttons |
| `test_all` | Run all supported tests | All devices |

### Reset Operations

| Command | Description | Support |
|---------|-------------|---------|
| `customer_reset` | Clear user data, preserve unit_id and cloud config | All devices |
| `factory_reset` | Full wipe of ALL data including unit_id | All devices |

---

## Command Details

### enter_service_mode

Enter service mode on a provisioned device. Only valid during the 10-second boot window.

**Request:**
```json
{"cmd": "enter_service_mode"}
```

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Entered service mode"
}
```

**Response (Outside Window):**
```json
{
  "status": "error",
  "message": "Service mode entry window expired",
  "data": {"error_code": "window_expired"}
}
```

After entering service mode, the device begins sending periodic status beacons.

---

### exit_service_mode

Exit service mode and continue to standard operation. Does not reboot.

**Request:**
```json
{"cmd": "exit_service_mode"}
```

**Response:**
```json
{
  "status": "ok",
  "message": "Exiting service mode"
}
```

**Prerequisites:**
- Device must have `unit_id` configured (either fresh provision or previously provisioned)

**Response (Not Provisioned):**
```json
{
  "status": "error",
  "message": "Cannot exit service mode - device not provisioned",
  "data": {"error_code": "not_provisioned"}
}
```

---

### get_status

Get current device status and configuration. Returns all fields the device supports.

**Request:**
```json
{"cmd": "get_status"}
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "device_type": "hub",
    "firmware_version": "0.6.0",
    "mac_address": "AA:BB:CC:DD:EE:FF",
    "unit_id": "SV-HUB-000001",
    "cloud_configured": true,
    "wifi_configured": true,
    "wifi_connected": false,
    "free_heap": 245760,
    "uptime_ms": 12345,
    "last_tests": {
      "wifi_ok": true,
      "cloud_ok": true,
      "rfid_ok": true
    }
  }
}
```

**All Possible Fields:**

Fields are only present if the device supports that capability.

| Field | Type | Description | Support |
|-------|------|-------------|---------|
| `device_type` | string | Device type identifier (e.g., "hub", "speaker") | All devices |
| `firmware_version` | string | Current firmware version | All devices |
| `mac_address` | string | Primary MAC address (unique hardware ID) | All devices |
| `unit_id` | string | Unit serial number (only if provisioned) | All devices |
| `cloud_configured` | boolean | Whether cloud credentials are stored | Devices with cloud |
| `cloud_url` | string | Configured cloud endpoint (only if configured) | Devices with cloud |
| `wifi_configured` | boolean | Whether Wi-Fi credentials are stored | Devices with Wi-Fi |
| `wifi_connected` | boolean | Current Wi-Fi connection state | Devices with Wi-Fi |
| `wifi_ssid` | string | Connected SSID (only if connected) | Devices with Wi-Fi |
| `wifi_rssi` | number | Signal strength in dBm (only if connected) | Devices with Wi-Fi |
| `ip_address` | string | IP address (only if connected) | Devices with IP networking |
| `bluetooth_enabled` | boolean | Bluetooth enabled state | Devices with Bluetooth |
| `thread_configured` | boolean | Thread network configured | Devices with Thread |
| `thread_connected` | boolean | Thread network connected | Devices with Thread |
| `thread` | object | Thread network credentials (see below) | Devices with Thread (Border Router) |
| `free_heap` | number | Free heap memory in bytes | All devices |
| `uptime_ms` | number | Milliseconds since boot | All devices |
| `last_tests` | object | Results from last test run | All devices |
| `battery_level` | number | Battery percentage (0-100) | Battery-powered devices |
| `battery_charging` | boolean | Currently charging | Battery-powered devices |

**Thread Credentials Object (`thread`):**

For devices acting as Thread Border Routers (e.g., Saturday Hub), the `thread` field contains the network credentials generated on first boot. These credentials must be captured during factory provisioning and uploaded to the cloud so the mobile app can provision other devices (e.g., crates) to join the Thread network.

| Field | Type | Description |
|-------|------|-------------|
| `network_name` | string | Thread network name (max 16 chars) |
| `pan_id` | number | 16-bit PAN ID |
| `channel` | number | Radio channel (11-26) |
| `network_key` | string | 32-char hex string (128-bit master key) |
| `extended_pan_id` | string | 16-char hex string (64-bit extended PAN ID) |
| `mesh_local_prefix` | string | 16-char hex string (64-bit mesh-local prefix) |
| `pskc` | string | 32-char hex string (Pre-Shared Key for Commissioner) |

Example `thread` object:
```json
{
  "thread": {
    "network_name": "SaturdayVinyl",
    "pan_id": 21334,
    "channel": 15,
    "network_key": "a1b2c3d4e5f6789012345678abcdef12",
    "extended_pan_id": "0123456789abcdef",
    "mesh_local_prefix": "fd00000000000000",
    "pskc": "fedcba9876543210fedcba9876543210"
  }
}
```

If Thread is not yet initialized, `thread` will be `null`.

---

### get_manifest

Get the device's Service Mode Manifest describing its capabilities. See [Service Mode Manifest](#service-mode-manifest) section for details.

**Request:**
```json
{"cmd": "get_manifest"}
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "manifest_version": "1.0",
    "device_type": "hub",
    "device_name": "Saturday Vinyl Hub",
    "firmware_version": "0.6.0",
    "capabilities": {
      "wifi": true,
      "bluetooth": true,
      "thread": false,
      "cloud": true,
      "rfid": true,
      "audio": false,
      "display": false,
      "battery": false
    },
    "provisioning_fields": {
      "required": ["unit_id", "cloud_url", "cloud_anon_key"],
      "optional": ["cloud_device_secret"]
    },
    "supported_tests": ["wifi", "cloud", "rfid", "bluetooth"],
    "custom_commands": []
  }
}
```

---

### provision

Store unit credentials. This is the primary provisioning command. The `unit_id` (serial number) is the core required field.

**Request:**
```json
{
  "cmd": "provision",
  "data": {
    "unit_id": "SV-HUB-000001",
    "cloud_url": "https://xxx.supabase.co",
    "cloud_anon_key": "eyJ...",
    "cloud_device_secret": "optional-secret"
  }
}
```

**Standard Fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `unit_id` | string | **Yes** | Unique unit serial number from production database |
| `cloud_url` | string | Conditional | Cloud API endpoint URL (required if device has cloud capability) |
| `cloud_anon_key` | string | Conditional | Cloud API public key (required if device has cloud capability) |
| `cloud_device_secret` | string | No | Device-specific secret for authentication |

Devices may define additional provisioning fields in their manifest.

**Response (Success):**
```json
{
  "status": "provisioned",
  "message": "Device provisioned successfully",
  "data": {
    "unit_id": "SV-HUB-000001",
    "cloud_stored": true
  }
}
```

**Response (Error):**
```json
{
  "status": "error",
  "message": "Required: unit_id",
  "data": {"error_code": "missing_fields"}
}
```

---

### test_wifi

Test Wi-Fi connectivity. Credentials can be provided inline or use stored credentials.

**Support:** Devices with Wi-Fi capability

**Request (use stored credentials):**
```json
{"cmd": "test_wifi"}
```

**Request (with credentials):**
```json
{
  "cmd": "test_wifi",
  "data": {
    "ssid": "TestNetwork",
    "password": "TestPassword123"
  }
}
```

If credentials are provided, they are stored before testing.

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Wi-Fi connected",
  "data": {
    "connected": true,
    "ssid": "TestNetwork",
    "ip": "192.168.1.100",
    "rssi": -55
  }
}
```

**Response (Timeout):**
```json
{
  "status": "error",
  "message": "Wi-Fi connection timed out",
  "data": {"error_code": "wifi_timeout"}
}
```

**Response (No Credentials):**
```json
{
  "status": "error",
  "message": "No Wi-Fi credentials stored - provision device first",
  "data": {"error_code": "no_credentials"}
}
```

**Response (Wi-Fi Not Ready):**
```json
{
  "status": "error",
  "message": "Wi-Fi subsystem not ready - try again",
  "data": {"error_code": "wifi_not_ready"}
}
```

**Response (Invalid Credentials):**
```json
{
  "status": "error",
  "message": "Invalid Wi-Fi credentials format",
  "data": {"error_code": "invalid_credentials"}
}
```

**Response (Init Failed):**
```json
{
  "status": "error",
  "message": "Failed to initialize Wi-Fi",
  "data": {"error_code": "wifi_init_failed"}
}
```

**Response (Connect Failed):**
```json
{
  "status": "error",
  "message": "Wi-Fi connect failed: <error_name>",
  "data": {"error_code": "connect_failed"}
}
```

**Response (Not Supported):**
```json
{
  "status": "error",
  "message": "Wi-Fi not supported on this device",
  "data": {"error_code": "unsupported_command"}
}
```

---

### test_bluetooth

Test Bluetooth functionality by performing a scan or advertising test.

**Support:** Devices with Bluetooth capability

**Request:**
```json
{"cmd": "test_bluetooth"}
```

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Bluetooth test passed",
  "data": {
    "ble_enabled": true,
    "devices_found": 3,
    "advertising": true
  }
}
```

---

### test_thread

Test Thread network connectivity.

**Support:** Devices with Thread capability

**Request:**
```json
{"cmd": "test_thread"}
```

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Thread connected",
  "data": {
    "connected": true,
    "network_name": "SaturdayThread",
    "role": "router"
  }
}
```

---

### test_cloud

Test cloud API connectivity by sending a test request. Requires network connectivity (Wi-Fi, Thread, etc.) to be established first.

**Support:** Devices with cloud capability

**Request:**
```json
{"cmd": "test_cloud"}
```

**Prerequisites:**
- Device must be provisioned (cloud credentials stored)
- Network must be connected (Wi-Fi, Thread, etc.)

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Cloud connection successful",
  "data": {
    "status_code": 201,
    "latency_ms": 245,
    "unit_id": "SV-HUB-000001"
  }
}
```

**Response (Not Configured):**
```json
{
  "status": "error",
  "message": "Cloud not configured - run provision first",
  "data": {"error_code": "not_configured"}
}
```

**Response (No Network):**
```json
{
  "status": "error",
  "message": "No network connection - run test_wifi or test_thread first",
  "data": {"error_code": "no_network"}
}
```

---

### test_rfid

Test RFID tag scanning by scanning for tags over a defined period.

**Support:** Devices with RFID capability

**Request:**
```json
{"cmd": "test_rfid"}
```

**Response (Success - Tags Found):**
```json
{
  "status": "ok",
  "message": "RFID scan complete",
  "data": {
    "module_firmware": "YRM100-V2.1",
    "tags_found": 2,
    "last_epc": "E280116060000209..."
  }
}
```

**Response (Success - No Tags):**
```json
{
  "status": "ok",
  "message": "RFID working but no tags found",
  "data": {
    "module_firmware": "YRM100-V2.1",
    "tags_found": 0
  }
}
```

**Response (Module Error):**
```json
{
  "status": "error",
  "message": "RFID module not responding",
  "data": {"error_code": "rfid_comm_failed"}
}
```

---

### test_audio

Test audio output by playing a test tone or sound.

**Support:** Devices with audio capability

**Request:**
```json
{"cmd": "test_audio"}
```

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Audio test complete",
  "data": {
    "codec": "ES8388",
    "sample_rate": 44100,
    "channels": 2
  }
}
```

---

### test_display

Test display output by showing a test pattern.

**Support:** Devices with display capability

**Request:**
```json
{"cmd": "test_display"}
```

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Display test complete",
  "data": {
    "type": "OLED",
    "resolution": "128x64",
    "driver": "SSD1306"
  }
}
```

---

### test_led

Test addressable LED strip functionality by cycling through colors.

**Support:** Devices with addressable LED capability

**Request:**
```json
{"cmd": "test_led"}
```

The device cycles through a color sequence (red, green, blue, white) on the LED strip to verify all LEDs are functioning.

**Response (Success):**
```json
{
  "status": "ok",
  "message": "LED test complete",
  "data": {
    "led_count": 8,
    "type": "SK6812"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `led_count` | number | Number of LEDs in the strip |
| `type` | string | LED type (e.g., "SK6812", "WS2812B") |

**Response (Error):**
```json
{
  "status": "error",
  "message": "LED strip not responding",
  "data": {"error_code": "led_comm_failed"}
}
```

---

### test_motion

Test motion sensor (accelerometer) by waiting for movement detection.

**Support:** Devices with accelerometer/motion sensor capability

**Request:**
```json
{"cmd": "test_motion"}
```

The device waits for the accelerometer to detect motion (with timeout). The technician should physically move or tilt the device to trigger the sensor.

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Motion detected",
  "data": {
    "sensor_type": "LIS2DH12",
    "triggered": true,
    "wait_time_ms": 1250
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `sensor_type` | string | Accelerometer model (e.g., "LIS2DH12") |
| `triggered` | boolean | Whether motion was detected |
| `wait_time_ms` | number | Time waited before motion was detected |

**Response (Timeout):**
```json
{
  "status": "error",
  "message": "No motion detected within timeout",
  "data": {"error_code": "motion_timeout"}
}
```

**Response (Sensor Error):**
```json
{
  "status": "error",
  "message": "Motion sensor not responding",
  "data": {"error_code": "motion_comm_failed"}
}
```

**Timeout:** Default 30 seconds. Technician should move the device during this window.

---

### test_environment

Test temperature and humidity sensor by reading current environmental conditions.

**Support:** Devices with environmental sensor capability

**Request:**
```json
{"cmd": "test_environment"}
```

The device reads the current temperature and humidity from the sensor.

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Environment sensor test complete",
  "data": {
    "sensor_type": "SHT40",
    "temperature_c": 21.5,
    "temperature_f": 70.7,
    "humidity_pct": 48.2,
    "in_safe_range": true
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `sensor_type` | string | Sensor model (e.g., "SHT40", "SHT31") |
| `temperature_c` | number | Temperature in Celsius |
| `temperature_f` | number | Temperature in Fahrenheit |
| `humidity_pct` | number | Relative humidity percentage |
| `in_safe_range` | boolean | Whether conditions are safe for vinyl storage |

**Response (Warning - Outside Safe Range):**
```json
{
  "status": "ok",
  "message": "Environment sensor working - conditions outside safe range",
  "data": {
    "sensor_type": "SHT40",
    "temperature_c": 28.5,
    "temperature_f": 83.3,
    "humidity_pct": 65.0,
    "in_safe_range": false,
    "warnings": ["temperature_high", "humidity_high"]
  }
}
```

**Response (Sensor Error):**
```json
{
  "status": "error",
  "message": "Environment sensor not responding",
  "data": {"error_code": "environment_comm_failed"}
}
```

**Safe Range Reference:**

| Condition | Safe Range | Warning Threshold |
|-----------|------------|-------------------|
| Temperature | 18-21°C (65-70°F) | >24°C (75°F) or <15°C (60°F) |
| Humidity | 45-50% RH | >60% RH or <30% RH |

---

### test_button

Test button input by waiting for button press.

**Support:** Devices with button capability

**Request:**
```json
{"cmd": "test_button"}
```

The device waits for a button press (with timeout).

**Response (Success):**
```json
{
  "status": "ok",
  "message": "Button test passed",
  "data": {
    "button_pressed": true,
    "button_id": "main",
    "press_duration_ms": 150
  }
}
```

**Response (Timeout):**
```json
{
  "status": "error",
  "message": "No button press detected",
  "data": {"error_code": "button_timeout"}
}
```

---

### test_all

Run all supported tests in sequence.

**Support:** All devices

**Request:**
```json
{"cmd": "test_all"}
```

**Request (with Wi-Fi credentials):**
```json
{
  "cmd": "test_all",
  "data": {
    "wifi_ssid": "TestNetwork",
    "wifi_password": "TestPassword123"
  }
}
```

**Response:**

Individual test responses are sent first, followed by a summary:

```json
{
  "status": "ok",
  "message": "All tests passed",
  "data": {
    "wifi_ok": true,
    "cloud_ok": true,
    "rfid_ok": true,
    "all_passed": true
  }
}
```

Or if tests failed:
```json
{
  "status": "failed",
  "message": "Some tests failed",
  "data": {
    "wifi_ok": true,
    "cloud_ok": false,
    "rfid_ok": true,
    "all_passed": false
  }
}
```

The `data` object contains results for each test the device supports.

---

### customer_reset

Clear user data but preserve factory provisioning. Use this to prepare a device for a new customer or to reset after testing.

**Support:** All devices

**Request:**
```json
{"cmd": "customer_reset"}
```

**Response:**
```json
{
  "status": "ok",
  "message": "Customer reset complete - device will reboot"
}
```

The device reboots after sending this response.

**Clears:**
- Wi-Fi credentials
- Bluetooth pairings
- User preferences
- Device-specific user data

**Preserves:**
- `unit_id` (serial number)
- Cloud URL and credentials
- Factory calibration data

---

### factory_reset

Complete factory reset - erases ALL data including `unit_id`. Use this for devices being returned to manufacturing for re-work or complete re-provisioning.

**Support:** All devices

**Request:**
```json
{"cmd": "factory_reset"}
```

**Response:**
```json
{
  "status": "ok",
  "message": "Factory reset complete - device will reboot"
}
```

The device reboots after sending this response. After reboot, the device will be in fresh state (no `unit_id`) and will automatically enter service mode.

**Clears:**
- **ALL NVS data**
- `unit_id` (serial number)
- Cloud credentials
- Wi-Fi credentials
- All device configuration

**Warning:** This removes the device's identity. It will need to be re-registered in inventory.

---

### reboot

Reboot the device without clearing any data.

**Support:** All devices

**Request:**
```json
{"cmd": "reboot"}
```

**Response:**
```json
{
  "status": "ok",
  "message": "Rebooting..."
}
```

---

## Status Beacon

When in service mode, the device sends a status beacon every 2 seconds:

```json
{
  "status": "service_mode",
  "data": {
    "device_type": "hub",
    "firmware_id": "550e8400-e29b-41d4-a716-446655440000",
    "firmware_version": "0.6.0",
    "mac_address": "AA:BB:CC:DD:EE:FF",
    "unit_id": "SV-HUB-000001",
    "cloud_configured": true,
    "free_heap": 245760
  }
}
```

The beacon includes relevant status fields for the device. A fresh device will have `unit_id: null` in the beacon.

This beacon serves multiple purposes:
1. Indicates the device is in service mode and ready for commands
2. Provides device identification (`mac_address`) and firmware info (`firmware_id`, `firmware_version`)
3. Shows current provisioning state at a glance (`unit_id`, `cloud_configured`)
4. Allows Admin app to look up firmware details from `firmware_versions` table via `firmware_id`

---

## Service Mode Manifest

Each device firmware must define a **Service Mode Manifest** - a machine-readable description of the device's service mode capabilities. This enables the Admin app to dynamically adapt its UI and behavior based on what the connected device supports.

### Manifest Schema

```json
{
  "manifest_version": "1.0",
  "device_type": "<string>",
  "device_name": "<string>",
  "firmware_id": "<uuid>",
  "firmware_version": "<string>",
  "capabilities": {
    "wifi": <boolean>,
    "bluetooth": <boolean>,
    "thread": <boolean>,
    "cloud": <boolean>,
    "rfid": <boolean>,
    "audio": <boolean>,
    "display": <boolean>,
    "battery": <boolean>,
    "button": <boolean>
  },
  "provisioning_fields": {
    "required": ["<field_name>", ...],
    "optional": ["<field_name>", ...]
  },
  "supported_tests": ["<test_name>", ...],
  "status_fields": ["<field_name>", ...],
  "custom_commands": [
    {
      "name": "<command_name>",
      "description": "<description>",
      "parameters": {...}
    }
  ],
  "led_patterns": {
    "<state>": {"color": "<color>", "pattern": "<pattern>"}
  }
}
```

### Manifest Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `manifest_version` | string | Yes | Manifest schema version (currently "1.0") |
| `device_type` | string | Yes | Device type identifier (e.g., "hub", "speaker") |
| `device_name` | string | Yes | Human-readable device name |
| `firmware_id` | uuid | Yes | UUID from `firmware_versions` table - allows Admin app to look up firmware details |
| `firmware_version` | string | Yes | Current firmware version (semver) |
| `capabilities` | object | Yes | Boolean flags for each hardware capability |
| `provisioning_fields` | object | Yes | Required and optional fields for `provision` command |
| `supported_tests` | array | Yes | List of test command suffixes this device supports |
| `status_fields` | array | Yes | List of fields returned by `get_status` |
| `custom_commands` | array | No | Device-specific commands not in standard protocol |
| `led_patterns` | object | No | LED behavior during service mode states |

### Standard Capabilities

| Capability | Description |
|------------|-------------|
| `wifi` | Device has Wi-Fi connectivity |
| `bluetooth` | Device has Bluetooth (BLE/Classic) |
| `thread` | Device has Thread/Matter connectivity |
| `cloud` | Device connects to cloud backend |
| `rfid` | Device has RFID reader |
| `audio` | Device has audio output |
| `display` | Device has visual display |
| `led` | Device has addressable LED strip |
| `motion` | Device has accelerometer/motion sensor |
| `environment` | Device has temperature/humidity sensor |
| `battery` | Device is battery-powered |
| `button` | Device has physical button(s) |

### Example: Saturday Hub Manifest

```json
{
  "manifest_version": "1.1",
  "device_type": "hub",
  "device_name": "Saturday Vinyl Hub",
  "firmware_id": "550e8400-e29b-41d4-a716-446655440000",
  "firmware_version": "0.8.0",
  "capabilities": {
    "wifi": true,
    "bluetooth": true,
    "thread": true,
    "cloud": true,
    "rfid": true,
    "audio": false,
    "display": false,
    "battery": false,
    "button": true
  },
  "provisioning_fields": {
    "required": ["unit_id", "cloud_url", "cloud_anon_key"],
    "optional": ["cloud_device_secret"]
  },
  "supported_tests": ["wifi", "cloud", "rfid"],
  "status_fields": [
    "device_type",
    "firmware_version",
    "mac_address",
    "unit_id",
    "cloud_configured",
    "cloud_url",
    "wifi_configured",
    "wifi_connected",
    "wifi_ssid",
    "wifi_rssi",
    "ip_address",
    "thread",
    "free_heap",
    "uptime_ms",
    "last_tests"
  ],
  "custom_commands": [],
  "led_patterns": {
    "service_awaiting": {"color": "white", "pattern": "pulse"},
    "processing": {"color": "yellow", "pattern": "pulse"},
    "testing": {"color": "yellow", "pattern": "blink_fast"},
    "success": {"color": "green", "pattern": "flash"},
    "error": {"color": "red", "pattern": "flash"},
    "resetting": {"color": "red", "pattern": "blink_fast"}
  }
}
```

### Example: Battery-Powered Speaker Manifest

```json
{
  "manifest_version": "1.0",
  "device_type": "speaker",
  "device_name": "Saturday Portable Speaker",
  "firmware_id": "660e8400-e29b-41d4-a716-446655440001",
  "firmware_version": "1.0.0",
  "capabilities": {
    "wifi": false,
    "bluetooth": true,
    "thread": false,
    "cloud": false,
    "rfid": false,
    "audio": true,
    "display": false,
    "battery": true,
    "button": true
  },
  "provisioning_fields": {
    "required": ["unit_id"],
    "optional": []
  },
  "supported_tests": ["bluetooth", "audio", "button"],
  "status_fields": [
    "device_type",
    "firmware_version",
    "mac_address",
    "unit_id",
    "bluetooth_enabled",
    "battery_level",
    "battery_charging",
    "free_heap",
    "uptime_ms",
    "last_tests"
  ],
  "custom_commands": [
    {
      "name": "set_volume",
      "description": "Set audio volume for testing",
      "parameters": {
        "level": {"type": "number", "min": 0, "max": 100, "required": true}
      }
    }
  ],
  "led_patterns": {}
}
```

### Using the Manifest

**Admin App Behavior:**

1. On device connection, call `get_manifest`
2. Cache manifest for the session
3. Show/hide UI elements based on `capabilities`
4. Validate `provision` data against `provisioning_fields`
5. Only show tests listed in `supported_tests`
6. Use `status_fields` to know what to display from `get_status`

### Firmware Implementation

The manifest is defined as a JSON file in the firmware project and embedded at compile time.

**Project Structure:**

```
components/
  service_mode/
    CMakeLists.txt
    include/
      service_mode.h
    service_mode.c
    service_manifest.json     ← Developer edits this file
```

**service_manifest.json:**

Create this file with your device's capabilities. The `firmware_id` is a UUID that must match a row in the `firmware_versions` table:

```json
{
  "manifest_version": "1.0",
  "device_type": "hub",
  "device_name": "Saturday Vinyl Hub",
  "firmware_id": "550e8400-e29b-41d4-a716-446655440000",
  "firmware_version": "0.6.0",
  "capabilities": {
    "wifi": true,
    "bluetooth": true,
    "thread": false,
    "cloud": true,
    "rfid": true,
    "audio": false,
    "display": false,
    "battery": false,
    "button": true
  },
  "provisioning_fields": {
    "required": ["unit_id", "cloud_url", "cloud_anon_key"],
    "optional": ["cloud_device_secret"]
  },
  "supported_tests": ["wifi", "bluetooth", "cloud", "rfid", "button"],
  "status_fields": [
    "device_type", "firmware_version", "mac_address", "unit_id",
    "cloud_configured", "wifi_configured", "wifi_connected",
    "free_heap", "uptime_ms", "last_tests"
  ],
  "custom_commands": [],
  "led_patterns": {
    "service_awaiting": {"color": "white", "pattern": "pulse"},
    "testing": {"color": "yellow", "pattern": "blink_fast"},
    "success": {"color": "green", "pattern": "flash"},
    "error": {"color": "red", "pattern": "flash"}
  }
}
```

**CMakeLists.txt:**

Use ESP-IDF's `EMBED_TXTFILES` to include the JSON at compile time:

```cmake
idf_component_register(
    SRCS "service_mode.c"
    INCLUDE_DIRS "include"
    EMBED_TXTFILES "service_manifest.json"
    REQUIRES nvs_flash driver cJSON
)
```

**Accessing the Manifest in Code:**

```c
/* The embedded file is available as a symbol */
extern const char service_manifest_json_start[] asm("_binary_service_manifest_json_start");
extern const char service_manifest_json_end[] asm("_binary_service_manifest_json_end");

static void handle_get_manifest(void)
{
    /* Calculate length (exclude null terminator if present) */
    size_t len = service_manifest_json_end - service_manifest_json_start;

    /* Send the raw JSON - it's already properly formatted */
    cJSON *root = cJSON_CreateObject();
    cJSON_AddStringToObject(root, "status", "ok");

    /* Parse and attach the manifest data */
    cJSON *manifest = cJSON_ParseWithLength(service_manifest_json_start, len);
    if (manifest) {
        cJSON_AddItemToObject(root, "data", manifest);
    }

    char *response = cJSON_PrintUnformatted(root);
    serial_send_json(response);

    cJSON_free(response);
    cJSON_Delete(root);
}
```

**Important Notes:**

1. **Firmware ID**: The `firmware_id` UUID must exist in the `firmware_versions` table before releasing the firmware. Create the database entry first, then copy the UUID into the manifest.
2. **Version Sync**: Update `firmware_version` in the manifest when you update `FIRMWARE_VERSION` in code
3. **Validation**: The manifest should accurately reflect device capabilities - don't claim capabilities the device doesn't have
4. **Keep Updated**: When adding new tests or status fields, update the manifest
5. **No Runtime Changes**: The manifest is read-only at runtime; it's baked into the firmware

---

## Error Codes

| Code | Description |
|------|-------------|
| `parse_error` | Invalid JSON received |
| `invalid_command` | Missing 'cmd' field |
| `unknown_command` | Unrecognized command |
| `unsupported_command` | Command not supported by this device |
| `missing_data` | Command requires data field |
| `missing_fields` | Required fields missing from data |
| `storage_error` | Failed to store data in NVS |
| `wifi_init_failed` | Wi-Fi initialization failed |
| `wifi_connect_failed` | Failed to start Wi-Fi connection |
| `wifi_timeout` | Wi-Fi connection timed out |
| `no_wifi_config` | No Wi-Fi credentials stored |
| `no_network` | No network connection available |
| `not_configured` | Cloud credentials not configured |
| `not_provisioned` | Device not provisioned (no unit_id) |
| `request_failed` | HTTP/network request failed |
| `window_expired` | Service mode entry window expired |
| `not_in_service_mode` | Command only valid in service mode |
| `rfid_comm_failed` | RFID module communication failed |
| `audio_failed` | Audio test failed |
| `button_timeout` | Button press not detected within timeout |
| `led_comm_failed` | LED strip communication failed |
| `motion_timeout` | Motion not detected within timeout |
| `motion_comm_failed` | Motion sensor communication failed |
| `environment_comm_failed` | Temperature/humidity sensor communication failed |

---

## Workflows

### Factory Provisioning (New Device)

```
1. Flash firmware to device
2. Connect device to computer via USB-C data cable
3. Device boots → No unit_id → Enters service mode automatically
4. Device sends beacon: {"status": "service_mode", ...}
5. Admin app opens serial port
6. Admin app sends: {"cmd": "get_manifest"}
7. Admin app sends: {"cmd": "get_status"}
8. Admin app generates unit_id, registers in inventory database
9. Admin app sends: {"cmd": "provision", "data": {...}}
10. Admin app sends: {"cmd": "test_all", "data": {"wifi_ssid": "...", ...}}
11. If all tests pass:
    Admin app sends: {"cmd": "customer_reset"}
12. Device reboots, ready for customer
```

### Service/Repair (Provisioned Device)

```
1. Connect device to computer via USB-C data cable
2. Device boots → Has unit_id → Listens for entry command (10 sec)
3. Admin app detects device connection, immediately starts sending:
   {"cmd": "enter_service_mode"} (repeat every 500ms)
4. Device enters service mode, sends beacon
5. Admin app sends: {"cmd": "get_manifest"}
6. Admin app sends: {"cmd": "get_status"}
7. Technician reviews device state (unit_id shown for inventory lookup)
8. Options:
   a. Run diagnostics: {"cmd": "test_all"}
   b. Re-provision: {"cmd": "provision", "data": {...}}
   c. Full wipe: {"cmd": "factory_reset"}
   d. Exit without changes: {"cmd": "exit_service_mode"}
```

### Customer Return to Factory State

```
1. Enter service mode (see above)
2. Admin app sends: {"cmd": "factory_reset"}
3. Device wipes ALL data including unit_id and reboots
4. Device is now fresh, ready for re-provisioning
5. Device will need new unit_id assigned in inventory
```

---

## Implementation Notes

### Console Output Filtering

The device outputs ESP-IDF log messages on the same serial port. Log lines have prefixes like `I (12345) TAG:`. The Admin app should:
1. Read complete lines (until `\n`)
2. Attempt JSON parse only on lines starting with `{`
3. Ignore non-JSON lines (log output)

### Timeout Recommendations

| Operation | Timeout |
|-----------|---------|
| Service mode entry window | 10 seconds |
| Status beacon poll | 5 seconds |
| Standard commands | 10 seconds |
| Wi-Fi test | 20 seconds |
| Cloud test | 15 seconds |
| RFID test | 10 seconds |
| Button test | 30 seconds |
| test_all | 90 seconds |

### LED Indicators

Devices with LEDs should provide visual feedback during service mode. Recommended patterns:

| State | LED Pattern |
|-------|-------------|
| Service mode (awaiting) | White pulse |
| Processing command | Yellow pulse |
| Test in progress | Yellow fast blink |
| Success | Green flash |
| Error | Red flash |
| Rebooting | Red fast blink |

Device-specific LED behaviors should be documented in the device's manifest.

---

## Device-Specific Documentation

For device-specific details beyond what's in the manifest:

- [Saturday Hub Provisioning Guide](hub_provisioning_guide.md) - Saturday Vinyl Hub with RFID
- (Future) Saturday Speaker Provisioning Guide

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.2.0 | 2026-01-14 | Added `test_led`, `test_motion`, and `test_environment` commands for Crate support; added `led`, `motion`, `environment` capabilities |
| 2.1.0 | 2026-01-05 | Added Service Mode Manifest, expanded test commands, renamed cloud commands, clarified reset behaviors, unit_id as core provisioning identifier |
| 2.0.0 | 2026-01-05 | Major rewrite: Service Mode architecture, explicit entry/exit, separate reset commands |
| 1.1.0 | 2026-01-04 | Added MAC address to status, updated for ESP32-C6 |
| 1.0.0 | 2026-01-03 | Initial protocol specification |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
