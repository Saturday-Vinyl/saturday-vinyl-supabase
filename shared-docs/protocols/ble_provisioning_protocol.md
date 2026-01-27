# Saturday Vinyl BLE Provisioning Protocol

**Version:** 1.1.0
**Status:** Draft
**Last Updated:** 2026-01-24
**Audience:** Saturday Vinyl app developers, firmware engineers

> **Note:** This protocol works with the unified device architecture. See
> [Device Command Protocol](device_command_protocol.md) for factory provisioning
> and [Capability Schema](../schemas/capability_schema.md) for attribute formats.

---

## Table of Contents

1. [Overview](#overview)
2. [Device Discovery](#device-discovery)
3. [Service Architecture](#service-architecture)
4. [Characteristics Reference](#characteristics-reference)
5. [Provisioning Flow](#provisioning-flow)
6. [Status Codes](#status-codes)
7. [Commands](#commands)
8. [Error Handling](#error-handling)
9. [Security Considerations](#security-considerations)
10. [Device Type Extensions](#device-type-extensions)
11. [Implementation Examples](#implementation-examples)
12. [Appendix](#appendix)

---

## Overview

### Purpose

The Saturday Vinyl BLE Provisioning Protocol defines a standard interface for mobile applications to configure Saturday Vinyl devices over Bluetooth Low Energy (BLE). This protocol is designed to be:

- **Device-agnostic** - Works with Hubs, Crates, and future devices
- **Extensible** - New characteristics can be added without breaking compatibility
- **Secure** - Supports optional pairing and encrypted communication
- **User-friendly** - Clear status feedback for mobile app UI

### Supported Devices

| Device | Provisioning Needs | Connectivity |
|--------|-------------------|--------------|
| **Hub** | Wi-Fi credentials, user linking | Wi-Fi → Cloud |
| **Crate** | Thread network credentials | Thread → Hub → Cloud |
| **Future devices** | TBD | Various |

### Protocol Layers

```
┌─────────────────────────────────────────────────┐
│             Saturday Mobile App                  │
├─────────────────────────────────────────────────┤
│      Saturday BLE Provisioning Protocol          │  ← This document
├─────────────────────────────────────────────────┤
│              BLE GATT Profile                    │
├─────────────────────────────────────────────────┤
│         Bluetooth Low Energy (BLE)               │
└─────────────────────────────────────────────────┘
```

---

## Device Discovery

### Advertising

Saturday devices advertise with the following characteristics:

#### Local Name Format

```
Saturday <DeviceType> <Identifier>
```

| Component | Description | Example |
|-----------|-------------|---------|
| `Saturday` | Brand prefix | "Saturday" |
| `DeviceType` | Device type | "Hub", "Crate" |
| `Identifier` | Last 4 chars of unit_id or MAC | "A1B2", "F3E4" |

**Examples:**
- `Saturday Hub A1B2`
- `Saturday Crate F3E4`

#### Advertising Data

| Field | Value |
|-------|-------|
| Flags | `0x06` (LE General Discoverable, BR/EDR Not Supported) |
| Complete Local Name | "Saturday Hub XXXX" |
| Complete List of 16-bit Service UUIDs | `0x5356` |

#### Scan Response (Optional)

| Field | Value |
|-------|-------|
| Manufacturer Specific Data | Company ID + Device Info (see below) |

**Manufacturer Data Format:**
```
Byte 0-1: Company ID (TBD - apply to Bluetooth SIG or use 0xFFFF for testing)
Byte 2:   Device Type (0x01=Hub, 0x02=Crate, etc.)
Byte 3:   Protocol Version (0x01 for v1.0)
Byte 4:   Status Flags (bit 0: needs provisioning, bit 1: has Wi-Fi, etc.)
```

### Filtering Devices

Apps should filter discovered devices by:

1. **Service UUID** - Must advertise `0x5356` service UUID
2. **Name prefix** - Must start with "Saturday "
3. **Optional:** Manufacturer data validation

```swift
// iOS Example
let saturdayServiceUUID = CBUUID(string: "5356")
centralManager.scanForPeripherals(withServices: [saturdayServiceUUID])
```

```kotlin
// Android Example
val filter = ScanFilter.Builder()
    .setServiceUuid(ParcelUuid.fromString("00005356-0000-1000-8000-00805f9b34fb"))
    .build()
```

---

## Service Architecture

### UUID Structure

Saturday Vinyl uses a custom 128-bit UUID base with the "SV" prefix:

```
Base UUID: 5356XXXX-0001-1000-8000-00805f9b34fb
           ^^^^
           "SV" in hex (0x53 = 'S', 0x56 = 'V')
```

The `XXXX` portion identifies specific characteristics.

### Service Definition

**Saturday Provisioning Service**

| Attribute | UUID | Description |
|-----------|------|-------------|
| Service | `53560000-0001-1000-8000-00805f9b34fb` | Primary provisioning service |

### Characteristics Overview

| Characteristic | Short UUID | Full UUID | Properties |
|----------------|------------|-----------|------------|
| Device Info | `0x0001` | `53560001-0001-1000-8000-00805f9b34fb` | Read |
| Status | `0x0002` | `53560002-0001-1000-8000-00805f9b34fb` | Read, Notify |
| Command | `0x0003` | `53560003-0001-1000-8000-00805f9b34fb` | Write |
| Response | `0x0004` | `53560004-0001-1000-8000-00805f9b34fb` | Read, Notify |
| Wi-Fi SSID | `0x0010` | `53560010-0001-1000-8000-00805f9b34fb` | Write |
| Wi-Fi Password | `0x0011` | `53560011-0001-1000-8000-00805f9b34fb` | Write |
| Thread Dataset | `0x0020` | `53560020-0001-1000-8000-00805f9b34fb` | Write |
| User Token | `0x0030` | `53560030-0001-1000-8000-00805f9b34fb` | Write |

**UUID Ranges (Reserved):**

| Range | Purpose |
|-------|---------|
| `0x0001-0x000F` | Core characteristics (all devices) |
| `0x0010-0x001F` | Wi-Fi provisioning |
| `0x0020-0x002F` | Thread provisioning |
| `0x0030-0x003F` | User/account linking |
| `0x0040-0x004F` | Device configuration |
| `0x0050-0x00FF` | Reserved for future use |
| `0x0100-0xFFFF` | Device-specific extensions |

---

## Characteristics Reference

### Device Info (0x0001)

**Properties:** Read
**Description:** Static device information. Read once after connection.

**Format:** JSON string (UTF-8)

```json
{
  "device_type": "hub",
  "serial_number": "SV-HUB-000123",
  "mac_address": "AA:BB:CC:DD:EE:FF",
  "firmware_version": "1.2.0",
  "protocol_version": "1.1",
  "capabilities": ["wifi", "thread_br", "rfid"],
  "needs_provisioning": true,
  "has_wifi": false,
  "has_thread": false
}
```

| Field | Type | Description |
|-------|------|-------------|
| `device_type` | string | Device type identifier |
| `serial_number` | string | Unit serial number (was `unit_id` in v1.0) |
| `mac_address` | string | Primary hardware MAC address |
| `firmware_version` | string | Semantic version of firmware |
| `protocol_version` | string | BLE protocol version |
| `capabilities` | string[] | Supported capability names |
| `needs_provisioning` | boolean | Whether device needs consumer setup |
| `has_wifi` | boolean | Wi-Fi credentials configured |
| `has_thread` | boolean | Thread credentials configured |

> **Migration Note:** The `unit_id` field has been renamed to `serial_number` in v1.1
> to align with the unified device architecture. Consumer apps should check for
> both fields for backwards compatibility.

**Capability Values:**

| Capability | Description |
|------------|-------------|
| `wifi` | Device supports Wi-Fi connectivity |
| `thread` | Device supports Thread connectivity |
| `thread_br` | Device is a Thread Border Router |
| `rfid` | Device has RFID reader |
| `battery` | Device is battery-powered |

### Status (0x0002)

**Properties:** Read, Notify
**Description:** Current provisioning status. Subscribe for real-time updates.

**Format:** Single byte status code

| Value | Name | Description |
|-------|------|-------------|
| `0x00` | `IDLE` | Not in provisioning mode |
| `0x01` | `READY` | Ready to receive credentials |
| `0x02` | `CREDENTIALS_RECEIVED` | Credentials written, awaiting command |
| `0x03` | `CONNECTING` | Attempting network connection |
| `0x04` | `VERIFYING` | Verifying cloud connectivity |
| `0x05` | `SUCCESS` | Provisioning complete |
| `0x10` | `ERROR_INVALID_SSID` | SSID validation failed |
| `0x11` | `ERROR_INVALID_PASSWORD` | Password validation failed |
| `0x12` | `ERROR_WIFI_FAILED` | Wi-Fi connection failed |
| `0x13` | `ERROR_WIFI_TIMEOUT` | Wi-Fi connection timeout |
| `0x14` | `ERROR_THREAD_FAILED` | Thread join failed |
| `0x15` | `ERROR_CLOUD_FAILED` | Cloud verification failed |
| `0x1E` | `ERROR_BUSY` | Device busy, try again |
| `0x1F` | `ERROR_UNKNOWN` | Unknown error |

### Command (0x0003)

**Properties:** Write
**Description:** Send commands to the device.

**Format:** Command byte followed by optional parameters

| Command | Value | Parameters | Description |
|---------|-------|------------|-------------|
| `CONNECT` | `0x01` | None | Attempt connection with stored credentials |
| `RESET` | `0x02` | None | Clear stored credentials |
| `GET_STATUS` | `0x03` | None | Request current status |
| `SCAN_WIFI` | `0x04` | None | Scan for Wi-Fi networks (if supported) |
| `ABORT` | `0x05` | None | Abort current operation |
| `FACTORY_RESET` | `0xFF` | Confirmation code | Full factory reset |

**Factory Reset Confirmation:**
To prevent accidental resets, the `FACTORY_RESET` command requires a 4-byte confirmation code: `0x52 0x45 0x53 0x54` ("REST" in ASCII).

```
Write: [0xFF, 0x52, 0x45, 0x53, 0x54]
```

### Response (0x0004)

**Properties:** Read, Notify
**Description:** Human-readable response messages and structured data.

**Format:** JSON string (UTF-8)

```json
{
  "type": "message",
  "code": "SUCCESS",
  "message": "Connected to MyNetwork"
}
```

**Response Types:**

| Type | Description |
|------|-------------|
| `message` | Status message for display |
| `wifi_scan` | Wi-Fi scan results |
| `error` | Error details |
| `progress` | Operation progress |

**Wi-Fi Scan Response Example:**
```json
{
  "type": "wifi_scan",
  "networks": [
    {"ssid": "HomeNetwork", "rssi": -45, "secure": true},
    {"ssid": "GuestNetwork", "rssi": -67, "secure": true},
    {"ssid": "OpenNetwork", "rssi": -72, "secure": false}
  ]
}
```

### Wi-Fi SSID (0x0010)

**Properties:** Write
**Description:** Wi-Fi network name to connect to.

**Format:** UTF-8 string, max 32 bytes

**Validation:**
- Length: 1-32 bytes
- Characters: Printable ASCII recommended

### Wi-Fi Password (0x0011)

**Properties:** Write
**Description:** Wi-Fi network password.

**Format:** UTF-8 string, max 64 bytes

**Validation:**
- Length: 0-64 bytes (0 for open networks)
- WPA2: Minimum 8 characters recommended

### Thread Dataset (0x0020)

**Properties:** Write
**Description:** Thread network operational dataset (for Crates and Thread devices).

**Format:** Binary Thread Operational Dataset TLV format

See [Thread 1.3.0 Specification](https://www.threadgroup.org/) for dataset format.

**Simplified JSON Alternative:**
For easier integration, devices may accept JSON format:

```json
{
  "network_name": "SaturdayVinyl",
  "pan_id": "0x5356",
  "channel": 15,
  "network_key": "base64-encoded-key"
}
```

### User Token (0x0030)

**Properties:** Write
**Description:** Authentication token for linking device to user account.

**Format:** UTF-8 string (typically JWT or opaque token)

**Usage:**
1. App authenticates user with Saturday backend
2. Backend issues device linking token
3. App writes token to device
4. Device sends token to cloud for account linking

---

## Provisioning Flow

### Hub Provisioning (Wi-Fi)

```
┌─────────────┐                              ┌─────────────┐
│  Mobile App │                              │  Saturday   │
│             │                              │    Hub      │
└──────┬──────┘                              └──────┬──────┘
       │                                            │
       │  1. Scan for Saturday devices              │
       │────────────────────────────────────────────>
       │                                            │
       │  2. Connect to "Saturday Hub XXXX"         │
       │<───────────────────────────────────────────│
       │                                            │
       │  3. Discover services                      │
       │────────────────────────────────────────────>
       │                                            │
       │  4. Read Device Info (0x0001)              │
       │────────────────────────────────────────────>
       │  {"device_type":"hub","capabilities":...}  │
       │<───────────────────────────────────────────│
       │                                            │
       │  5. Subscribe to Status (0x0002)           │
       │────────────────────────────────────────────>
       │                                            │
       │  6. Subscribe to Response (0x0004)         │
       │────────────────────────────────────────────>
       │                                            │
       │  7. Write Wi-Fi SSID (0x0010)              │
       │  "MyHomeNetwork"                           │
       │────────────────────────────────────────────>
       │                                            │
       │  8. Write Wi-Fi Password (0x0011)          │
       │  "mypassword123"                           │
       │────────────────────────────────────────────>
       │                                            │
       │  9. Status Notification: CREDENTIALS_RX    │
       │<───────────────────────────────────────────│
       │                                            │
       │  10. Write Command: CONNECT (0x01)         │
       │────────────────────────────────────────────>
       │                                            │
       │  11. Status Notification: CONNECTING       │
       │<───────────────────────────────────────────│
       │                                            │
       │  12. Response: "Connecting to Wi-Fi..."    │
       │<───────────────────────────────────────────│
       │                                            │
       │      [Hub connects to Wi-Fi]               │
       │                                            │
       │  13. Status Notification: VERIFYING        │
       │<───────────────────────────────────────────│
       │                                            │
       │  14. Response: "Verifying cloud..."        │
       │<───────────────────────────────────────────│
       │                                            │
       │      [Hub verifies cloud connectivity]     │
       │                                            │
       │  15. Status Notification: SUCCESS          │
       │<───────────────────────────────────────────│
       │                                            │
       │  16. Response: "Connected!"                │
       │<───────────────────────────────────────────│
       │                                            │
       │  17. Disconnect BLE                        │
       │────────────────────────────────────────────>
       │                                            │
```

### Crate Provisioning (Thread)

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  Mobile App │         │  Saturday   │         │  Saturday   │
│             │         │    Hub      │         │   Crate     │
└──────┬──────┘         └──────┬──────┘         └──────┬──────┘
       │                       │                       │
       │  1. Request Thread    │                       │
       │     credentials       │                       │
       │──────────────────────>│                       │
       │                       │                       │
       │  2. Thread dataset    │                       │
       │<──────────────────────│                       │
       │                       │                       │
       │  3. Connect to Crate via BLE                  │
       │───────────────────────────────────────────────>
       │                       │                       │
       │  4. Write Thread Dataset (0x0020)             │
       │───────────────────────────────────────────────>
       │                       │                       │
       │  5. Write CONNECT command                     │
       │───────────────────────────────────────────────>
       │                       │                       │
       │                       │  6. Join Thread       │
       │                       │<──────────────────────│
       │                       │                       │
       │  7. Status: SUCCESS                           │
       │<──────────────────────────────────────────────│
       │                       │                       │
```

### Re-provisioning Flow

Users may need to change Wi-Fi networks. The flow is identical, but:

1. Button long-press triggers BLE advertising on provisioned devices
2. App detects device is already provisioned via Device Info
3. App shows "Update Network" UI instead of initial setup
4. CONNECT command replaces existing credentials

---

## Status Codes

### Status Code Categories

| Range | Category |
|-------|----------|
| `0x00-0x0F` | Normal states |
| `0x10-0x1F` | Error states |
| `0x20-0x2F` | Reserved |

### State Machine

```
                    ┌──────────┐
                    │   IDLE   │
                    └────┬─────┘
                         │ BLE connect
                         ▼
                    ┌──────────┐
         ┌─────────│  READY   │─────────┐
         │         └────┬─────┘         │
         │              │ credentials   │ timeout
         │              ▼               │
         │    ┌─────────────────────┐   │
         │    │ CREDENTIALS_RECEIVED│   │
         │    └─────────┬───────────┘   │
         │              │ CONNECT cmd   │
         │              ▼               │
         │       ┌────────────┐         │
         │       │ CONNECTING │─────────┤
         │       └─────┬──────┘         │
         │             │ connected      │
         │             ▼                │
         │       ┌────────────┐         │
         │       │ VERIFYING  │─────────┤
         │       └─────┬──────┘         │
         │             │ verified       │
         │             ▼                │
         │       ┌────────────┐         │
         │       │  SUCCESS   │         │
         │       └────────────┘         │
         │                              │
         │  RESET cmd                   │
         └──────────────────────────────┘
                         │
                         ▼
                   ┌───────────┐
                   │  ERROR_*  │
                   └───────────┘
```

---

## Commands

### Command Reference

| Command | Code | Description | Expected Response |
|---------|------|-------------|-------------------|
| `CONNECT` | `0x01` | Connect using stored credentials | Status transitions |
| `RESET` | `0x02` | Clear credentials, return to READY | Status → READY |
| `GET_STATUS` | `0x03` | Request current status | Status notification |
| `SCAN_WIFI` | `0x04` | Scan Wi-Fi networks | Response with networks |
| `ABORT` | `0x05` | Cancel current operation | Status → READY or IDLE |
| `FACTORY_RESET` | `0xFF` | Full device reset | Device reboots |

### Command Responses

Commands that complete immediately return ATT success (0x00).
Long-running commands (CONNECT, SCAN_WIFI) provide progress via Status and Response notifications.

---

## Error Handling

### Recovery Procedures

| Error | Recovery |
|-------|----------|
| `ERROR_INVALID_SSID` | Re-write valid SSID |
| `ERROR_INVALID_PASSWORD` | Re-write valid password |
| `ERROR_WIFI_FAILED` | Check credentials, retry |
| `ERROR_WIFI_TIMEOUT` | Check network availability, retry |
| `ERROR_CLOUD_FAILED` | Retry, or check cloud status |
| `ERROR_BUSY` | Wait 1s, retry command |

### App UI Recommendations

1. **Show clear error messages** - Map status codes to user-friendly text
2. **Offer retry option** - Most errors are recoverable
3. **Timeout handling** - If no status update for 30s, show timeout message
4. **Connection loss** - If BLE disconnects during provisioning, show reconnect option

### Example Error Messages

```swift
func errorMessage(for status: UInt8) -> String {
    switch status {
    case 0x10: return "Invalid network name"
    case 0x11: return "Invalid password"
    case 0x12: return "Could not connect to Wi-Fi. Check password and try again."
    case 0x13: return "Connection timed out. Make sure you're near the router."
    case 0x14: return "Could not join Thread network"
    case 0x15: return "Could not connect to Saturday cloud"
    case 0x1F: return "An unexpected error occurred"
    default:   return "Unknown error"
    }
}
```

---

## Security Considerations

### BLE Security Levels

| Level | Description | When to Use |
|-------|-------------|-------------|
| 1 | No security | Initial connection, reading Device Info |
| 2 | Unauthenticated encryption | Optional, improves privacy |
| 3 | Authenticated encryption (pairing) | Recommended for credential writes |

### Current Implementation

**Version 1.0:** Security Level 1 (no pairing required)

Rationale:
- Provisioning requires physical access to device (button press)
- Credentials are for connecting to user's own network
- Simplifies user experience

**Future versions** may require pairing (Level 3) for:
- User token writes
- Factory reset commands
- Configuration changes

### Recommendations

1. **Physical security** - BLE provisioning requires button press
2. **Timeout** - Stop advertising after 5 minutes
3. **One connection** - Only allow single BLE connection
4. **Clear on disconnect** - Clear partial credentials if BLE disconnects
5. **No credential readback** - Passwords are write-only

---

## Device Type Extensions

### Hub-Specific Characteristics

Hubs act as Thread Border Routers and may expose additional characteristics:

| Characteristic | UUID | Description |
|----------------|------|-------------|
| Thread Network Info | `0x0100` | Read Thread network status |
| Thread Commissioning | `0x0101` | Commission new Thread devices |

### Crate-Specific Characteristics

Crates may expose battery and inventory status:

| Characteristic | UUID | Description |
|----------------|------|-------------|
| Battery Level | `0x0110` | Read battery percentage |
| Tag Count | `0x0111` | Read number of tags detected |

### Adding New Characteristics

To maintain compatibility:

1. Use reserved UUID ranges
2. Add new capabilities to Device Info
3. Check capability before accessing characteristic
4. Handle "characteristic not found" gracefully

---

## Implementation Examples

### iOS (Swift/CoreBluetooth)

```swift
import CoreBluetooth

class SaturdayDeviceManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // UUIDs
    let serviceUUID = CBUUID(string: "53560000-0001-1000-8000-00805f9b34fb")
    let deviceInfoUUID = CBUUID(string: "53560001-0001-1000-8000-00805f9b34fb")
    let statusUUID = CBUUID(string: "53560002-0001-1000-8000-00805f9b34fb")
    let commandUUID = CBUUID(string: "53560003-0001-1000-8000-00805f9b34fb")
    let responseUUID = CBUUID(string: "53560004-0001-1000-8000-00805f9b34fb")
    let wifiSSIDUUID = CBUUID(string: "53560010-0001-1000-8000-00805f9b34fb")
    let wifiPasswordUUID = CBUUID(string: "53560011-0001-1000-8000-00805f9b34fb")

    var centralManager: CBCentralManager!
    var peripheral: CBPeripheral?

    // Characteristic references
    var statusCharacteristic: CBCharacteristic?
    var commandCharacteristic: CBCharacteristic?
    var responseCharacteristic: CBCharacteristic?
    var wifiSSIDCharacteristic: CBCharacteristic?
    var wifiPasswordCharacteristic: CBCharacteristic?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scanning

    func startScanning() {
        centralManager.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    // MARK: - Provisioning

    func provisionWiFi(ssid: String, password: String) {
        guard let peripheral = peripheral,
              let ssidChar = wifiSSIDCharacteristic,
              let passChar = wifiPasswordCharacteristic,
              let cmdChar = commandCharacteristic else {
            return
        }

        // Write SSID
        if let ssidData = ssid.data(using: .utf8) {
            peripheral.writeValue(ssidData, for: ssidChar, type: .withResponse)
        }

        // Write password
        if let passData = password.data(using: .utf8) {
            peripheral.writeValue(passData, for: passChar, type: .withResponse)
        }

        // Send CONNECT command
        let connectCommand = Data([0x01])
        peripheral.writeValue(connectCommand, for: cmdChar, type: .withResponse)
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let value = characteristic.value else { return }

        switch characteristic.uuid {
        case statusUUID:
            handleStatusUpdate(value[0])
        case responseUUID:
            if let message = String(data: value, encoding: .utf8) {
                handleResponse(message)
            }
        default:
            break
        }
    }

    private func handleStatusUpdate(_ status: UInt8) {
        switch status {
        case 0x05:
            print("Provisioning successful!")
        case 0x10...0x1F:
            print("Error: \(errorMessage(for: status))")
        default:
            print("Status: \(status)")
        }
    }
}
```

### Android (Kotlin/Android BLE)

```kotlin
import android.bluetooth.*
import java.util.UUID

class SaturdayDeviceManager(private val context: Context) {

    companion object {
        val SERVICE_UUID = UUID.fromString("53560000-0001-1000-8000-00805f9b34fb")
        val DEVICE_INFO_UUID = UUID.fromString("53560001-0001-1000-8000-00805f9b34fb")
        val STATUS_UUID = UUID.fromString("53560002-0001-1000-8000-00805f9b34fb")
        val COMMAND_UUID = UUID.fromString("53560003-0001-1000-8000-00805f9b34fb")
        val RESPONSE_UUID = UUID.fromString("53560004-0001-1000-8000-00805f9b34fb")
        val WIFI_SSID_UUID = UUID.fromString("53560010-0001-1000-8000-00805f9b34fb")
        val WIFI_PASSWORD_UUID = UUID.fromString("53560011-0001-1000-8000-00805f9b34fb")

        const val CMD_CONNECT: Byte = 0x01
        const val CMD_RESET: Byte = 0x02
    }

    private var bluetoothGatt: BluetoothGatt? = null

    private val gattCallback = object : BluetoothGattCallback() {

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) {
                val service = gatt.getService(SERVICE_UUID)
                // Enable notifications for Status and Response
                enableNotifications(service.getCharacteristic(STATUS_UUID))
                enableNotifications(service.getCharacteristic(RESPONSE_UUID))
            }
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray
        ) {
            when (characteristic.uuid) {
                STATUS_UUID -> handleStatusUpdate(value[0])
                RESPONSE_UUID -> handleResponse(String(value, Charsets.UTF_8))
            }
        }
    }

    fun provisionWiFi(ssid: String, password: String) {
        val gatt = bluetoothGatt ?: return
        val service = gatt.getService(SERVICE_UUID) ?: return

        // Write SSID
        val ssidChar = service.getCharacteristic(WIFI_SSID_UUID)
        ssidChar.value = ssid.toByteArray(Charsets.UTF_8)
        gatt.writeCharacteristic(ssidChar)

        // Write password (queued after SSID write completes)
        val passChar = service.getCharacteristic(WIFI_PASSWORD_UUID)
        passChar.value = password.toByteArray(Charsets.UTF_8)
        gatt.writeCharacteristic(passChar)

        // Send CONNECT command
        val cmdChar = service.getCharacteristic(COMMAND_UUID)
        cmdChar.value = byteArrayOf(CMD_CONNECT)
        gatt.writeCharacteristic(cmdChar)
    }

    private fun handleStatusUpdate(status: Byte) {
        when (status.toInt()) {
            0x05 -> Log.d("Saturday", "Provisioning successful!")
            in 0x10..0x1F -> Log.e("Saturday", "Error: ${errorMessage(status)}")
            else -> Log.d("Saturday", "Status: $status")
        }
    }
}
```

### Flutter (flutter_blue_plus)

```dart
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class SaturdayBLEService {
  static const serviceUuid = '53560000-0001-1000-8000-00805f9b34fb';
  static const statusUuid = '53560002-0001-1000-8000-00805f9b34fb';
  static const commandUuid = '53560003-0001-1000-8000-00805f9b34fb';
  static const wifiSsidUuid = '53560010-0001-1000-8000-00805f9b34fb';
  static const wifiPasswordUuid = '53560011-0001-1000-8000-00805f9b34fb';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _commandChar;
  BluetoothCharacteristic? _ssidChar;
  BluetoothCharacteristic? _passwordChar;

  Stream<List<ScanResult>> scanForDevices() {
    FlutterBluePlus.startScan(
      withServices: [Guid(serviceUuid)],
      timeout: Duration(seconds: 10),
    );
    return FlutterBluePlus.scanResults;
  }

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    await device.connect();

    List<BluetoothService> services = await device.discoverServices();
    BluetoothService? provService = services.firstWhere(
      (s) => s.uuid.toString() == serviceUuid,
    );

    for (var char in provService.characteristics) {
      switch (char.uuid.toString()) {
        case statusUuid:
          _statusChar = char;
          await char.setNotifyValue(true);
          break;
        case commandUuid:
          _commandChar = char;
          break;
        case wifiSsidUuid:
          _ssidChar = char;
          break;
        case wifiPasswordUuid:
          _passwordChar = char;
          break;
      }
    }
  }

  Stream<int> get statusStream => _statusChar?.value
      .map((data) => data.isNotEmpty ? data[0] : 0) ?? Stream.empty();

  Future<void> provisionWiFi(String ssid, String password) async {
    await _ssidChar?.write(ssid.codeUnits);
    await _passwordChar?.write(password.codeUnits);
    await _commandChar?.write([0x01]); // CONNECT command
  }
}
```

---

## Appendix

### A. UUID Quick Reference

```
Service:        53560000-0001-1000-8000-00805f9b34fb
Device Info:    53560001-0001-1000-8000-00805f9b34fb
Status:         53560002-0001-1000-8000-00805f9b34fb
Command:        53560003-0001-1000-8000-00805f9b34fb
Response:       53560004-0001-1000-8000-00805f9b34fb
Wi-Fi SSID:     53560010-0001-1000-8000-00805f9b34fb
Wi-Fi Password: 53560011-0001-1000-8000-00805f9b34fb
Thread Dataset: 53560020-0001-1000-8000-00805f9b34fb
User Token:     53560030-0001-1000-8000-00805f9b34fb
```

### B. Status Code Quick Reference

```
0x00 = IDLE
0x01 = READY
0x02 = CREDENTIALS_RECEIVED
0x03 = CONNECTING
0x04 = VERIFYING
0x05 = SUCCESS
0x10 = ERROR_INVALID_SSID
0x11 = ERROR_INVALID_PASSWORD
0x12 = ERROR_WIFI_FAILED
0x13 = ERROR_WIFI_TIMEOUT
0x14 = ERROR_THREAD_FAILED
0x15 = ERROR_CLOUD_FAILED
0x1E = ERROR_BUSY
0x1F = ERROR_UNKNOWN
```

### C. Command Quick Reference

```
0x01 = CONNECT
0x02 = RESET
0x03 = GET_STATUS
0x04 = SCAN_WIFI
0x05 = ABORT
0xFF = FACTORY_RESET (requires confirmation: 0x52 0x45 0x53 0x54)
```

### D. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | 2026-01-24 | Aligned with unified device architecture: renamed `unit_id` to `serial_number`, added `mac_address` to Device Info, added cross-references to Device Command Protocol and Capability Schema |
| 1.0.0 | 2026-01-05 | Initial protocol specification |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
