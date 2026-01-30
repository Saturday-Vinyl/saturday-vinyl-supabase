# Saturday Vinyl CoAP Protocol Specification

This document defines the CoAP (Constrained Application Protocol) communication standards for Saturday Vinyl Thread devices, specifically communication between the Hub (ESP32-H2 Thread Border Router) and Crate devices.

## Overview

| Property | Value |
|----------|-------|
| Protocol | CoAP over Thread |
| Port | 5683 (standard CoAP port) |
| Security | DTLS via Thread network encryption |
| Encoding | Binary (packed structs) |
| Content Format | `application/octet-stream` (default) |

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Saturday Hub                              │
│  ┌─────────────────┐              ┌─────────────────────────┐  │
│  │   ESP32-S3      │◄───UART────►│      ESP32-H2           │  │
│  │   (Master)      │              │  (Thread Border Router) │  │
│  │                 │              │                         │  │
│  │ - WiFi/Cloud    │              │  CoAP Server (port 5683)│  │
│  │ - BLE           │              │  ├─ POST /inventory     │  │
│  │ - RFID          │              │  ├─ POST /heartbeat     │  │
│  │ - USB Service   │              │  ├─ GET  /config        │  │
│  └─────────────────┘              │  └─ POST /ota (future)  │  │
│                                   └────────────┬────────────┘  │
└────────────────────────────────────────────────┼───────────────┘
                                                 │ Thread (IEEE 802.15.4)
                         ┌───────────────────────┼───────────────────────┐
                         │                       │                       │
                    ┌────▼────┐            ┌─────▼─────┐          ┌──────▼──────┐
                    │  Crate  │            │   Crate   │          │    Crate    │
                    │  (FTD)  │            │   (FTD)   │          │    (FTD)    │
                    └─────────┘            └───────────┘          └─────────────┘
```

## Message Flow

Crates are CoAP **clients** that send requests to the Hub's CoAP **server**. The Hub does not initiate requests to Crates in normal operation (push notifications use OTA protocol).

```
Crate (Client)                                Hub H2 (Server)
     │                                              │
     │──── POST /inventory ────────────────────────►│
     │◄─── 2.04 Changed ───────────────────────────│
     │                                              │
     │──── POST /heartbeat ────────────────────────►│
     │◄─── 2.04 Changed ───────────────────────────│
     │                                              │
     │──── GET /config ────────────────────────────►│
     │◄─── 2.05 Content (JSON payload) ────────────│
     │                                              │
```

---

## Endpoints

### POST /inventory

Reports the current vinyl record inventory in the Crate.

**When to Call**: On inventory change (record inserted/removed) or periodically based on config.

#### Request

| Field | Type | Description |
|-------|------|-------------|
| Method | POST | |
| URI Path | `/inventory` | |
| Content-Format | (none or `application/octet-stream`) | |
| Payload | Binary | See format below |

#### Request Payload Format

```
┌─────────────┬─────────────────────────────────────────────────┐
│  Byte 0     │  Bytes 1 to (1 + count * 12)                    │
├─────────────┼─────────────────────────────────────────────────┤
│  count (1B) │  EPC data (count * 12 bytes)                    │
└─────────────┴─────────────────────────────────────────────────┘
```

| Offset | Size | Field | Description |
|--------|------|-------|-------------|
| 0 | 1 | `count` | Number of EPCs (0-75) |
| 1 | 12 × count | `epcs` | Array of 12-byte EPC values |

**Constraints**:
- Maximum 75 EPCs per request (`COAP_MAX_EPCS_PER_UPDATE`)
- EPC length is always 12 bytes (`COAP_EPC_LENGTH`)
- Maximum payload size: 1 + (75 × 12) = 901 bytes
- `count = 0` indicates empty crate

#### Response

| Code | Meaning |
|------|---------|
| 2.04 Changed | Success - inventory received |
| 4.00 Bad Request | Malformed payload (missing count, truncated EPCs) |
| 4.05 Method Not Allowed | Non-POST method used |
| 5.00 Internal Server Error | Server-side processing error |

**Response Payload**: None

#### Example

```
Crate with 2 records (EPCs: E20000123456789012345678, E20000AABBCCDDEEFF112233)

Request payload (25 bytes):
  Byte 0:     0x02                          (count = 2)
  Bytes 1-12: E2 00 00 12 34 56 78 90 12 34 56 78  (EPC 1)
  Bytes 13-24: E2 00 00 AA BB CC DD EE FF 11 22 33  (EPC 2)
```

---

### POST /heartbeat

Periodic health check from Crate to Hub. Reports battery level, signal strength, and current tag count.

**When to Call**: Every `poll_interval` seconds as configured via `/config`.

#### Request

| Field | Type | Description |
|-------|------|-------------|
| Method | POST | |
| URI Path | `/heartbeat` | |
| Payload | Binary (3 bytes) | See format below |

#### Request Payload Format

```
┌───────────────────┬─────────────┬─────────────┐
│  Byte 0           │  Byte 1     │  Byte 2     │
├───────────────────┼─────────────┼─────────────┤
│  battery_percent  │  rssi       │  tag_count  │
│  (uint8_t, 0-100) │  (int8_t)   │  (uint8_t)  │
└───────────────────┴─────────────┴─────────────┘
```

| Offset | Size | Field | Type | Description |
|--------|------|-------|------|-------------|
| 0 | 1 | `battery_percent` | uint8_t | Battery level (0-100%) |
| 1 | 1 | `rssi` | int8_t | Signal strength in dBm (typically -30 to -100) |
| 2 | 1 | `tag_count` | uint8_t | Current number of tags in crate |

#### Response

| Code | Meaning |
|------|---------|
| 2.04 Changed | Success |
| 4.05 Method Not Allowed | Non-POST method used |

**Response Payload**: None

#### Example

```
Crate at 85% battery, -65 dBm signal, 3 tags:

Request payload (3 bytes):
  Byte 0: 0x55  (85 decimal = battery percent)
  Byte 1: 0xBF  (-65 signed = rssi)
  Byte 2: 0x03  (3 = tag count)
```

---

### GET /config

Request current configuration from Hub. Crates call this on boot and periodically to sync settings.

**When to Call**: On device boot, after joining Thread network, or when prompted.

#### Request

| Field | Type | Description |
|-------|------|-------------|
| Method | GET | |
| URI Path | `/config` | |
| Payload | None | |

#### Response

| Code | Meaning |
|------|---------|
| 2.05 Content | Success - config returned |
| 4.05 Method Not Allowed | Non-GET method used |

**Response Payload**: JSON (Content-Format: `application/json`)

```json
{
  "version": 1,
  "poll_interval": 30,
  "report_on_change": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | integer | Config schema version |
| `poll_interval` | integer | Seconds between heartbeats |
| `report_on_change` | boolean | If true, send inventory on any change |

---

## OTA Endpoints

The following endpoints implement CoAP-based OTA firmware updates from Hub to Crate devices. For the full cloud-to-Hub OTA protocol, see [OTA Protocol](./ota_protocol.md).

**Direction**: Hub (CoAP Client) → Crate (CoAP Server)

Note: Unlike the endpoints above where Crate is the client, OTA updates are push-based where the Hub initiates CoAP requests to the Crate.

### GET /ping

Checks if a Crate is reachable and responsive.

**When to Call**: Before initiating OTA, to verify device is online.

#### Request

| Field | Type | Description |
|-------|------|-------------|
| Method | GET | |
| URI Path | `/ping` | |
| Payload | None | |

#### Response

| Code | Meaning |
|------|---------|
| 2.05 Content | Device is reachable |
| No response | Device unreachable (timeout) |

---

### POST /ota/start

Initiates an OTA update session to a Crate.

**When to Call**: Beginning of OTA transfer, after `/ping` confirms device is reachable.

#### Request

| Field | Type | Description |
|-------|------|-------------|
| Method | POST | |
| URI Path | `/ota/start` | |
| Type | Confirmable | Must receive ACK before sending data |
| Payload | Binary (39 bytes) | See format below |

#### Request Payload Format

```
┌─────────────────────────────────────────────────────────────────┐
│  Bytes 0-3      │  Bytes 4-35      │  Bytes 36-38             │
├─────────────────┼──────────────────┼──────────────────────────┤
│  firmware_size  │  sha256 hash     │  version (major.min.pat) │
│  (uint32_t LE)  │  (32 bytes)      │  (3 × uint8_t)           │
└─────────────────┴──────────────────┴──────────────────────────┘
```

| Offset | Size | Field | Type | Description |
|--------|------|-------|------|-------------|
| 0 | 4 | `firmware_size` | uint32_t (LE) | Total firmware size in bytes |
| 4 | 32 | `sha256` | bytes | Expected SHA-256 hash of firmware |
| 36 | 1 | `version_major` | uint8_t | Major version number |
| 37 | 1 | `version_minor` | uint8_t | Minor version number |
| 38 | 1 | `version_patch` | uint8_t | Patch version number |

#### Response

| Code | Meaning |
|------|---------|
| 2.04 Changed | OTA session accepted, ready for data |
| 4.00 Bad Request | Invalid payload format |
| 4.09 Conflict | OTA already in progress |
| 5.00 Internal Server Error | Not enough flash space or internal error |

---

### POST /ota/data

Transfers firmware data chunks. Called repeatedly until all data is sent.

#### Request

| Field | Type | Description |
|-------|------|-------------|
| Method | POST | |
| URI Path | `/ota/data` | |
| Type | Confirmable | Must receive ACK for each chunk |
| Payload | Binary (4 + N bytes) | See format below |

#### Request Payload Format

```
┌─────────────────────────────────────────────────────────────────┐
│  Bytes 0-3      │  Bytes 4 to (4 + length - 1)                  │
├─────────────────┼───────────────────────────────────────────────┤
│  offset         │  firmware data chunk                           │
│  (uint32_t LE)  │  (up to 512 bytes)                             │
└─────────────────┴───────────────────────────────────────────────┘
```

| Offset | Size | Field | Type | Description |
|--------|------|-------|------|-------------|
| 0 | 4 | `offset` | uint32_t (LE) | Byte offset in firmware image |
| 4 | N | `data` | bytes | Firmware chunk (max 512 bytes) |

**Chunk Size**: Maximum 512 bytes per CoAP message (configurable via `COAP_OTA_BLOCK_SIZE`).

#### Response

| Code | Meaning |
|------|---------|
| 2.04 Changed | Chunk received and written successfully |
| 4.00 Bad Request | Invalid offset or payload |
| 4.08 Request Entity Incomplete | Missing data (out-of-order chunk) |
| 5.00 Internal Server Error | Flash write failed |

#### Retry Behavior

The Hub retries failed chunks up to `COAP_OTA_MAX_RETRIES` (3) times before aborting the session.

---

### POST /ota/verify

Signals end of transfer and requests firmware verification.

**When to Call**: After all `/ota/data` chunks have been successfully ACKed.

#### Request

| Field | Type | Description |
|-------|------|-------------|
| Method | POST | |
| URI Path | `/ota/verify` | |
| Type | Confirmable | |
| Payload | None | |

#### Response

| Code | Meaning |
|------|---------|
| 2.04 Changed | Verification passed, device will reboot to apply |
| 4.00 Bad Request | No OTA session active |
| 5.00 Internal Server Error | SHA-256 mismatch or flash verification failed |

**Important**: On success, the Crate will apply the update and reboot. The Hub should expect the device to become temporarily unreachable.

---

### POST /ota/abort

Aborts an in-progress OTA session and cleans up staged firmware.

**When to Call**: User cancellation, timeout, or unrecoverable error.

#### Request

| Field | Type | Description |
|-------|------|-------------|
| Method | POST | |
| URI Path | `/ota/abort` | |
| Type | Non-Confirmable | Best-effort (device may be unreachable) |
| Payload | None | |

#### Response

| Code | Meaning |
|------|---------|
| 2.04 Changed | Abort acknowledged, session cleaned up |
| (No response expected for NON messages) |

---

## Device Addressing

### RLOC16 (Router Locator)

Each device on the Thread network has a 16-bit RLOC16 address derived from its mesh-local IPv6 address:
- Format: Last 2 bytes of mesh-local address
- Example: `fd00:dead:beef::ff:fe00:1234` → RLOC16 = `0x1234`

### Extended Address

8-byte IEEE 802.15.4 extended address (similar to MAC address). Used for device identification across network reconfigurations.

### Sender Identification

The Hub extracts sender identity from incoming CoAP requests:

```c
/* Extract RLOC16 from peer address */
const otIp6Address *peer = &message_info->mPeerAddr;
uint16_t rloc16 = ((uint16_t)peer->mFields.m8[14] << 8) | peer->mFields.m8[15];

/* Extended address derived from last 8 bytes (approximation) */
uint8_t ext_addr[8];
memcpy(ext_addr, peer->mFields.m8 + 8, 8);
```

---

## Error Handling

### CoAP Response Codes

| Code | Name | When Used |
|------|------|-----------|
| 2.04 | Changed | Successful POST (inventory, heartbeat) |
| 2.05 | Content | Successful GET with payload (config) |
| 4.00 | Bad Request | Malformed payload, invalid parameters |
| 4.05 | Method Not Allowed | Wrong HTTP method for endpoint |
| 5.00 | Internal Server Error | Server-side failure |

### Retry Behavior (Client)

Crates should implement exponential backoff for failed requests:

```
Attempt 1: Immediate
Attempt 2: 2 seconds delay
Attempt 3: 4 seconds delay
Attempt 4: 8 seconds delay
Maximum: 60 seconds between retries
```

### Timeout Values

| Operation | Timeout |
|-----------|---------|
| CoAP ACK | 2 seconds (default) |
| Request timeout | 30 seconds |
| Block transfer | 60 seconds total |

---

## Security Considerations

### Thread Network Security

All CoAP traffic is encrypted at the Thread network layer:
- AES-128 CCM encryption
- Network Key shared by all Thread devices
- Automatic key rotation (optional)

### Authentication

Devices are authenticated via Thread network joining:
1. Device must possess valid Thread credentials (Network Key, PAN ID, etc.)
2. Joining requires commissioning (PSKd exchange)
3. Only commissioned devices can send CoAP requests

### Input Validation

Hub validates all incoming payloads:
- Payload length checks before parsing
- EPC count bounds checking (max 75)
- Integer overflow prevention
- Null termination for string data

---

## Implementation Notes

### OpenThread CoAP API

The Hub uses OpenThread's built-in CoAP implementation:

```c
#include "openthread/coap.h"

/* Start CoAP server */
otCoapStart(instance, COAP_DEFAULT_PORT);

/* Register resource */
otCoapResource resource = {
    .mUriPath = "inventory",
    .mHandler = inventory_handler,
};
otCoapAddResource(instance, &resource);
```

### Thread Safety

CoAP handlers run in the OpenThread task context. Use `esp_openthread_lock_acquire/release` when accessing OpenThread APIs from other tasks.

### Memory Constraints

ESP32-H2 has limited RAM. CoAP implementation uses:
- OpenThread message buffers (not heap)
- Maximum payload: ~1KB per message
- No dynamic allocation in handlers

---

## Protocol Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01 | Initial specification |
| 1.1 | 2025-01 | Added OTA endpoints (Phase 4) |

---

## Related Documents

- [Service Mode Protocol](./service_mode_protocol.md) - USB serial interface for provisioning
- [BLE Provisioning Protocol](./ble_provisioning_protocol.md) - Mobile app device setup
- [OTA Protocol](./ota_protocol.md) - Over-the-air update mechanism
- [S3-H2 Protocol](../../shared/include/s3_h2_protocol.h) - Inter-processor UART protocol
