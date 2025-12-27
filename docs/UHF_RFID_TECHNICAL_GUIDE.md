# UHF RFID Technical Guide

This document provides a comprehensive technical overview of UHF RFID functionality in the Saturday Vinyl app, including EPC formats, communication protocols, and read/write operations.

## Table of Contents

1. [Overview](#overview)
2. [Hardware](#hardware)
3. [EPC Format Specification](#epc-format-specification)
4. [Communication Protocol](#communication-protocol)
5. [Frame Format](#frame-format)
6. [Commands Reference](#commands-reference)
7. [Tag Operations](#tag-operations)
8. [Error Handling](#error-handling)
9. [Architecture](#architecture)
10. [Implementation Notes](#implementation-notes)

---

## Overview

The Saturday Vinyl app uses UHF RFID tags to uniquely identify vinyl records. Each tag contains a 96-bit EPC (Electronic Product Code) that follows a specific format to identify it as a Saturday Vinyl tag.

### Key Concepts

- **EPC (Electronic Product Code)**: A 96-bit (12-byte) identifier stored on the RFID tag
- **PC (Protocol Control)**: A 16-bit word that contains metadata about the EPC, including its length
- **TID (Tag Identifier)**: A factory-programmed, read-only unique identifier
- **Access Password**: A 32-bit password used to protect tag memory from unauthorized writes

---

## Hardware

### Supported Module

The app communicates with **YRM100** UHF RFID modules over serial (USB-to-Serial).

| Parameter | Value |
|-----------|-------|
| Module | YRM100 |
| Frequency | UHF (860-960 MHz) |
| Protocol | ISO 18000-6C / EPC Gen2 |
| Interface | Serial (USB) |
| Baud Rate | 115200 (default) |
| Data Bits | 8 |
| Stop Bits | 1 |
| Parity | None |

### RF Power

| Setting | Value |
|---------|-------|
| Default | 20 dBm |
| Minimum | 0 dBm |
| Maximum | 30 dBm |

### YRM100 Pinout

The YRM100 module has the following pin configuration:

```
┌─────────────────────────────────────┐
│           YRM100 Module             │
│                                     │
│  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐     │
│  │ 1 │ │ 2 │ │ 3 │ │ 4 │ │ 5 │     │
│  └───┘ └───┘ └───┘ └───┘ └───┘     │
│  GND   VCC   TX    RX    EN        │
└─────────────────────────────────────┘
```

| Pin | Name | Description |
|-----|------|-------------|
| 1 | GND | Ground |
| 2 | VCC | Power supply (3.3V - 5V) |
| 3 | TX | Serial transmit (module → host) |
| 4 | RX | Serial receive (host → module) |
| 5 | EN | Enable pin (active high) |

### Enable Pin (EN)

**IMPORTANT:** The EN pin must be pulled HIGH to enable the module.

| Requirement | Value |
|-------------|-------|
| Minimum voltage | 1.5V |
| Recommended | 3.3V (tied to VCC) |
| When LOW | Module is disabled/in sleep mode |
| When HIGH | Module is active and operational |

**Wiring Notes:**
- For always-on operation, connect EN directly to VCC
- For power management, use a GPIO pin to control EN (ensure ≥1.5V logic level)
- When using USB-to-Serial adapters with DTR control, DTR can be used to control module power via EN

---

## EPC Format Specification

### Saturday Vinyl EPC Structure

```
┌─────────────┬─────────────────────────────────────────┐
│   Prefix    │              Random Data                │
│  (2 bytes)  │              (10 bytes)                 │
├─────────────┼─────────────────────────────────────────┤
│    5356     │    XXXX XXXX XXXX XXXX XXXX             │
│   ("SV")    │    (80 random bits)                     │
└─────────────┴─────────────────────────────────────────┘
       │                      │
       └──────────────────────┴──────────────────────────
                         Total: 96 bits (12 bytes, 24 hex chars)
```

### Format Details

| Component | Size | Description |
|-----------|------|-------------|
| Prefix | 2 bytes (4 hex chars) | `5356` - ASCII "SV" (Saturday Vinyl) |
| Random | 10 bytes (20 hex chars) | Cryptographically random data |
| **Total** | **12 bytes (24 hex chars)** | Complete EPC identifier |

### Example EPCs

```
Valid Saturday EPCs:
  5356A1B2C3D4E5F67890ABCD    (raw)
  5356-A1B2-C3D4-E5F6-7890-ABCD  (formatted for display)

Non-Saturday EPCs (no "5356" prefix):
  E200001234567890ABCDEF12
  300000000000000000000001
```

### Validation Rules

A valid Saturday Vinyl EPC must:
1. Be exactly 24 hexadecimal characters (12 bytes / 96 bits)
2. Start with the prefix `5356` (ASCII "SV")
3. Contain only valid hexadecimal characters (0-9, A-F)

```dart
// Validation example
static bool isValidSaturdayEpc(String epc) {
  if (epc.length != 24) return false;
  if (!epc.toUpperCase().startsWith('5356')) return false;
  return RegExp(r'^[0-9A-Fa-f]{24}$').hasMatch(epc);
}
```

---

## Communication Protocol

### Serial Configuration

```dart
const serialConfig = {
  'baudRate': 115200,
  'dataBits': 8,
  'stopBits': 1,
  'parity': 0,  // None
};
```

### Connection Sequence

1. Open serial port with DTR enabled (powers the module)
2. Wait 300ms for module initialization
3. Send `GetRfPower` command to verify communication
4. Module is ready for operations

---

## Frame Format

### General Frame Structure

All communication uses this frame format:

```
┌────────┬──────┬─────────┬────────┬────────┬────────────┬──────────┬─────┐
│ Header │ Type │ Command │ PL MSB │ PL LSB │ Parameters │ Checksum │ End │
│  0xBB  │ 1B   │   1B    │   1B   │   1B   │  Variable  │    1B    │0x7E │
└────────┴──────┴─────────┴────────┴────────┴────────────┴──────────┴─────┘
```

| Field | Size | Description |
|-------|------|-------------|
| Header | 1 byte | `0xBB` (some responses use `0xBF`) |
| Type | 1 byte | `0x00` = Command, `0x01` = Response, `0x02` = Notice |
| Command | 1 byte | Command/response code |
| PL MSB | 1 byte | Payload length (high byte) |
| PL LSB | 1 byte | Payload length (low byte) |
| Parameters | Variable | Command-specific data |
| Checksum | 1 byte | Sum of Type + Command + PL + Parameters (lowest byte) |
| End | 1 byte | `0x7E` |

### Frame Types

| Type | Value | Description |
|------|-------|-------------|
| Command | `0x00` | Host → Module |
| Response | `0x01` | Module → Host (reply to command) |
| Notice | `0x02` | Module → Host (async notification, e.g., tag found) |

### Checksum Calculation

```dart
int calculateChecksum(int type, int command, List<int> parameters) {
  var sum = type + command;
  sum += (parameters.length >> 8) & 0xFF;  // PL MSB
  sum += parameters.length & 0xFF;          // PL LSB
  for (final param in parameters) {
    sum += param;
  }
  return sum & 0xFF;  // Take lowest byte
}
```

---

## Commands Reference

### Command Codes

| Command | Code | Description |
|---------|------|-------------|
| GetFirmwareVersion | `0x03` | Get module firmware version |
| SinglePoll | `0x22` | Poll for one tag |
| MultiplePoll | `0x27` | Start continuous polling |
| StopMultiplePoll | `0x28` | Stop continuous polling |
| ReadData | `0x39` | Read tag memory |
| WriteEpc | `0x49` | Write to tag memory (EPC bank) |
| LockTag | `0x82` | Lock tag memory regions |
| SetRfPower | `0xB6` | Set RF power level |
| GetRfPower | `0xB7` | Get current RF power |

### Response Codes

| Code | Name | Description |
|------|------|-------------|
| `0x00` | Success | Operation completed successfully |
| `0x0F` | OtherError | General/unspecified error |
| `0x10` | AccessError | Tag locked or password mismatch |
| `0x11` | InvalidCommand | Unrecognized command |
| `0x12` | InvalidParameter | Bad parameter value |
| `0x13` | MemoryOverrun | Address out of range |
| `0x14` | MemoryLocked | Memory region is locked |
| `0x15` | TagNotFound | No tag in field |
| `0x16` | ReadFailed | Read operation failed |
| `0x17` | WriteFailed | Write operation failed |
| `0x18` | LockFailed | Lock operation failed |

### Error Responses

Error responses have command code `0xFF` with error details in parameters:
```
Header: 0xBB
Type:   0x01 (Response)
Cmd:    0xFF (Error indicator)
Params: [error_code, ...additional_info]
```

---

## Tag Operations

### Polling (Reading Tags)

#### Start Continuous Polling

```
Command: 0x27 (MultiplePoll)
Parameters: [0x22, 0x00, 0x00]
  - 0x22: Number of polls (0x22 = 34 or continuous)
  - 0x00, 0x00: Reserved

Frame: BB 00 27 00 03 22 00 00 4C 7E
```

#### Tag Poll Response (Notice Frame)

When a tag is detected, the module sends a notice frame:

```
Header: 0xBB
Type:   0x02 (Notice)
Cmd:    0x22 or 0x27
Params: [RSSI, PC_MSB, PC_LSB, EPC..., CRC16_MSB, CRC16_LSB]
```

**Parsing Tag Data:**

```dart
// Parameters structure:
// [0]      = RSSI (signal strength)
// [1-2]    = PC (Protocol Control word)
// [3..n-2] = EPC bytes
// [n-1..n] = CRC-16 (optional, may be included by module)

// Extract EPC length from PC word (bits 15-11)
final pc = (params[1] << 8) | params[2];
final epcLengthWords = (pc >> 11) & 0x1F;  // 5 bits
final epcLengthBytes = epcLengthWords * 2;

// For 96-bit EPC: PC = 0x3400
//   Bits 15-11 = 00110 = 6 words = 12 bytes
```

**Important:** The YRM100 module may append a CRC-16 after the EPC. Always use the PC word to determine actual EPC length.

#### Stop Polling

```
Command: 0x28 (StopMultiplePoll)
Parameters: (none)

Frame: BB 00 28 00 00 28 7E
```

### Writing EPC

#### Write EPC Command (0x49)

```
Command: 0x49 (WriteEpc / WriteData)
Parameters:
  - Access Password: 4 bytes
  - Memory Bank:     1 byte (0x01 = EPC bank)
  - Start Address:   2 bytes (0x00, 0x02 = word 2, where EPC data starts)
  - Data Length:     2 bytes (0x00, 0x06 = 6 words for 96-bit EPC)
  - EPC Data:        12 bytes
```

**Frame Construction:**

```dart
List<int> buildWriteEpc(List<int> accessPassword, List<int> epcBytes) {
  // accessPassword: 4 bytes (e.g., [0x53, 0x56, 0x12, 0x25])
  // epcBytes: 12 bytes (the new EPC to write)

  final parameters = <int>[
    ...accessPassword,           // 4 bytes
    0x01,                        // Memory bank (EPC)
    0x00, 0x02,                  // Start address (word 2) - 2 bytes
    0x00, 0x06,                  // Data length (6 words) - 2 bytes
    ...epcBytes,                 // 12 bytes of EPC data
  ];

  return buildCommand(0x49, parameters);
}
```

**Example Frame:**
```
BB 00 49 00 15
   53 56 12 25       <- Access Password
   01                <- Memory Bank (EPC)
   00 02             <- Start Address (word 2)
   00 06             <- Data Length (6 words)
   53 56 A1 B2 C3 D4 E5 F6 78 90 AB CD  <- EPC Data
   [checksum] 7E
```

#### Write Response

**Success Response:**
- Type: `0x01` (Response)
- Command: `0x49` (echoes the command)
- Parameters: Tag data (PC + EPC of the written tag)

**Error Response:**
- Command: `0xFF`
- Parameters: `[error_code, ...]`

### Memory Banks

| Bank | Code | Description |
|------|------|-------------|
| Reserved | `0x00` | Kill/Access passwords |
| EPC | `0x01` | EPC identifier + PC/CRC |
| TID | `0x02` | Factory Tag ID (read-only) |
| User | `0x03` | User data area |

### EPC Memory Layout

```
Word 0: CRC-16 (auto-calculated by tag)
Word 1: PC (Protocol Control)
Word 2-7: EPC data (96 bits = 6 words)
```

When writing EPC, start at word 2 to preserve CRC and PC.

---

## Error Handling

### Common Error Scenarios

| Error Code | Scenario | Resolution |
|------------|----------|------------|
| `0x10` | Tag is locked | Use correct access password |
| `0x13` | Memory overrun | Check address/length parameters |
| `0x15` | No tag found | Ensure tag is in RF field |
| `0x17` | Write failed | Retry, check tag is not moving |

### Timeout Handling

| Operation | Recommended Timeout |
|-----------|---------------------|
| Simple commands | 1000ms |
| Write operations | 2000ms |
| Polling interval | 150ms |
| No-tag timeout | 3000ms (for bulk operations) |

### Write Failure Recovery

```dart
if (!writeSuccess) {
  // Log error but continue with other tags
  AppLogger.warning('Write failed for tag (may be locked)');

  // Resume polling to find other tags
  await uhfService.startPolling();
}
```

---

## Architecture

### Key Classes

```
lib/
├── config/
│   ├── rfid_config.dart        # Protocol constants, commands, error codes
│   └── env_config.dart         # Environment config (access password)
├── models/
│   ├── rfid_tag.dart           # Database tag model
│   ├── tag_poll_result.dart    # Parsed tag poll result
│   └── uhf_frame.dart          # Frame parsing, TagPollData
├── services/
│   ├── serial_port_service.dart    # Low-level serial I/O
│   ├── uhf_rfid_service.dart       # High-level RFID operations
│   └── uhf_frame_codec.dart        # Frame encoding/decoding
├── repositories/
│   └── rfid_tag_repository.dart    # Database operations
└── providers/
    ├── uhf_rfid_provider.dart      # Connection state, polling
    ├── bulk_write_provider.dart    # Bulk tag writing
    └── scan_mode_provider.dart     # Tag scanning/lookup
```

### Data Flow

```
┌─────────────────┐     Serial      ┌──────────────────┐
│  YRM100 Module  │◄──────────────►│ SerialPortService │
└─────────────────┘                 └────────┬─────────┘
                                             │
                                    ┌────────▼─────────┐
                                    │ UhfFrameCodec    │
                                    │ (encode/decode)  │
                                    └────────┬─────────┘
                                             │
                                    ┌────────▼─────────┐
                                    │ UhfRfidService   │
                                    │ (high-level API) │
                                    └────────┬─────────┘
                                             │
              ┌──────────────────────────────┼──────────────────────────────┐
              │                              │                              │
     ┌────────▼─────────┐          ┌────────▼─────────┐          ┌────────▼─────────┐
     │ BulkWriteProvider│          │ ScanModeProvider │          │ UhfPollingProvider│
     │ (write new tags) │          │ (lookup tags)    │          │ (raw polling)     │
     └──────────────────┘          └──────────────────┘          └───────────────────┘
```

---

## Implementation Notes

### Detecting Saturday Tags

Always check both prefix AND length:

```dart
bool get isSaturdayTag =>
    epc.length == 12 &&  // 12 bytes = 24 hex chars
    epcHex.toUpperCase().startsWith('5356');
```

### Parsing EPC from Poll Response

The YRM100 module may include a CRC-16 after the EPC. Use the PC word to determine actual EPC length:

```dart
static TagPollData? parseTagPollData(UhfFrame frame) {
  final params = frame.parameters;

  final rssi = params[0];
  final pc = (params[1] << 8) | params[2];

  // Extract EPC length from PC word (bits 15-11)
  final epcLengthWords = (pc >> 11) & 0x1F;
  final epcLengthBytes = epcLengthWords * 2;

  // Only take the actual EPC bytes, ignore trailing CRC
  final epcBytes = params.sublist(3, 3 + epcLengthBytes);

  return TagPollData(rssi: rssi, pc: pc, epcBytes: epcBytes);
}
```

### Access Password

The access password is stored in the environment configuration:

```
# .env
RFID_ACCESS_PASSWORD=53561225
```

Format: 8 hex characters (4 bytes / 32 bits)

Example: `53561225` = `[0x53, 0x56, 0x12, 0x25]`

The password is used for:
- Writing EPC to tags
- Locking tag memory regions
- Accessing locked tags

### Bulk Write Workflow

1. Start polling for tags
2. For each detected tag:
   - Check if it's already a Saturday tag (prefix + length)
   - If Saturday tag: ensure it exists in database
   - If not: generate new EPC, write to tag, save to database
3. Skip already-processed EPCs (cache)
4. Stop after 3 seconds of no new tags

### Database Schema

```sql
CREATE TABLE rfid_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  epc_identifier VARCHAR(24) UNIQUE NOT NULL,
  tid VARCHAR(48),
  status VARCHAR(20) NOT NULL DEFAULT 'generated',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  written_at TIMESTAMPTZ,
  locked_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id)
);
```

### Tag Status Lifecycle

```
generated → written → locked → retired
              ↓
           failed
```

| Status | Description |
|--------|-------------|
| `generated` | EPC created in database, not yet on physical tag |
| `written` | EPC written to physical tag |
| `locked` | Tag memory locked with access password |
| `failed` | Write or lock operation failed |
| `retired` | Tag decommissioned |

---

## Appendix: Quick Reference

### Frame Examples

**Poll Start:**
```
BB 00 27 00 03 22 00 00 4C 7E
```

**Poll Stop:**
```
BB 00 28 00 00 28 7E
```

**Get RF Power:**
```
BB 00 B7 00 00 B7 7E
```

**Tag Notice (96-bit EPC with CRC):**
```
BB 02 22 00 11
   D1                  <- RSSI
   34 00               <- PC (6 words = 12 bytes EPC)
   53 56 A1 B2 C3 D4 E5 F6 78 90 AB CD  <- EPC (12 bytes)
   XX XX               <- CRC-16 (ignored)
   [checksum] 7E
```

### Useful Constants

```dart
// EPC
const epcLengthBytes = 12;
const epcLengthHex = 24;
const epcPrefix = '5356';

// Serial
const defaultBaudRate = 115200;

// Commands
const cmdMultiplePoll = 0x27;
const cmdStopMultiplePoll = 0x28;
const cmdWriteEpc = 0x49;

// Frame
const frameHeader = 0xBB;
const frameEnd = 0x7E;
```

---

## References

- UHF Commands Manual (see `docs/UHF Commands Manual.pdf`)
- ISO 18000-6C / EPC Gen2 specification
- Flutter serial communication: `flutter_libserialport` package
