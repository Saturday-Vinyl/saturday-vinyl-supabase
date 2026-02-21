# Saturday CoAP Mesh Protocol

**Version:** 1.1.0
**Last Updated:** 2026-02-20
**Audience:** Saturday Firmware engineers, Node firmware developers, Backend developers

---

## Table of Contents

1. [Overview](#overview)
2. [Transport](#transport)
3. [Content Format — CBOR](#content-format--cbor)
4. [Endpoints Summary](#endpoints-summary)
5. [Node → Hub: POST /register](#node--hub-post-register)
6. [Node → Hub: POST /heartbeat](#node--hub-post-heartbeat)
7. [Node → Hub: POST /inventory](#node--hub-post-inventory)
8. [Hub → Node: POST /cmd](#hub--node-post-cmd)
9. [Hub → Node: OTA Endpoints](#hub--node-ota-endpoints)
10. [Command Lifecycle over Mesh](#command-lifecycle-over-mesh)
11. [Device Registration and Identity Cache](#device-registration-and-identity-cache)
12. [Sleepy End Device Considerations](#sleepy-end-device-considerations)
13. [Cloud Relay Pipeline](#cloud-relay-pipeline)
14. [Version Compatibility](#version-compatibility)
15. [Implementation Notes](#implementation-notes)
16. [Version History](#version-history)

---

## Overview

This document defines the **CoAP Mesh Protocol** for communication between the Saturday Hub's Thread Border Router (ESP32-H2 co-processor) and Thread mesh devices (Crates and future device types). It is the authoritative contract for all CoAP communication over the Thread 802.15.4 mesh network.

### Problem

The Hub's CoAP server currently expects 3-byte binary heartbeats `[battery, rssi, tags]` while Crate firmware sends ~412-byte JSON. This format mismatch causes data corruption — JSON bytes are interpreted as binary values (e.g., `{` = ASCII 123 is read as battery 123%).

### Scope

- All CoAP communication over Thread mesh (Hub ↔ Node)
- Payload formats, endpoints, device identification, command lifecycle
- Cloud relay pipeline from CoAP to `device_heartbeats` table

**Not in scope:** S3-H2 UART binary protocol details (see `s3_h2_protocol.h`), cloud REST API, BLE provisioning (see `ble_provisioning_protocol.md`), Supabase Realtime commands to WiFi-connected devices.

### Design Principles

1. **CBOR Everywhere** — Content-Format 60 (`application/cbor`) for all endpoints. Single serialization format, single parser on each side, standard CoAP content format pairing (RFC 7252).
2. **Capability-Driven** — Heartbeat telemetry fields are defined by the device's firmware capability schema (see [Capability Schema](../schemas/capability_schema.md)), not hardcoded. CBOR maps handle variable field sets naturally.
3. **Device-Agnostic** — Protocol applies to any Thread device type (Crate, future devices), not just the Crate-Hub relationship.
4. **Battery-Efficient** — Typical heartbeat payload ~50 bytes, fits in a single 802.15.4 frame. NON (non-confirmable) messages for routine telemetry, CON (confirmable) for commands.
5. **Bidirectional** — Hub is both CoAP server (receives telemetry) and CoAP client (sends commands, OTA).
6. **Forward Compatible** — CBOR maps: receivers MUST ignore unknown keys, senders MAY add new keys without version negotiation.

---

## Transport

| Parameter | Value |
|-----------|-------|
| Protocol | CoAP (RFC 7252) over UDP over IPv6 |
| Network | Thread 802.15.4 mesh (250 kbps shared) |
| Port | 5683 (standard CoAP, unsecured) |
| Content-Format | 60 (`application/cbor`) |
| Max single-frame CoAP payload | ~62 bytes (after MAC + security + 6LoWPAN + CoAP overhead) |

### Addressing

**Hub (Border Router / Leader):**

Nodes address the Hub via the Thread Leader Anycast Locator (ALOC):

```
<mesh-local-prefix>:0:ff:fe00:fc00
```

The IID portion is `0000:00ff:fe00:fc00`. This is NOT the same as `::fc00` — the `ff:fe00` bytes are required.

Example: `fd00:83e:82ed:2980:0:ff:fe00:fc00`

**Node (Crate / Device):**

The Hub addresses nodes via their mesh-local EUI-64 address. The IID is derived from the extended MAC address with the Universal/Local bit flipped (`byte[0] XOR 0x02`), following RFC 4291 Modified EUI-64 format.

Example: ext_addr `74:4D:BD:60:00:12:34:56` → IID `764d:bd60:0012:3456`

### Message Types

| Type | Used For | Rationale |
|------|----------|-----------|
| CON (Confirmable) | Commands (Hub → Node), Register, Command ack/result | Delivery guarantee required |
| NON (Non-confirmable) | Status heartbeats, Inventory | Lost telemetry is replaced by the next cycle |

---

## Content Format — CBOR

All CoAP messages in this protocol use Content-Format: 60 (`application/cbor`), with the exception of OTA data endpoints which carry raw binary firmware bytes.

Payload schemas in this document are defined using **CDDL** (Concise Data Definition Language, RFC 8610).

### Encoding Rules

- **Map keys**: Text strings (human-readable). Integer keys are NOT used — readability outweighs the 1-2 byte savings per key given payloads are already small.
- **Integers**: CBOR unsigned or negative integers (not wrapped in strings).
- **Booleans**: CBOR simple values `true` / `false`.
- **Byte strings**: CBOR `bstr` for raw binary data (EPC values, hashes).
- **Text strings**: CBOR `tstr` (UTF-8).

### CBOR Diagnostic Notation

Examples in this document use CBOR diagnostic notation (RFC 8949 §8) for readability. Actual payloads are binary CBOR, not text.

---

## Endpoints Summary

| Direction | Method | URI Path | Msg Type | Payload | Typical Size | Frequency |
|-----------|--------|----------|----------|---------|-------------|-----------|
| Node → Hub | POST | `/register` | CON | CBOR | ~70 B | On Thread attach |
| Node → Hub | POST | `/heartbeat` | NON | CBOR | ~50 B | Configurable (default 30s) |
| Node → Hub | POST | `/inventory` | NON | CBOR | variable | On RFID change |
| Hub → Node | POST | `/cmd` | CON | CBOR | ~80 B | On demand |
| Hub → Node | POST | `/ota/start` | CON | Binary | 39 B | OTA session start |
| Hub → Node | POST | `/ota/data` | CON | Binary | ≤516 B | OTA chunks |
| Hub → Node | POST | `/ota/verify` | CON | Empty | 0 B | OTA finalize |

---

## Node → Hub: POST /register

Device registers with the Hub immediately after Thread attach. This establishes the identity mapping (source address → device info) so that subsequent heartbeats can omit identity fields, saving ~40 bytes per heartbeat.

### Request

```cddl
register-request = {
  "mac"     : tstr,           ; MAC address "AA:BB:CC:DD:EE:FF"
  "unit_id" : tstr,           ; Serial number "SV-CRT-000001"
  "type"    : tstr,           ; Device type slug "crate"
  "fw"      : tstr,           ; Firmware version "1.2.0"
  ? "caps"  : [* tstr],      ; Capability names ["rfid", "battery", "thread"]
}
```

### Example (CBOR diagnostic)

```cbor-diag
{
  "mac": "74:4D:BD:FF:FE:60:12:34",
  "unit_id": "SV-CRT-000001",
  "type": "crate",
  "fw": "0.2.0",
  "caps": ["rfid", "battery", "thread", "environment"]
}
```

Approximate encoded size: ~75 bytes (single 802.15.4 frame).

### Response

| Condition | Code | Body |
|-----------|------|------|
| First registration | 2.01 Created | Empty |
| Re-registration | 2.04 Changed | Empty |

### Behavior

- Node sends `/register` on every Thread attach (first join, reconnect after power loss, network change).
- Hub caches the mapping keyed by source IPv6 address / extended address.
- If a node sends a heartbeat before registering, the Hub responds with **4.01 Unauthorized**, which signals the node to send `/register` first.

---

## Node → Hub: POST /heartbeat

Capability-driven telemetry. The payload is a CBOR map with a protocol version, heartbeat type, and flat telemetry fields defined by the node's firmware capability schema.

### Request

```cddl
heartbeat-request = {
  "v"        : uint,                              ; Protocol version (1)
  "type"     : "status" / "command_ack" / "command_result",
  ? "cmd_id" : tstr,                              ; Command UUID (present for ack/result)
  ? "result" : {                                  ; Present for command_result only
    "status" : "completed" / "failed",
    ? "data"  : {* tstr => any},                  ; Result data
    ? "error" : tstr,                             ; Error message (for failed)
  },
  * tstr => any,                                  ; Capability telemetry fields
}
```

### Heartbeat Types

| Type | Description | Required Fields |
|------|-------------|----------------|
| `status` | Regular periodic telemetry | `v`, `type`, plus capability fields |
| `command_ack` | Acknowledges receipt of a command | `v`, `type`, `cmd_id` |
| `command_result` | Reports command completion or failure | `v`, `type`, `cmd_id`, `result` |

These types align with the [Command Acknowledgement Protocol](device_command_protocol.md#command-acknowledgement-protocol) in the Device Command Protocol.

### Example: Status Heartbeat (CBOR diagnostic)

```cbor-diag
{
  "v": 1,
  "type": "status",
  "battery_level": 85,
  "battery_mv": 3750,
  "battery_charging": false,
  "thread_rssi": -65,
  "rfid_tag_count": 3,
  "temperature_c": 22.5,
  "humidity_pct": 45.2,
  "uptime_sec": 86400,
  "free_heap": 125000,
  "min_free_heap": 98000
}
```

Approximate encoded size: ~55 bytes (single 802.15.4 frame).

### Example: Command Ack (CBOR diagnostic)

```cbor-diag
{
  "v": 1,
  "type": "command_ack",
  "cmd_id": "550e8400-e29b-41d4-a716-446655440000",
  "battery_level": 85,
  "uptime_sec": 86410,
  "free_heap": 124500,
  "min_free_heap": 98000
}
```

### Example: Command Result (CBOR diagnostic)

```cbor-diag
{
  "v": 1,
  "type": "command_result",
  "cmd_id": "550e8400-e29b-41d4-a716-446655440000",
  "result": {
    "status": "completed",
    "data": {
      "device_type": "crate",
      "firmware_version": "0.2.0",
      "mac_address": "74:4D:BD:FF:FE:60:12:34"
    }
  },
  "battery_level": 85,
  "uptime_sec": 86415,
  "free_heap": 124200,
  "min_free_heap": 98000
}
```

### Telemetry Field Naming

Field names follow the [Capability Schema](../schemas/capability_schema.md) conventions:

| Suffix | Unit | Example |
|--------|------|---------|
| `_c` | Celsius | `temperature_c` |
| `_pct` | Percent | `humidity_pct`, `battery_level` (0-100) |
| `_mv` | Millivolts | `battery_mv` |
| `_sec` | Seconds | `uptime_sec` |
| `_dbm` | Decibels (milliwatt) | `thread_rssi` |

Fields are flat (no nesting). Capability groupings are organizational only — they do not appear in the payload.

### Identity

Heartbeats carry **no identity fields** (`mac_address`, `unit_id`, `device_type`, `firmware_version`). The Hub resolves the sender's identity from the `/register` cache using the source IPv6 address of the CoAP request (`otMessageInfo.mPeerAddr`).

This saves ~40 bytes per heartbeat compared to including identity every 30 seconds.

### Response

| Condition | Code | Body |
|-----------|------|------|
| Success | 2.04 Changed | Empty |
| Unknown sender | 4.01 Unauthorized | Empty (node should re-register) |

---

## Node → Hub: POST /inventory

Reports the RFID EPC tags currently present in the Crate.

### Request

```cddl
inventory-request = {
  "epcs" : [* bstr .size 12],    ; Array of 12-byte EPC byte strings
}
```

CBOR byte strings (`bstr`) encode raw binary EPC data efficiently — no hex encoding overhead.

### Size Estimates

| EPCs | Approximate CBOR size | Frames |
|------|-----------------------|--------|
| 1 | ~18 B | 1 |
| 5 | ~75 B | 1-2 |
| 10 | ~140 B | 2-3 |
| 75 (max) | ~920 B | 6LoWPAN fragmented |

Maximum: 75 EPCs (per existing `COAP_MAX_EPCS_PER_UPDATE`).

### Response

| Condition | Code | Body |
|-----------|------|------|
| Success | 2.04 Changed | Empty |

---

## Hub → Node: POST /cmd

General command delivery over mesh. This is the mesh transport for commands originating from the cloud `device_commands` table (see [Device Command Protocol](device_command_protocol.md)).

### Request

```cddl
cmd-request = {
  "id"      : tstr,              ; Command UUID from device_commands table
  "cmd"     : tstr,              ; Command name: "reboot", "get_dataset", "register", etc.
  ? "params" : {* tstr => any},  ; Command parameters
}
```

All commands — both core (e.g., `reboot`) and capability-specific (e.g., `get_dataset`, `scan`) — use the same flat format. There is no wrapping meta-command.

### Example: Core Command (CBOR diagnostic)

```cbor-diag
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "cmd": "reboot"
}
```

### Example: Capability Command (CBOR diagnostic)

```cbor-diag
{
  "id": "660e8400-e29b-41d4-a716-446655440001",
  "cmd": "scan",
  "params": {
    "duration_ms": 5000,
    "power_dbm": 20
  }
}
```

### Example: Thread Dataset Query (CBOR diagnostic)

```cbor-diag
{
  "id": "770e8400-e29b-41d4-a716-446655440002",
  "cmd": "get_dataset"
}
```

### Example: Hub-Initiated Re-registration (CBOR diagnostic)

```cbor-diag
{
  "id": "00000000-0000-0000-0000-000000000000",
  "cmd": "register"
}
```

The `register` command is sent by the Hub when it receives a heartbeat from an unregistered node. See [Unregistered Device Handling](#unregistered-device-handling).

### Response

| Condition | Code | Body |
|-----------|------|------|
| Command received | 2.04 Changed | Empty |
| Unknown command | 4.04 Not Found | Empty |
| Busy | 5.03 Service Unavailable | Empty |

The CoAP 2.04 response is **transport-level** receipt only. Logical command acknowledgement and result are sent as heartbeat messages (`command_ack` and `command_result` types) back to the Hub via `POST /heartbeat`.

### Delivery

- Uses **CON** (confirmable) messages for guaranteed delivery.
- For Sleepy End Devices (SEDs): the parent router buffers the CoAP message until the node's next poll. See [Sleepy End Device Considerations](#sleepy-end-device-considerations).
- CoAP retransmission (2s initial, exponential backoff, max 4 retries per RFC 7252) handles poll timing.

---

## Hub → Node: OTA Endpoints

The Hub acts as a CoAP client to push firmware updates to nodes. These endpoints remain **binary** (not CBOR) because they transfer raw firmware data where CBOR wrapping adds overhead with no benefit.

### POST /ota/start

Initiates an OTA session with firmware metadata.

```
Offset  Size  Field
------  ----  -----------------
0       4     firmware_size (uint32, little-endian)
4       32    sha256 hash
36      1     version_major
37      1     version_minor
38      1     version_patch
```

Total: 39 bytes. Response: 2.04 Changed.

### POST /ota/data

Sends a firmware chunk.

```
Offset  Size  Field
------  ----  -----------------
0       4     offset (uint32, little-endian)
4       N     firmware data (max 512 bytes per COAP_OTA_BLOCK_SIZE)
```

Maximum payload: 516 bytes. Response: 2.04 Changed.

### POST /ota/verify

Requests the node verify the firmware hash and apply the update.

Empty payload. Response: 2.04 Changed (after hash verification).

### POST /ota/abort

Aborts an in-progress OTA session.

Empty payload. Sent as **NON** (best-effort). Response: 2.04 Changed.

---

## Command Lifecycle over Mesh

Commands flow from the cloud through the Hub to mesh nodes and back:

```
Cloud                S3 (WiFi)           H2 (Thread BR)       Node (Crate)
  │                     │                     │                     │
  │ device_commands     │                     │                     │
  │ INSERT + trigger    │                     │                     │
  │────────────────────>│                     │                     │
  │                     │                     │                     │
  │                     │ UART CMD_RELAY_CMD  │                     │
  │                     │ [ext_addr + CBOR]   │                     │
  │                     │────────────────────>│                     │
  │                     │                     │                     │
  │                     │                     │ CoAP POST /cmd      │
  │                     │                     │ (CON, CBOR)         │
  │                     │                     │────────────────────>│
  │                     │                     │                     │
  │                     │                     │     CoAP 2.04       │
  │                     │                     │<────────────────────│
  │                     │                     │                     │
  │                     │                     │ CoAP POST /heartbeat│
  │                     │                     │ (command_ack)       │
  │                     │                     │<────────────────────│
  │                     │                     │                     │
  │                     │ UART EVT_CRATE_HB   │                     │
  │                     │<────────────────────│                     │
  │                     │                     │                     │
  │ POST device_        │                     │                     │
  │ heartbeats          │                     │                     │
  │<────────────────────│                     │                     │
  │                     │                     │                     │
  │ Trigger: update     │                     │ CoAP POST /heartbeat│
  │ device_commands     │                     │ (command_result)    │
  │ .status             │                     │<────────────────────│
  │                     │                     │                     │
  │                     │ UART EVT_CRATE_HB   │                     │
  │                     │<────────────────────│                     │
  │                     │                     │                     │
  │ POST device_        │                     │                     │
  │ heartbeats          │                     │                     │
  │<────────────────────│                     │                     │
```

### Status Mapping

The cloud database trigger automatically updates `device_commands.status` based on heartbeat type:

| Heartbeat Type | Sets `device_commands.status` |
|----------------|-------------------------------|
| `command_ack` | `acknowledged` |
| `command_result` with `"status": "completed"` | `completed` |
| `command_result` with `"status": "failed"` | `failed` |

This is identical to the WiFi-connected device flow described in [Device Command Protocol — Command Acknowledgement](device_command_protocol.md#command-acknowledgement-protocol), with the mesh relay being transparent to the cloud.

---

## Device Registration and Identity Cache

### Registration Flow

1. Node joins Thread network (role transitions from detached → child/router)
2. Node immediately sends `POST /register` (CON) to Hub
3. Hub caches the identity mapping
4. Node begins periodic `POST /heartbeat` (NON)

### Hub Identity Cache

| Field | Source | Description |
|-------|--------|-------------|
| Key: mesh-local IPv6 | CoAP `mPeerAddr` | Sender address from CoAP message info |
| `mac` | `/register` | Device MAC address |
| `unit_id` | `/register` | Serial number |
| `type` | `/register` | Device type slug |
| `fw` | `/register` | Firmware version |
| `caps` | `/register` | Capability list |
| `last_seen` | Updated on heartbeat | Timestamp of last activity |

- Maximum entries: ~20 (typical home Thread network)
- Cache eviction: entry removed after 5 minutes of no heartbeat, or on `THREAD_BR_EVENT_DEVICE_LEFT`

### Unregistered Device Handling

When the Hub receives a `POST /heartbeat` from an address not in the cache, it uses a two-pronged approach to recover:

1. **Graceful accept with 4.01 (passive signal):** The Hub creates a partial cache entry (`mac="unknown"`, `unit_id="unknown"`) so telemetry can still be forwarded to the cloud. It responds with **4.01 Unauthorized** to signal "re-register required." The node should interpret 4.01 as a prompt to send `POST /register` before its next heartbeat.

2. **Active re-register nudge:** The Hub sends a CON `POST /cmd` to the unregistered node with `{"id":"00000000-0000-0000-0000-000000000000","cmd":"register"}`. This actively tells the node to re-register, handling cases where the node firmware doesn't react to the 4.01 response code. The nudge is rate-limited to **one per device per 60 seconds** to avoid flooding.

This dual approach handles the common scenario where the Hub restarts (clearing its registration cache) while mesh nodes continue sending heartbeats. Previously, these heartbeats were rejected permanently until the nodes were power-cycled.

### Re-registration

Nodes re-register on every Thread re-attach. The Hub replaces the existing cache entry. This handles:
- Node reboot (new firmware version, changed capabilities)
- Hub reboot (cache cleared)
- Network topology change (new mesh-local address)

---

## Sleepy End Device Considerations

Crates are battery-powered **Sleepy End Devices (SEDs)**. The 802.15.4 radio is turned off between poll intervals to conserve power.

### Two Independent Intervals

| Interval | Purpose | Default | Radio Activity |
|----------|---------|---------|----------------|
| Poll interval | Check parent router for buffered messages | 1–5 seconds | MAC-layer data request (~10 bytes, ~2ms radio on) |
| Heartbeat interval | Send telemetry to Hub | Configurable (30s for testing) | Full CoAP POST (~50 bytes, ~5ms radio on) |

The poll is a lightweight MAC-layer operation. The node is already waking every 1–5 seconds — commands sent via CON are delivered on the next poll, not the next heartbeat.

### Command Delivery to Sleeping Nodes

1. Hub sends CoAP CON to node's mesh-local address
2. The parent router (typically the Hub's H2 itself) buffers the message
3. On the node's next poll (1–5 seconds), the parent delivers the buffered message
4. Node processes the command and responds

Command latency = **poll interval** (1–5 seconds), not heartbeat interval.

### CoAP Retransmission

CoAP CON uses exponential backoff: initial 2s, doubled up to ~30s, max 4 retransmissions (RFC 7252 §4.2). For SEDs with a 1-second poll interval, the initial retransmission at ~3 seconds reliably catches the second poll.

### Battery Optimization Guidelines

- Use **NON** for status heartbeats — no ACK wait, radio sleeps immediately after TX
- Use **CON** only when delivery matters: register, command_ack, command_result
- Batch inventory reports with heartbeats when possible (send inventory immediately after heartbeat in the same wake cycle)
- Increase poll interval during extended idle periods (no user interaction)
- Heartbeat interval is configurable per deployment — longer intervals save proportionally more power

---

## Cloud Relay Pipeline

Mesh nodes have no direct cloud connectivity. The Hub relays their heartbeats to the cloud as **relayed heartbeats** on the `device_heartbeats` table.

### Data Flow

```
Node                    H2 (Thread BR)           S3 (WiFi Master)         Supabase
  │                        │                         │                      │
  │  POST /heartbeat       │                         │                      │
  │  (CBOR)                │                         │                      │
  │───────────────────────>│                         │                      │
  │                        │                         │                      │
  │                        │  Decode CBOR             │                      │
  │                        │  Look up identity        │                      │
  │                        │  from /register cache    │                      │
  │                        │                         │                      │
  │                        │  UART EVT (binary)       │                      │
  │                        │  [ext_addr + telemetry]  │                      │
  │                        │────────────────────────>│                      │
  │                        │                         │                      │
  │                        │                         │  Build JSON payload:  │
  │                        │                         │  {                    │
  │                        │                         │    mac_address,       │
  │                        │                         │    unit_id,           │
  │                        │                         │    device_type,       │
  │                        │                         │    firmware_version,  │
  │                        │                         │    type,              │
  │                        │                         │    telemetry: {...},  │
  │                        │                         │    relay_device_type: │
  │                        │                         │      "hub",          │
  │                        │                         │    relay_instance_id  │
  │                        │                         │  }                    │
  │                        │                         │                      │
  │                        │                         │  POST /rest/v1/      │
  │                        │                         │  device_heartbeats   │
  │                        │                         │─────────────────────>│
  │                        │                         │                      │
  │                        │                         │              Trigger: │
  │                        │                         │  sync_heartbeat_to_  │
  │                        │                         │  device_and_unit()   │
```

### Relay Fields

The S3 adds these fields when posting to `device_heartbeats`:

| Field | Value | Description |
|-------|-------|-------------|
| `relay_device_type` | `"hub"` | Identifies the Hub as the relay |
| `relay_instance_id` | Hub's device instance UUID | Which Hub relayed this heartbeat |

### Telemetry Mapping

The S3 places all capability telemetry fields into the `telemetry` JSONB column. The database trigger `sync_heartbeat_to_device_and_unit` extracts known fields to typed columns on the `units` table:

| CBOR Field | `telemetry` Key | Extracted To |
|------------|----------------|-------------|
| `battery_level` | `battery_level` | `units.battery_level` |
| `battery_charging` | `battery_charging` | `units.battery_charging` |
| `thread_rssi` | `thread_rssi` | — |
| `temperature_c` | `temperature_c` | `units.temperature_c` |
| `humidity_pct` | `humidity_pct` | `units.humidity_pct` |
| `uptime_sec` | `uptime_sec` | — |
| `free_heap` | `free_heap` | — |
| `min_free_heap` | `min_free_heap` | — |

Unknown telemetry keys are preserved in the `telemetry` JSONB column and are available for future extraction without schema changes.

### Identity Fields

The S3 populates identity from the H2's register cache (forwarded via UART) or its own cache:

| Cloud Field | Source |
|-------------|--------|
| `mac_address` | `/register` cache → `mac` |
| `unit_id` | `/register` cache → `unit_id` |
| `device_type` | `/register` cache → `type` |
| `firmware_version` | `/register` cache → `fw` |

---

## Version Compatibility

### CBOR Map Extensibility

- **Receivers MUST ignore unknown keys.** A node may send telemetry fields that the Hub does not recognize (new capability in newer firmware). The Hub passes them through to the cloud.
- **Senders MAY add new keys** without version negotiation. New firmware versions can add telemetry fields to heartbeats. The Hub and cloud handle them transparently via CBOR maps and JSONB.

### Protocol Version Field

The `"v": 1` field in heartbeats allows future breaking changes to the heartbeat format. If a receiver encounters an unknown version, it SHOULD attempt to process what it can and log a warning.

### Legacy 3-Byte Binary Fallback

During the migration period, the Hub's CoAP server SHOULD detect the payload format:

1. If the CoAP Content-Format option is 60 (CBOR), or the payload parses as valid CBOR: use the CBOR parser.
2. If the Content-Format option is absent AND the payload is exactly 3 bytes: fall back to the legacy binary parser (`[battery_pct, rssi, tag_count]`).

This allows gradual firmware rollout — nodes with old firmware continue to work.

### Deprecated Endpoints

- **GET /config**: Deprecated. Configuration is pushed to nodes via `POST /cmd`. Will be removed in a future version.

---

## Implementation Notes

### CBOR Library

**Recommended: `nanocbor`** — header-only C library, zero heap allocation, streaming encoder/decoder. Available as an ESP-IDF managed component. Suitable for both the H2 (ESP32-H2, ~320 KB SRAM) and constrained node firmware.

### S3-H2 UART Protocol Extensions

The current `s3h2_crate_heartbeat_payload_t` in `s3_h2_protocol.h` is 10 bytes (`ext_addr[8] + battery_percent + rssi`) and cannot carry arbitrary CBOR telemetry. The following extensions are needed:

| New Type | Direction | Purpose |
|----------|-----------|---------|
| `EVT_CRATE_TELEMETRY` | H2 → S3 | Variable-length telemetry event: `ext_addr[8] + type[1] + cbor_len[2] + cbor_data[N]` |
| `CMD_RELAY_CMD` | S3 → H2 | Command relay: `target_ext_addr[8] + cbor_len[2] + cbor_data[N]` |

The CBOR telemetry blob is passed through from CoAP to UART. The S3 decodes the CBOR on its side (it has more resources and already builds JSON for the cloud).

### Hub Registration Cache

- Static array of structs, max 20 entries
- Keyed by mesh-local IPv6 address (16 bytes)
- Fields: `mac` (string, 18 chars), `unit_id` (string, 20 chars), `type` (string, 20 chars), `fw` (string, 12 chars), `caps` (bitmask or string list), `last_seen_ms` (uint32)
- On cache miss for heartbeat: graceful accept with partial cache entry, respond 4.01, send re-register nudge

### Content-Format Option

All CBOR endpoints MUST include the Content-Format: 60 option in both requests and responses. This enables the legacy fallback detection described in [Version Compatibility](#version-compatibility).

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | 2026-02-20 | Simplified POST /cmd to flat command format (removed `capability`/`test_name` fields); added `register` command; expanded unregistered device handling with two-pronged approach (graceful accept + active nudge) |
| 1.0.0 | 2026-02-19 | Initial CoAP Mesh Protocol specification |

---

*This document is proprietary to Saturday Vinyl. Do not distribute externally.*
