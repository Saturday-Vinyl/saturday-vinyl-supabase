# Tags Feature Specification

## Overview

This document specifies the UHF RFID tag management feature for the Saturday! Admin App. The Tags feature enables bulk creation, programming, and management of UHF RFID tags that will be used to track vinyl records in customer collections. Products built using the Saturday! production system will contain RFID readers capable of scanning these tags.

## Business Context

### Purpose
- Create infrastructure for asset tracking using UHF RFID tags
- Enable bulk programming of blank tags with unique identifiers
- Provide admin interface for tag lifecycle management
- Store tag data in Supabase for future integration with album/record tracking

### Future Integration
Tags created through this system will eventually be associated with:
- Album/record metadata (future feature)
- Customer vinyl collections
- Product RFID readers for library scanning

### Scale Considerations
- Potentially hundreds of thousands of tags in circulation
- Products will read ~50 tags/second using embedded ESP32 hardware
- Battery-powered readers require efficient scan operations

## Technical Architecture

### Hardware Components

#### UHF RFID Module
- **Protocol**: EPC Class1 Gen2 (ISO 18000-6C)
- **Interface**: UART serial communication
- **Connection**: USB-to-UART adapter (CP2102)
- **Baud Rate**: 115200 (default, configurable)
- **Enable Pin**: Module requires EN pin pulled LOW to energize
- **Documentation**: `/docs/UHF Commands Manual.pdf`

#### Hardware Wiring (CP2102 to UHF Module)
```
CP2102          UHF Module
───────         ──────────
TX      ───────► RX
RX      ◄─────── TX
GND     ───────► GND
DTR     ───────► EN (Enable - active LOW)
5V/3.3V ───────► VCC
```

**EN Pin Control via DTR:**
- The UHF module's EN (enable) pin must be pulled LOW to power on the module
- We use the CP2102's DTR (Data Terminal Ready) pin to control this
- When DTR is asserted (set true in software), the pin goes LOW, enabling the module
- When DTR is deasserted (set false), the pin goes HIGH, disabling the module
- This allows software control of module power state for power management

#### Tag Specifications
- **Memory**: EPC memory bank (96 bits)
- **Protocol**: EPC Class1 Gen2
- **Lockable**: Yes, with 32-bit access password

### EPC Identifier Format

Each tag will be programmed with a 96-bit (12-byte) EPC identifier:

```
┌─────────────────┬────────────────────────────────────────────┐
│  Bytes 0-1      │  Bytes 2-11                                │
│  Prefix         │  Unique Identifier                         │
├─────────────────┼────────────────────────────────────────────┤
│  0x5356 ("SV")  │  Random 80-bit value                       │
└─────────────────┴────────────────────────────────────────────┘
```

**Prefix**: `0x5356` (ASCII "SV" for Saturday Vinyl)
- Enables instant recognition of Saturday! tags without database lookup
- Allows embedded readers to filter out non-Saturday tags efficiently
- Blank/unwritten tags will NOT have this prefix

**Unique Identifier**: 80 random bits
- Provides 2^80 (~1.2 × 10^24) unique values
- Zero practical collision risk at any scale
- Generated server-side and stored in database before writing to tag

### Tag Detection Strategy

**Primary Approach: Prefix-based Detection**

Rather than relying on manufacturer TID (which may not be unique across tag suppliers), the system uses EPC prefix detection:

1. Poll all tags in RF range (returns list of EPCs)
2. Any EPC NOT starting with `0x5356` is considered unwritten/blank
3. Select one unwritten tag and program it with new Saturday! EPC
4. Verify write succeeded by reading back
5. Lock the tag with shared access password
6. Save to database
7. Repeat until no unwritten tags remain or user stops

**Rationale**:
- No dependency on TID uniqueness from tag manufacturer
- Simpler database queries (no TID cross-referencing needed)
- EPC is returned in standard polling - no extra read command
- Works reliably with any tag supplier

**Fallback Documentation**:
If future requirements need TID-based targeting (e.g., for tag traceability):
- TID is captured during write process and stored in database
- TID-based approach would: poll for TIDs → cross-reference database → select specific unwritten tag by TID → write EPC
- This requires verifying TID uniqueness with your specific tag supplier

### Locking Strategy

**Password-Protected Lock**
- All tags locked with a shared 32-bit access password
- Password stored in app configuration (not per-tag)
- Enables authorized reprogramming if needed
- Prevents casual tampering while maintaining operational flexibility

**Lock Process**:
1. Write EPC to tag
2. Verify write by reading back
3. Set access password on tag
4. Lock EPC memory with password protection
5. Verify lock succeeded

## Database Schema

### New Table: `rfid_tags`

```sql
CREATE TABLE rfid_tags (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  epc_identifier VARCHAR(24) NOT NULL UNIQUE, -- 96 bits as hex string (12 bytes = 24 hex chars)
  tid VARCHAR(48), -- Factory TID if captured (variable length, up to 96 bits)
  status VARCHAR(20) NOT NULL DEFAULT 'generated',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  written_at TIMESTAMP WITH TIME ZONE, -- When EPC was written to physical tag
  locked_at TIMESTAMP WITH TIME ZONE, -- When tag was locked
  created_by UUID REFERENCES users(id), -- Admin who created the tag

  CONSTRAINT valid_status CHECK (status IN ('generated', 'written', 'locked', 'failed', 'retired'))
);

-- Primary lookup index (most queries will be by EPC)
CREATE INDEX idx_rfid_tags_epc ON rfid_tags(epc_identifier);

-- Status filtering
CREATE INDEX idx_rfid_tags_status ON rfid_tags(status);

-- Timestamp queries
CREATE INDEX idx_rfid_tags_created ON rfid_tags(created_at DESC);
```

### Tag Status Lifecycle

```
┌───────────┐     ┌─────────┐     ┌────────┐
│ generated │────▶│ written │────▶│ locked │
└───────────┘     └─────────┘     └────────┘
      │                │               │
      │                │               │
      ▼                ▼               ▼
┌──────────────────────────────────────────┐
│                 failed                    │
└──────────────────────────────────────────┘
                       │
                       ▼
               ┌───────────┐
               │  retired  │
               └───────────┘
```

**Status Definitions**:
- **generated**: EPC created in database, not yet written to physical tag
- **written**: Successfully written to tag, not yet locked
- **locked**: Written and password-locked (ready for deployment)
- **failed**: Write or lock operation failed (needs investigation)
- **retired**: Tag decommissioned/removed from circulation

### New Permission: `manage_tags`

```sql
INSERT INTO permissions (name, description)
VALUES ('manage_tags', 'Create, write, and manage RFID tags');
```

### New Role: `tag_manager`

Users with `manage_tags` permission can access the Tags section. Admin users automatically have access to all features including Tags.

## UART Communication Protocol

### Frame Format

All communication with the UHF module uses this frame structure:

```
┌────────┬──────┬─────────┬────────┬────────┬───────────┬──────────┬─────┐
│ Header │ Type │ Command │ PL(MSB)│ PL(LSB)│ Parameter │ Checksum │ End │
│  0xBB  │ 1B   │   1B    │   1B   │   1B   │  Variable │    1B    │0x7E │
└────────┴──────┴─────────┴────────┴────────┴───────────┴──────────┴─────┘
```

**Frame Types**:
- `0x00`: Command (host → module)
- `0x01`: Response (module → host)
- `0x02`: Notice (module → host, async)

**Checksum**: Sum of all bytes from Type to end of Parameter, take lowest byte

### Key Commands

#### Multiple Polling (0x27)
Discover all tags in RF range.

**Command**:
```
BB 00 27 00 03 22 [cycles_high] [cycles_low] [checksum] 7E
```
- `cycles`: Number of polling cycles (0x0000 = continuous until stop)

**Response** (per tag found):
```
BB 02 22 [length] [RSSI] [PC] [EPC...] [checksum] 7E
```

#### Stop Multiple Polling (0x28)
```
BB 00 28 00 00 28 7E
```

#### Write EPC (0x49)
Write data to tag's EPC memory bank.

**Command**:
```
BB 00 49 [length] [password 4B] [mem_bank=1] [start_addr] [word_count] [EPC data...] [checksum] 7E
```
- `mem_bank`: 0x01 for EPC
- `start_addr`: 0x02 (skip PC bytes)
- `word_count`: 0x06 (6 words = 12 bytes = 96 bits)
- `password`: 0x00000000 for unlocked tags

#### Lock Tag (0x82)
Lock memory banks with password protection.

**Command**:
```
BB 00 82 [length] [password 4B] [lock_payload 3B] [checksum] 7E
```

**Lock Payload** (3 bytes = 24 bits):
- Controls lock state for: Kill password, Access password, EPC, TID, User memory
- Each area has 2 bits: [Permalock, Lock]
- For EPC password-protected lock: Set lock bit, clear permalock bit

#### Set Access Password (0x??)
Set the 32-bit access password before locking.

### Error Handling

**Response Status Codes**:
- `0x10`: Success
- `0x11`: Invalid command
- `0x12`: Invalid parameter
- `0x13`: Memory overrun
- `0x14`: Memory locked
- `0x15`: Tag not found
- `0x16`: Read failed
- `0x17`: Write failed
- `0x18`: Lock failed

## User Interface Specification

### Tags Section Access

**Navigation**: Add "Tags" item to sidebar navigation
- Icon: RFID/tag icon
- Position: After existing sections (Settings area)
- Visibility: Only for users with `manage_tags` permission or admin role

### Main View: Tag List

Single primary view following standard CRUD pattern.

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Tags                                          [RFID Module: ● Ready]  │
├─────────────────────────────────────────────────────────────────────────┤
│  [Search...]  [Status ▼]  [Sort ▼]              [Scan] [Add]           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ EPC: 5356-A1B2-C3D4-E5F6-7890-ABCD    Status: ● Locked          │   │
│  │ Created: 2025-01-15 14:32             TID: E200...              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ EPC: 5356-1234-5678-9ABC-DEF0-1234    Status: ● Locked          │   │
│  │ Created: 2025-01-15 14:31             TID: E200...              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
│  [Load More...]                                                         │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│  Activity Log                                              [Clear]      │
│  ─────────────────────────────────────────────────────────────────      │
│  14:32:15 - Tag 5356-A1B2... written successfully                       │
│  14:32:16 - Tag 5356-A1B2... locked successfully                        │
│  14:32:17 - No unwritten tags in range, stopping                        │
└─────────────────────────────────────────────────────────────────────────┘
```

### RFID Module Status Indicator

**Persistent Header Element**:
- Shows connection status at all times
- Click to open connection settings modal/drawer

**States**:
- `● Disconnected` (gray) - No module connected
- `● Connecting...` (yellow) - Attempting connection
- `● Ready` (green) - Connected and operational
- `● Error` (red) - Connection error, click for details

### Connection Settings Modal

```
┌─────────────────────────────────────────────────────┐
│  RFID Module Settings                           [X] │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Serial Port                                        │
│  ┌─────────────────────────────────┐ [Scan Ports]  │
│  │ /dev/tty.usbserial-0001      ▼ │               │
│  └─────────────────────────────────┘               │
│                                                     │
│  Baud Rate                                          │
│  ┌─────────────────────────────────┐               │
│  │ 115200                       ▼ │               │
│  └─────────────────────────────────┘               │
│                                                     │
│  RF Power                                           │
│  [────────────●──────] 20 dBm                      │
│  (Lower = shorter range, easier single-tag writes) │
│                                                     │
│  Access Password                                    │
│  ┌─────────────────────────────────┐               │
│  │ ••••••••                        │               │
│  └─────────────────────────────────┘               │
│                                                     │
│  [Test Connection]                                  │
│                                                     │
│  Status: Connected - Module responding              │
│                                                     │
│              [Disconnect]  [Save & Connect]         │
└─────────────────────────────────────────────────────┘
```

**Settings Persistence**: Save last-used port, baud rate, and RF power between sessions.

### Add Mode (Bulk Write)

**Trigger**: User clicks "Add" button

**Behavior**:
1. Button changes to "Stop" (red)
2. Activity log shows "Starting bulk write mode..."
3. System continuously polls for tags in range
4. For each tag without `0x5356` prefix:
   - Generate new EPC (prefix + random 80 bits)
   - Insert database record with status `generated`
   - Write EPC to tag
   - Update status to `written`, log success
   - Lock tag with access password
   - Update status to `locked`, log success
   - Tag appears in list immediately
5. Continue until:
   - No unwritten tags detected for 2 seconds, OR
   - User clicks "Stop"
6. Activity log shows summary: "Bulk write complete: X tags created"

**Error Handling**:
- On any write/lock failure: STOP immediately
- Log detailed error information
- Keep failed tag in database with status `failed`
- Display error alert to user for debugging

### Scan Mode (Read)

**Trigger**: User clicks "Scan" button

**Behavior**:
1. Button changes to "Stop Scanning" (blue)
2. Activity log shows "Scanning for tags..."
3. System polls for tags in range
4. For each tag with `0x5356` prefix:
   - Look up EPC in database
   - If found: Highlight/filter that row in the list
   - If not found: Log "Unknown Saturday! tag: [EPC]"
5. Non-Saturday tags (without prefix) are ignored
6. Continue until user clicks "Stop Scanning"
7. Filter remains applied until user clears it

### Tag Detail View

Clicking a tag row opens detail view (slide-over or modal):

```
┌─────────────────────────────────────────────────────┐
│  Tag Details                                    [X] │
├─────────────────────────────────────────────────────┤
│                                                     │
│  EPC Identifier                                     │
│  5356-A1B2-C3D4-E5F6-7890-ABCD                     │
│                                                     │
│  Status                                             │
│  ● Locked                                          │
│                                                     │
│  Factory TID                                        │
│  E2003412B802011234567890                          │
│                                                     │
│  Timeline                                           │
│  ├─ Created: 2025-01-15 14:32:10 by admin@...     │
│  ├─ Written: 2025-01-15 14:32:12                  │
│  └─ Locked:  2025-01-15 14:32:14                  │
│                                                     │
│  ─────────────────────────────────────────────────  │
│                                                     │
│  [Mark as Retired]                                  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Search and Filter

**Search**: Filter by EPC (partial match)
**Status Filter**: Dropdown with options:
- All
- Generated (pending write)
- Written (pending lock)
- Locked (ready)
- Failed
- Retired

**Sort Options**:
- Created (newest first) - default
- Created (oldest first)
- EPC (A-Z)
- Status

## Implementation Architecture

### File Structure

```
lib/
├── models/
│   └── rfid_tag.dart              # RfidTag model with JSON serialization
│
├── repositories/
│   └── rfid_tag_repository.dart   # Supabase CRUD operations
│
├── providers/
│   └── rfid_tag_provider.dart     # Riverpod state management
│
├── services/
│   └── uhf_rfid_service.dart      # UART communication, commands, parsing
│
├── screens/
│   └── tags/
│       ├── tag_list_screen.dart   # Main CRUD view
│       └── tag_detail_screen.dart # Tag detail modal/view
│
└── widgets/
    └── tags/
        ├── rfid_module_status.dart    # Persistent status indicator
        ├── rfid_connection_modal.dart # Connection settings
        ├── tag_list_item.dart         # Individual tag row
        └── tag_activity_log.dart      # Scrolling activity log
```

### Service Layer: UhfRfidService

```dart
class UhfRfidService {
  // Connection management
  Future<void> connect(String port, int baudRate);
  Future<void> disconnect();
  bool get isConnected;
  Stream<ConnectionStatus> get connectionStatus;

  // Configuration
  Future<void> setRfPower(int dbm);
  Future<void> setAccessPassword(List<int> password);

  // Tag operations
  Stream<TagPollResult> startPolling();
  Future<void> stopPolling();
  Future<bool> writeEpc(List<int> epc, {List<int>? password});
  Future<bool> lockTag(List<int> password);
  Future<List<int>?> readTid();

  // Frame encoding/decoding
  List<int> buildCommand(int command, List<int> params);
  ParsedFrame parseResponse(List<int> bytes);
}
```

### Provider Layer

```dart
// Connection state
final rfidConnectionProvider = StateNotifierProvider<RfidConnectionNotifier, RfidConnectionState>;

// Tag list with filtering
final rfidTagsProvider = FutureProvider.family<List<RfidTag>, TagFilter>;

// Single tag lookup
final rfidTagProvider = FutureProvider.family<RfidTag?, String>; // by EPC

// Bulk write controller
final bulkWriteProvider = StateNotifierProvider<BulkWriteNotifier, BulkWriteState>;

// Scan mode controller
final scanModeProvider = StateNotifierProvider<ScanModeNotifier, ScanModeState>;
```

## Configuration

### App Settings

Store in local preferences (not synced):
- `rfid_port`: Last used serial port
- `rfid_baud_rate`: Baud rate (default: 115200)
- `rfid_power`: RF power level in dBm (default: 20)

Store securely (keychain/secure storage):
- `rfid_access_password`: 32-bit access password as hex string

### Environment Configuration

```dart
class RfidConfig {
  static const epcPrefix = [0x53, 0x56]; // "SV"
  static const epcLength = 12; // bytes
  static const defaultBaudRate = 115200;
  static const defaultRfPower = 20; // dBm
  static const pollingIntervalMs = 150;
  static const noTagTimeoutMs = 2000; // Stop bulk write after 2s with no new tags
}
```

## Testing Recommendations

### Unit Tests
- [ ] EPC generation (correct prefix, correct length, uniqueness)
- [ ] Frame encoding/checksum calculation
- [ ] Frame parsing and error detection
- [ ] Tag status transitions
- [ ] Repository CRUD operations

### Integration Tests
- [ ] Serial port connection/disconnection
- [ ] Module command/response cycle
- [ ] Write → verify → lock workflow
- [ ] Database record creation and updates
- [ ] Bulk write with multiple tags

### Manual Testing Checklist
- [ ] Connect to RFID module via USB adapter
- [ ] Scan for ports, select correct port
- [ ] Test connection (module responds)
- [ ] Adjust RF power
- [ ] Scan mode finds existing tags
- [ ] Add mode writes to blank tags
- [ ] Verify write by re-scanning
- [ ] Confirm lock prevents re-write (without password)
- [ ] Error handling when no module connected
- [ ] Error handling on write failure
- [ ] Settings persist between sessions

### Hardware Test Notes
- Test with your specific tag supplier to verify:
  - Default/blank EPC pattern (typically all zeros)
  - TID uniqueness (if TID tracking is needed later)
  - Lock behavior with access password

## Security Considerations

### Access Control
- Tags section only accessible to users with `manage_tags` permission or admin role
- All tag operations logged with user ID

### Access Password
- Stored locally in secure storage (macOS Keychain, etc.)
- Not stored in database (shared across all tags)
- Consider password rotation strategy for future

### Data Integrity
- EPC uniqueness enforced at database level
- All writes verified by read-back before marking complete

## Future Considerations

### Potential Enhancements
1. **Album Association**: Link tags to album/record metadata
2. **Batch Tracking**: Group tags by creation batch for traceability
3. **Export/Import**: Bulk export tag data for inventory management
4. **Mobile Read Support**: Bluetooth RFID readers for mobile scanning
5. **Product Integration**: ESP32 firmware for reading tags from Saturday! products
6. **Analytics Dashboard**: Tag creation trends, failure rates, etc.

### Embedded Reader Integration
Future products will contain RFID readers (ESP32-based). Considerations:
- Readers will use same EPC prefix detection (`0x5356`)
- No database lookup needed to identify Saturday! tags
- Backend API for tag → album lookups (future feature)
- Efficient batch queries for scanning large collections

## Dependencies

### Flutter Packages
- `flutter_libserialport` or `serial_port_win32`: Serial communication
- `flutter_riverpod`: State management
- `flutter_secure_storage`: Secure password storage

### Platform Support
- **macOS**: Primary target (USB serial via CP2102)
- **Windows**: Supported (may need driver installation for CP2102)
- **Linux**: Supported
- **Mobile**: Not supported for this feature (desktop only)

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-01-XX | - | Initial specification |
