# Tags Feature - Implementation Prompt Plan

## Overview

This document contains a series of prompts for implementing the UHF RFID Tags feature in the Saturday! Admin App. Each prompt builds incrementally, ensuring a working application at every stage.

**Reference Specification:** [TAGS_FEATURE_SPEC.md](./TAGS_FEATURE_SPEC.md)

**Development Approach:**
- Incremental, testable steps
- Data layer first, then service layer, then UI
- Desktop only (no mobile considerations)
- Integration after each step

**Key Dependencies:**
- UHF RFID module connected via USB-to-UART (CP2102)
- Supabase backend for tag storage
- Existing Saturday! Admin App infrastructure

---

## Phase 1: Database and Data Layer (Prompts T1-T2)

### Prompt T1: Database Schema and Model

**Context:** Create the database schema for RFID tags and the corresponding Flutter model. This is the foundation for all tag operations.

**Reference:** See TAGS_FEATURE_SPEC.md sections "Database Schema" and "EPC Identifier Format"

**Prompt:**

```
I'm implementing a UHF RFID tag management feature for the Saturday! Admin App. Let's start with the database schema and data model.

Reference the specification at docs/TAGS_FEATURE_SPEC.md for full context.

1. Create the Supabase migration file at supabase/migrations/XXX_rfid_tags.sql with:
   - rfid_tags table with columns:
     - id (UUID, primary key)
     - epc_identifier (VARCHAR(24), unique, not null) - 96-bit EPC as 24 hex characters
     - tid (VARCHAR(48), nullable) - Factory TID if captured
     - status (VARCHAR(20), not null, default 'generated') - with CHECK constraint for valid values
     - created_at (TIMESTAMPTZ, default NOW())
     - updated_at (TIMESTAMPTZ, default NOW())
     - written_at (TIMESTAMPTZ, nullable)
     - locked_at (TIMESTAMPTZ, nullable)
     - created_by (UUID, foreign key to users)
   - Index on epc_identifier (primary lookup path)
   - Index on status
   - Index on created_at DESC
   - Row Level Security policies for authenticated users

2. Add the 'manage_tags' permission to the permissions table:
   - INSERT INTO permissions (name, description) VALUES ('manage_tags', 'Create, write, and manage RFID tags')

3. Create lib/models/rfid_tag.dart with:
   - RfidTag model class with all properties matching the database schema
   - Status enum: generated, written, locked, failed, retired
   - fromJson/toJson methods for Supabase serialization
   - copyWith method for immutability
   - Equality and hashCode overrides
   - Helper method: bool get isSaturdayTag - checks if EPC starts with "5356" prefix
   - Static method: String generateEpc() - generates new EPC with "5356" prefix + random 80 bits

4. Write unit tests in test/models/rfid_tag_test.dart:
   - Test fromJson/toJson serialization
   - Test copyWith creates new instances correctly
   - Test generateEpc() produces valid format (24 hex chars, starts with 5356)
   - Test generateEpc() produces unique values
   - Test isSaturdayTag correctly identifies Saturday tags
   - Test status enum serialization

Ensure all tests pass before proceeding.
```

**Expected Outcome:**
- Database migration ready to apply
- RfidTag model with all properties and helpers
- EPC generation with "SV" (0x5356) prefix
- Comprehensive unit tests
- All tests passing

---

### Prompt T2: Tag Repository

**Context:** Create the repository layer for RFID tag CRUD operations against Supabase.

**Prompt:**

```
Now let's create the repository layer for RFID tag operations.

Reference the specification at docs/TAGS_FEATURE_SPEC.md for context.

1. Create lib/repositories/rfid_tag_repository.dart with:
   - Constructor that takes Supabase client
   - Method: Future<List<RfidTag>> getTags({TagFilter? filter, int limit = 50, int offset = 0})
     - Support filtering by status
     - Support search by EPC (partial match)
     - Sort by created_at DESC by default
     - Paginated results
   - Method: Future<RfidTag?> getTagByEpc(String epc)
     - Look up single tag by EPC identifier
     - Return null if not found
   - Method: Future<List<RfidTag>> getTagsByEpcs(List<String> epcs)
     - Bulk lookup for scan mode
     - Returns all matching tags
   - Method: Future<RfidTag> createTag(String epc, String? createdBy)
     - Insert new tag with status 'generated'
     - Return created tag
   - Method: Future<RfidTag> updateTagStatus(String id, RfidTagStatus status, {String? tid})
     - Update tag status
     - Set written_at when transitioning to 'written'
     - Set locked_at when transitioning to 'locked'
     - Optionally set TID
   - Method: Future<void> retireTag(String id)
     - Set status to 'retired'
   - Method: Future<int> getTagCount({RfidTagStatus? status})
     - Count tags, optionally filtered by status
   - All methods should include proper error handling and logging

2. Create lib/models/tag_filter.dart with:
   - TagFilter class for query parameters
   - Properties: status, searchQuery, sortBy, sortAscending
   - copyWith method

3. Create lib/providers/rfid_tag_provider.dart with Riverpod:
   - rfidTagRepositoryProvider - singleton repository instance
   - rfidTagsProvider(TagFilter) - FutureProvider.family for filtered tag list
   - rfidTagByEpcProvider(String) - FutureProvider.family for single tag lookup
   - rfidTagCountProvider(RfidTagStatus?) - FutureProvider for count

4. Write unit tests in test/repositories/rfid_tag_repository_test.dart using mocks:
   - Test getTags with various filters
   - Test getTagByEpc returns correct tag or null
   - Test getTagsByEpcs bulk lookup
   - Test createTag inserts correctly
   - Test updateTagStatus transitions
   - Test pagination

5. Write provider tests in test/providers/rfid_tag_provider_test.dart

Run all tests to ensure the data layer is working correctly.
```

**Expected Outcome:**
- Complete repository with CRUD operations
- Query filtering and pagination
- Riverpod providers for state management
- Comprehensive tests for repository
- Provider tests

---

## Phase 2: UART Communication Service (Prompts T3-T5)

### Prompt T3: Serial Port Foundation

**Context:** Set up serial port communication infrastructure for the UHF RFID module. The UHF module requires an EN (enable) pin to be pulled low to energize the module. We'll use the CP2102's DTR pin to control this.

**Prompt:**

```
Let's build the serial port communication layer for the UHF RFID module.

Reference docs/TAGS_FEATURE_SPEC.md section "UART Communication Protocol" and the UHF module documentation at docs/UHF Commands Manual.pdf.

IMPORTANT: The UHF RFID module requires an EN (enable) pin to be pulled LOW to energize the module. We will use the CP2102 USB adapter's DTR (Data Terminal Ready) pin to control this. When DTR is asserted (set true), it goes LOW, which enables the module. When DTR is deasserted, the module is disabled.

1. Add serial port dependency to pubspec.yaml:
   - flutter_libserialport: ^0.4.0 (or latest stable)

2. Create lib/services/serial_port_service.dart with:
   - Method: Future<List<String>> getAvailablePorts()
     - List all available serial ports on the system
     - Filter for likely USB-to-UART adapters if possible
   - Method: Future<bool> connect(String portName, int baudRate)
     - Open serial port with specified settings
     - Configure: 8 data bits, no parity, 1 stop bit
     - Assert DTR (set true) to enable the RFID module (pulls EN pin LOW)
     - Add small delay (100ms) after enabling to allow module to initialize
     - Return true on success, false on failure
   - Method: void disconnect()
     - Deassert DTR (set false) to disable the RFID module before closing
     - Close serial port connection
   - Method: bool get isConnected
     - Return current connection status
   - Method: Stream<List<int>> get dataStream
     - Stream of incoming bytes from serial port
   - Method: Future<bool> write(List<int> data)
     - Write bytes to serial port
     - Return true on success
   - Method: void setModuleEnabled(bool enabled)
     - Control DTR pin to enable/disable module
     - enabled=true: Assert DTR (LOW on EN pin, module ON)
     - enabled=false: Deassert DTR (HIGH on EN pin, module OFF)
   - Method: bool get isModuleEnabled
     - Return current DTR state
   - Proper resource cleanup on disconnect (ensure DTR deasserted)
   - Error handling with descriptive messages
   - Logging for all operations

3. Create lib/models/serial_connection_state.dart with:
   - Enum: SerialConnectionStatus (disconnected, connecting, connected, error)
   - SerialConnectionState class with: status, portName, baudRate, errorMessage, isModuleEnabled
   - copyWith method

4. Create lib/config/rfid_config.dart with constants:
   - EPC_PREFIX: [0x53, 0x56] ("SV")
   - EPC_LENGTH: 12 (bytes)
   - DEFAULT_BAUD_RATE: 115200
   - DEFAULT_RF_POWER: 20 (dBm)
   - POLLING_INTERVAL_MS: 150
   - NO_TAG_TIMEOUT_MS: 2000
   - FRAME_HEADER: 0xBB
   - FRAME_END: 0x7E
   - MODULE_ENABLE_DELAY_MS: 100 (delay after enabling module)

5. Write unit tests in test/services/serial_port_service_test.dart:
   - Test getAvailablePorts returns list
   - Test connect/disconnect lifecycle
   - Test connect asserts DTR on successful connection
   - Test disconnect deasserts DTR before closing
   - Test setModuleEnabled controls DTR state
   - Test write returns success/failure
   - Mock serial port for testing

Focus on getting the serial communication foundation working with proper EN pin control via DTR. We'll add UHF-specific commands in the next prompt.
```

**Expected Outcome:**
- Serial port service for basic communication
- DTR-based EN pin control for module power management
- Port listing and connection management
- Configuration constants for RFID
- Connection state model
- Tests for serial operations including DTR control

---

### Prompt T4: UHF Command Frame Protocol

**Context:** Implement the UHF module command frame encoding/decoding based on the protocol specification.

**Prompt:**

```
Now let's implement the UHF module command frame protocol.

Reference docs/TAGS_FEATURE_SPEC.md section "UART Communication Protocol" and docs/UHF Commands Manual.pdf for frame format details.

Frame format: [Header 0xBB] [Type] [Command] [PL MSB] [PL LSB] [Parameters...] [Checksum] [End 0x7E]

1. Create lib/services/uhf_frame_codec.dart with:
   - Static method: List<int> buildCommand(int command, List<int> parameters)
     - Build complete frame with header, type (0x00 for command), command byte
     - Calculate payload length (parameters length)
     - Calculate checksum: sum of bytes from Type to end of Parameters, take lowest byte
     - Append end byte (0x7E)
     - Return complete frame as byte list
   - Static method: UhfFrame? parseFrame(List<int> bytes)
     - Parse incoming bytes into UhfFrame
     - Validate header (0xBB) and end (0x7E)
     - Verify checksum
     - Extract type, command, parameters
     - Return null if invalid frame
   - Static method: bool validateChecksum(List<int> frame)
     - Verify frame checksum is correct

2. Create lib/models/uhf_frame.dart with:
   - UhfFrame class with: type, command, parameters, isValid
   - FrameType enum: command (0x00), response (0x01), notice (0x02)
   - Factory constructor from raw bytes
   - Helper getters for common response fields

3. Create lib/models/uhf_commands.dart with command constants:
   - SINGLE_POLL: 0x22
   - MULTI_POLL: 0x27
   - STOP_MULTI_POLL: 0x28
   - READ_DATA: 0x39
   - WRITE_EPC: 0x49
   - LOCK_TAG: 0x82
   - SET_RF_POWER: 0xB6
   - GET_RF_POWER: 0xB7

4. Create lib/models/uhf_response_codes.dart with response status codes:
   - SUCCESS: 0x10
   - INVALID_COMMAND: 0x11
   - INVALID_PARAMETER: 0x12
   - MEMORY_OVERRUN: 0x13
   - MEMORY_LOCKED: 0x14
   - TAG_NOT_FOUND: 0x15
   - READ_FAILED: 0x16
   - WRITE_FAILED: 0x17
   - LOCK_FAILED: 0x18
   - Helper method: String getErrorMessage(int code)

5. Write comprehensive unit tests in test/services/uhf_frame_codec_test.dart:
   - Test buildCommand produces correct frame format
   - Test checksum calculation with known values
   - Test parseFrame extracts correct fields
   - Test parseFrame rejects invalid frames (bad header, bad checksum, bad end)
   - Test round-trip: build then parse returns same data
   - Test with example frames from the UHF manual

6. Write tests in test/models/uhf_frame_test.dart for frame model

Ensure all frame encoding/decoding tests pass before proceeding.
```

**Expected Outcome:**
- Frame codec for building and parsing UHF commands
- Command and response code constants
- UhfFrame model for parsed responses
- Comprehensive codec tests with known test vectors
- Error message helpers

---

### Prompt T5: UHF RFID Service

**Context:** Build the high-level UHF RFID service that combines serial communication with command protocol for tag operations.

**Prompt:**

```
Now let's build the complete UHF RFID service that combines serial communication with the command protocol.

Reference docs/TAGS_FEATURE_SPEC.md sections "UART Communication Protocol" and "Tag Detection Strategy".

1. Create lib/services/uhf_rfid_service.dart with:

   Connection Management:
   - Constructor takes SerialPortService
   - Method: Future<bool> connect(String port, int baudRate)
   - Method: void disconnect()
   - Getter: bool isConnected
   - Getter: Stream<SerialConnectionState> connectionStateStream

   Configuration:
   - Method: Future<bool> setRfPower(int dbm)
     - Build SET_RF_POWER command
     - Send and verify response
   - Method: Future<int?> getRfPower()
     - Build GET_RF_POWER command
     - Parse and return current power level
   - Property: accessPassword (List<int>, 4 bytes) - stored in memory, set from config

   Tag Polling:
   - Method: Stream<TagPollResult> startPolling()
     - Send MULTI_POLL command with continuous mode
     - Parse incoming notice frames (type 0x02)
     - For each tag found, extract EPC and RSSI
     - Yield TagPollResult for each tag
     - Continue until stopPolling called
   - Method: Future<void> stopPolling()
     - Send STOP_MULTI_POLL command
     - Wait for acknowledgment

   Tag Operations:
   - Method: Future<WriteResult> writeEpc(List<int> newEpc)
     - Build WRITE_EPC command for EPC memory bank
     - Memory bank: 0x01 (EPC)
     - Start address: 0x02 (skip PC bytes)
     - Word count: 0x06 (6 words = 12 bytes)
     - Use stored access password (0x00000000 for unlocked tags)
     - Send command and parse response
     - Return WriteResult with success/failure and error details
   - Method: Future<bool> verifyEpc(List<int> expectedEpc)
     - Poll for tags
     - Check if any tag has the expected EPC
     - Return true if found
   - Method: Future<LockResult> lockTag(List<int> accessPassword)
     - Build LOCK command to password-protect EPC memory
     - Set access password on tag first
     - Lock EPC memory with password protection (not permalock)
     - Return LockResult with success/failure

   Frame Handling:
   - Private: Frame accumulator buffer for handling partial reads
   - Private: Parse complete frames from buffer
   - Private: Route parsed frames to appropriate handlers

2. Create lib/models/tag_poll_result.dart with:
   - epc (List<int>)
   - rssi (int)
   - Getter: String epcHex - EPC as hex string
   - Getter: bool isSaturdayTag - checks for 0x5356 prefix

3. Create lib/models/write_result.dart with:
   - success (bool)
   - errorCode (int?)
   - errorMessage (String?)

4. Create lib/models/lock_result.dart with:
   - success (bool)
   - errorCode (int?)
   - errorMessage (String?)

5. Create lib/providers/uhf_rfid_provider.dart with:
   - uhfRfidServiceProvider - singleton service instance
   - uhfConnectionStateProvider - stream of connection state
   - uhfPollingProvider - StateNotifier for polling control

6. Write integration tests in test/services/uhf_rfid_service_test.dart:
   - Test connect/disconnect flow
   - Test setRfPower sends correct command
   - Test polling starts and can be stopped
   - Test writeEpc builds correct command frame
   - Test frame accumulator handles partial reads
   - Use mocked serial port

Focus on correct command construction and response parsing. Actual hardware testing will come later.
```

**Expected Outcome:**
- Complete UHF RFID service
- Polling, writing, and locking operations
- Frame accumulation for handling serial data
- Result models for operations
- Riverpod providers
- Integration tests with mocked serial port

---

## Phase 3: Settings and Configuration (Prompts T6-T7)

### Prompt T6: RFID Module Settings Persistence

**Context:** Implement settings persistence for RFID module configuration (port, baud rate, RF power, access password).

**Prompt:**

```
Let's implement settings persistence for the RFID module configuration.

Reference docs/TAGS_FEATURE_SPEC.md section "Configuration".

1. Create lib/services/rfid_settings_service.dart with:
   - Uses shared_preferences for non-sensitive settings
   - Uses flutter_secure_storage for access password
   - Method: Future<void> savePort(String port)
   - Method: Future<String?> getPort()
   - Method: Future<void> saveBaudRate(int baudRate)
   - Method: Future<int> getBaudRate() - default 115200
   - Method: Future<void> saveRfPower(int dbm)
   - Method: Future<int> getRfPower() - default 20
   - Method: Future<void> saveAccessPassword(String passwordHex)
     - Store in secure storage
   - Method: Future<String?> getAccessPassword()
     - Retrieve from secure storage
   - Method: Future<RfidSettings> loadAllSettings()
     - Load all settings into RfidSettings object
   - Method: Future<void> clearSettings()
     - Clear all stored settings

2. Create lib/models/rfid_settings.dart with:
   - port (String?)
   - baudRate (int)
   - rfPower (int)
   - accessPassword (String?)
   - copyWith method
   - Factory: RfidSettings.defaults() with default values

3. Create lib/providers/rfid_settings_provider.dart with:
   - rfidSettingsServiceProvider - singleton
   - rfidSettingsProvider - AsyncNotifier for settings state
     - load() - load settings from storage
     - updatePort(String)
     - updateBaudRate(int)
     - updateRfPower(int)
     - updateAccessPassword(String)
   - Methods auto-save to storage on change

4. Add flutter_secure_storage to pubspec.yaml if not already present

5. Write unit tests in test/services/rfid_settings_service_test.dart:
   - Test save and retrieve port
   - Test save and retrieve baud rate
   - Test default values when not set
   - Test secure storage for password
   - Test loadAllSettings aggregation
   - Test clearSettings

6. Write provider tests in test/providers/rfid_settings_provider_test.dart

Settings persistence is critical for user experience - they shouldn't have to reconfigure the module every session.
```

**Expected Outcome:**
- Settings service with secure password storage
- Settings model
- Riverpod provider for reactive settings
- Persistence across app restarts
- Comprehensive tests

---

### Prompt T7: Connection Settings Modal

**Context:** Build the UI modal for configuring RFID module connection settings.

**Prompt:**

```
Let's build the connection settings modal for the RFID module.

Reference docs/TAGS_FEATURE_SPEC.md section "Connection Settings Modal" for the UI specification.

1. Create lib/widgets/tags/rfid_connection_modal.dart with:
   - Modal dialog for RFID module configuration
   - Port Selection:
     - Dropdown populated from SerialPortService.getAvailablePorts()
     - "Scan Ports" button to refresh list
     - Show "No ports found" message if empty
   - Baud Rate Selection:
     - Dropdown with options: 9600, 19200, 38400, 57600, 115200
     - Default: 115200
   - RF Power Slider:
     - Range: 0-30 dBm
     - Show current value
     - Helper text: "Lower = shorter range, easier single-tag writes"
   - Access Password Field:
     - Obscured text input
     - 8 hex characters (32 bits)
     - Validation: must be valid hex
   - Test Connection Button:
     - Attempt to connect with current settings
     - Send a simple command (e.g., GET_RF_POWER) to verify module responds
     - Show success/failure message
   - Status Display:
     - Current connection status
     - Error message if connection failed
   - Action Buttons:
     - "Disconnect" (if connected)
     - "Save & Connect" - save settings and connect
     - "Cancel" - close without saving

2. Create lib/widgets/tags/rfid_module_status.dart with:
   - Compact status indicator widget for app bar
   - Shows connection status with colored dot:
     - Gray: Disconnected
     - Yellow: Connecting
     - Green: Ready/Connected
     - Red: Error
   - Shows status text: "RFID Module: [status]"
   - Clickable - opens RfidConnectionModal on tap

3. Update lib/providers/uhf_rfid_provider.dart to:
   - Add method for test connection
   - Add method for connect with saved settings
   - Expose connection error details

4. Write widget tests in test/widgets/tags/rfid_connection_modal_test.dart:
   - Test port dropdown populates
   - Test baud rate selection
   - Test RF power slider
   - Test password validation (valid hex only)
   - Test connect button triggers connection
   - Test disconnect button
   - Test error display

5. Write widget tests in test/widgets/tags/rfid_module_status_test.dart:
   - Test status indicator colors
   - Test tap opens modal

This modal will be accessible from the Tags screen header.
```

**Expected Outcome:**
- Connection settings modal with all configuration options
- Persistent module status indicator
- Test connection functionality
- Settings save and load
- Widget tests for modal and status indicator

---

## Phase 4: Tags UI (Prompts T8-T11)

### Prompt T8: Tag List Screen Foundation

**Context:** Build the main Tags list screen with basic CRUD display functionality.

**Prompt:**

```
Let's build the main Tags list screen.

Reference docs/TAGS_FEATURE_SPEC.md section "Main View: Tag List" for UI specification.

1. Create lib/screens/tags/tag_list_screen.dart with:
   - AppBar with title "Tags"
   - RfidModuleStatus widget in app bar (from T7)
   - Search bar for filtering by EPC
   - Status filter dropdown (All, Generated, Written, Locked, Failed, Retired)
   - Sort dropdown (Created newest, Created oldest, EPC A-Z, Status)
   - Action buttons: "Scan" and "Add" (functionality in later prompts)
   - Tag list using ListView.builder with pagination
   - Pull-to-refresh to reload list
   - Loading state while fetching
   - Empty state: "No tags found" with appropriate messaging
   - Error state with retry button

2. Create lib/widgets/tags/tag_list_item.dart with:
   - Card displaying single tag
   - EPC identifier (formatted with dashes for readability: 5356-XXXX-XXXX-XXXX-XXXX-XXXX)
   - Status badge with color coding:
     - Generated: Gray
     - Written: Blue
     - Locked: Green
     - Failed: Red
     - Retired: Dark gray
   - Created timestamp
   - TID (if captured, truncated)
   - Tap to open detail view
   - Subtle highlight style for "found" state (for scan mode later)

3. Create lib/widgets/tags/tag_status_badge.dart with:
   - Small badge widget showing status
   - Color coded background
   - Status text

4. Create lib/screens/tags/tag_detail_screen.dart with:
   - Modal or slide-over panel
   - Full EPC identifier
   - Status with badge
   - Factory TID (if captured)
   - Timeline section:
     - Created: timestamp and user
     - Written: timestamp (if applicable)
     - Locked: timestamp (if applicable)
   - "Mark as Retired" button (with confirmation dialog)
   - Close button

5. Update lib/widgets/navigation/sidebar_nav.dart to:
   - Add "Tags" menu item
   - Use appropriate icon (label or rfid icon)
   - Only show for users with 'manage_tags' permission or admin role
   - Position in navigation (suggest: after Settings)

6. Update lib/screens/main_scaffold.dart to:
   - Add route for '/tags' → TagListScreen

7. Write widget tests in test/screens/tags/tag_list_screen_test.dart:
   - Test loading state
   - Test empty state
   - Test error state with retry
   - Test tag list renders correctly
   - Test search filters results
   - Test status filter works
   - Test sort changes order

8. Write widget tests for tag_list_item and tag_detail_screen

Manual testing:
- Navigate to Tags section
- Verify empty state shows
- Create some test tags in database manually
- Verify list displays correctly
- Test search and filters
- Tap tag to see details
```

**Expected Outcome:**
- Tags list screen with search, filter, sort
- Tag list item widget
- Tag detail view
- Navigation integration
- Permission-based access
- Widget tests
- Working UI (without Add/Scan functionality yet)

---

### Prompt T9: Activity Log Widget

**Context:** Build the activity log component that shows real-time operation feedback during tag writing and scanning.

**Prompt:**

```
Let's build the activity log widget for displaying real-time operation feedback.

Reference docs/TAGS_FEATURE_SPEC.md UI specification showing the activity log at bottom of screen.

1. Create lib/models/activity_log_entry.dart with:
   - id (String, for unique key)
   - timestamp (DateTime)
   - message (String)
   - level (enum: info, success, warning, error)
   - Optional: relatedEpc (String?) for linking to tags

2. Create lib/providers/activity_log_provider.dart with:
   - activityLogProvider - StateNotifier<List<ActivityLogEntry>>
   - Methods:
     - addEntry(String message, LogLevel level, {String? relatedEpc})
     - clear()
     - Maximum 100 entries (remove oldest when exceeded)

3. Create lib/widgets/tags/activity_log.dart with:
   - Expandable/collapsible panel at bottom of Tags screen
   - Header: "Activity Log" with entry count and "Clear" button
   - Scrollable list of log entries
   - Each entry shows:
     - Timestamp (HH:mm:ss format)
     - Level icon (info/success/warning/error with appropriate colors)
     - Message text
   - Auto-scroll to bottom when new entries added
   - Entries color-coded by level:
     - Info: Default text
     - Success: Green
     - Warning: Orange
     - Error: Red
   - Click on entry with relatedEpc highlights/scrolls to that tag in list (nice to have)

4. Update lib/screens/tags/tag_list_screen.dart to:
   - Include ActivityLog widget at bottom
   - Collapsible with toggle button
   - Remember collapsed state

5. Write widget tests in test/widgets/tags/activity_log_test.dart:
   - Test entries display correctly
   - Test color coding by level
   - Test clear button removes entries
   - Test auto-scroll behavior
   - Test expand/collapse

6. Write provider tests in test/providers/activity_log_provider_test.dart:
   - Test addEntry
   - Test clear
   - Test max entries limit

The activity log is critical for user feedback during bulk operations.
```

**Expected Outcome:**
- Activity log model and provider
- Activity log widget with proper styling
- Integration with Tags screen
- Auto-scroll and collapse functionality
- Tests for widget and provider

---

### Prompt T10: Scan Mode Implementation

**Context:** Implement the "Scan" functionality that reads tags and highlights them in the list.

**Prompt:**

```
Let's implement the Scan mode functionality for reading and identifying tags.

Reference docs/TAGS_FEATURE_SPEC.md section "Scan Mode (Read)".

1. Create lib/providers/scan_mode_provider.dart with:
   - ScanModeState class:
     - isScanning (bool)
     - foundEpcs (Set<String>) - EPCs found in current scan session
     - unknownEpcs (Set<String>) - Saturday tags not in database
   - ScanModeNotifier extends StateNotifier<ScanModeState>:
     - startScanning() - begin polling for tags
     - stopScanning() - stop polling
     - clearFoundTags() - reset found EPCs
   - Logic:
     - When tag found with "5356" prefix:
       - Look up in database via rfidTagRepository
       - If found: add to foundEpcs
       - If not found: add to unknownEpcs, log warning
     - Tags without "5356" prefix are ignored (log as "non-Saturday tag")
     - Add activity log entries for each tag found

2. Update lib/screens/tags/tag_list_screen.dart:
   - "Scan" button behavior:
     - When not scanning: Shows "Scan", clicking starts scan mode
     - When scanning: Shows "Stop Scanning" (different color), clicking stops
   - When scanning active:
     - Filter/highlight tags whose EPC is in foundEpcs
     - Option: Toggle between "Show all" and "Show found only"
     - Pulsing indicator or border on found tags
   - When scan stops:
     - Keep found tags highlighted until user clears or starts new scan
     - Show summary in activity log: "Scan complete: X tags found, Y unknown"

3. Update lib/widgets/tags/tag_list_item.dart:
   - Add 'isHighlighted' property
   - When highlighted: show subtle background color or border
   - Smooth transition animation

4. Create lib/widgets/tags/scan_mode_indicator.dart with:
   - Visual indicator that scan is active
   - Pulsing dot or animation
   - "Scanning..." text
   - Found count display

5. Write integration tests in test/screens/tags/scan_mode_test.dart:
   - Test start/stop scanning
   - Test found tags are highlighted
   - Test unknown Saturday tags are logged
   - Test non-Saturday tags are ignored
   - Test scan summary appears in activity log

6. Write provider tests in test/providers/scan_mode_provider_test.dart:
   - Test state transitions
   - Test EPC categorization logic

Manual testing (requires RFID module):
- Connect RFID module
- Have some tags in database
- Click Scan
- Present tags to reader
- Verify tags are found and highlighted
- Verify unknown tags show warning
- Click Stop Scanning
- Verify summary appears
```

**Expected Outcome:**
- Scan mode provider with state management
- Tag highlighting in list
- Activity log integration
- Scan summary
- Integration tests
- Manual testing successful with hardware

---

### Prompt T11: Add Mode (Bulk Write) Implementation

**Context:** Implement the "Add" functionality that writes new EPCs to blank tags in bulk.

**Prompt:**

```
Let's implement the Add mode (bulk write) functionality for programming blank tags.

Reference docs/TAGS_FEATURE_SPEC.md sections "Add Mode (Bulk Write)" and "Tag Detection Strategy".

This is the core tag creation workflow:
1. Poll for tags in range
2. Find tags without "5356" prefix (unwritten)
3. Generate new EPC with prefix
4. Write to tag
5. Verify write
6. Lock tag
7. Save to database
8. Repeat until no unwritten tags or user stops

1. Create lib/providers/bulk_write_provider.dart with:
   - BulkWriteState class:
     - isWriting (bool)
     - tagsWritten (int)
     - currentOperation (String?) - "Writing...", "Verifying...", "Locking..."
     - lastError (String?)
   - BulkWriteNotifier extends StateNotifier<BulkWriteState>:
     - startBulkWrite() - begin bulk write process
     - stopBulkWrite() - stop after current tag completes
   - Private methods for the write workflow:
     - _pollForUnwrittenTag() - find tag without "5356" prefix
     - _writeTag(epc) - write EPC to tag
     - _verifyWrite(epc) - poll and confirm EPC was written
     - _lockTag() - lock with access password
     - _saveToDatabase(epc, tid) - create/update database record
   - Error handling:
     - On any failure: STOP immediately (per spec requirement)
     - Log detailed error to activity log
     - Keep failed tag record with status 'failed'
   - Success flow:
     - Log each step to activity log
     - Update tag status: generated → written → locked
     - Continue to next unwritten tag
   - Stop conditions:
     - No unwritten tags found for 2 seconds
     - User clicks Stop
     - Error occurs

2. Update lib/screens/tags/tag_list_screen.dart:
   - "Add" button behavior:
     - When not writing: Shows "Add", clicking starts bulk write
     - When writing: Shows "Stop" (red), clicking stops after current tag
   - When writing active:
     - Show current operation status
     - Disable Scan button
     - New tags appear in list as they're created
   - When writing stops:
     - Show summary: "Bulk write complete: X tags created"
     - Or error message if stopped due to failure

3. Create lib/widgets/tags/bulk_write_status.dart with:
   - Status display during bulk write
   - Shows: current operation, tags written count
   - Progress indicator (indeterminate)
   - Stop button

4. Update activity log messages for clarity:
   - "Starting bulk write mode..."
   - "Found unwritten tag, generating EPC..."
   - "Writing EPC 5356-XXXX-... to tag"
   - "Write verified successfully"
   - "Locking tag..."
   - "Tag locked and saved: 5356-XXXX-..."
   - "ERROR: Write failed - [details]"
   - "Stopping bulk write: [reason]"
   - "Bulk write complete: X tags created"

5. Write integration tests in test/providers/bulk_write_provider_test.dart:
   - Test full write workflow with mocked services
   - Test error handling stops process
   - Test stop button behavior
   - Test database records created correctly
   - Test status transitions

6. Write integration tests in test/screens/tags/bulk_write_test.dart:
   - Test UI state during bulk write
   - Test new tags appear in list
   - Test error display
   - Test stop functionality

Manual testing (requires RFID module and blank tags):
- Connect RFID module
- Have blank tags ready
- Click Add
- Present blank tags to reader
- Verify tags are written and appear in list
- Verify activity log shows progress
- Test error handling (remove tag during write)
- Test stop button
```

**Expected Outcome:**
- Bulk write provider with complete workflow
- Write → verify → lock → save pipeline
- Error handling that stops on failure
- Activity log integration
- UI status display
- Integration tests
- Manual testing successful with hardware

---

## Phase 5: Integration and Polish (Prompts T12-T13)

### Prompt T12: End-to-End Integration Testing

**Context:** Ensure all components work together correctly with comprehensive integration tests.

**Prompt:**

```
Let's create comprehensive end-to-end integration tests for the Tags feature.

1. Create test/integration/tags_feature_test.dart with:

   Database Integration:
   - Test: Create tag via repository, verify in database
   - Test: Update tag status, verify timestamps set
   - Test: Query tags with filters
   - Test: Bulk EPC lookup performance with 100+ tags

   Settings Integration:
   - Test: Save settings, restart app (simulate), settings persist
   - Test: Secure password storage and retrieval

   UI Integration (with mocked services):
   - Test: Navigate to Tags section (requires permission)
   - Test: Navigate to Tags section denied (without permission)
   - Test: Tag list loads and displays
   - Test: Search filters list correctly
   - Test: Status filter works
   - Test: Tag detail opens on tap
   - Test: Retire tag updates status

   Scan Mode Integration:
   - Test: Start scan → find tags → highlight in list → stop scan
   - Test: Unknown Saturday tag shows warning
   - Test: Activity log shows entries

   Bulk Write Integration (mocked serial):
   - Test: Start write → write tag → verify → lock → save → stop
   - Test: Error during write stops process
   - Test: Tags appear in list as created
   - Test: Activity log shows all steps

2. Create test/integration/rfid_hardware_test.dart with:
   - Manual test checklist (not automated, requires hardware)
   - Connection test procedure
   - Scan test procedure
   - Write test procedure
   - Lock test procedure
   - Document expected results

3. Update any failing tests from previous prompts

4. Verify all existing tests still pass:
   - Run: flutter test
   - Fix any regressions

5. Create test coverage report:
   - Run: flutter test --coverage
   - Document coverage for Tags feature components
   - Target: >80% coverage for new code

6. Performance testing:
   - Test tag list with 1000 tags
   - Verify scrolling is smooth
   - Verify search is responsive
   - Document any performance issues

Document any bugs found and create issues for fixing.
```

**Expected Outcome:**
- Comprehensive integration test suite
- Hardware test documentation
- All tests passing
- Coverage report >80%
- Performance verified
- Bug list documented

---

### Prompt T13: Documentation and Final Polish

**Context:** Final documentation, code cleanup, and polish before the feature is complete.

**Prompt:**

```
Let's finalize the Tags feature with documentation and polish.

1. Update docs/TAGS_FEATURE_SPEC.md:
   - Add "Implementation Notes" section with any deviations from spec
   - Add "Known Limitations" section
   - Update revision history with implementation date

2. Create docs/TAGS_IMPLEMENTATION_SUMMARY.md following the pattern of other PROMPT_XX docs:
   - Overview
   - Implementation date
   - Files created/modified list
   - Database schema
   - Key features implemented
   - Testing recommendations with checklist
   - Known issues/limitations
   - Future enhancements
   - Dependencies

3. Code cleanup:
   - Review all new files for:
     - Consistent code style
     - Proper error handling
     - Logging at appropriate levels
     - No TODO comments left unaddressed
     - No debug print statements
   - Run: flutter analyze
   - Fix any warnings or errors
   - Run: dart format lib/
   - Ensure consistent formatting

4. Add inline documentation:
   - Document all public classes and methods
   - Add usage examples in complex services
   - Document any non-obvious logic

5. Update README.md (if exists) or create one:
   - Add Tags feature to feature list
   - Document RFID hardware requirements
   - Document setup instructions for RFID module

6. Create lib/screens/tags/README.md with:
   - Feature overview
   - Architecture diagram (text-based)
   - File organization
   - How to extend/modify

7. Final manual testing checklist:
   - [ ] Fresh app install → Tags section accessible for admin
   - [ ] Connect RFID module
   - [ ] Configure settings, disconnect, reconnect → settings persist
   - [ ] Scan mode finds existing tags
   - [ ] Add mode writes new tags
   - [ ] Activity log shows all operations
   - [ ] Search and filter work correctly
   - [ ] Tag detail shows all information
   - [ ] Retire tag works
   - [ ] Non-admin without manage_tags permission cannot access Tags
   - [ ] Errors are handled gracefully

8. Run full test suite one final time:
   - flutter test
   - All tests pass

Feature complete!
```

**Expected Outcome:**
- Updated specification with implementation notes
- Implementation summary document
- Clean, documented code
- All tests passing
- flutter analyze clean
- Manual testing checklist complete
- Feature ready for production

---

## Prompt Checklist

| Prompt | Description | Dependencies | Status |
|--------|-------------|--------------|--------|
| T1 | Database Schema and Model | None | [ ] |
| T2 | Tag Repository | T1 | [ ] |
| T3 | Serial Port Foundation | None | [ ] |
| T4 | UHF Command Frame Protocol | T3 | [ ] |
| T5 | UHF RFID Service | T3, T4 | [ ] |
| T6 | RFID Module Settings Persistence | None | [ ] |
| T7 | Connection Settings Modal | T5, T6 | [ ] |
| T8 | Tag List Screen Foundation | T2 | [ ] |
| T9 | Activity Log Widget | None | [ ] |
| T10 | Scan Mode Implementation | T5, T8, T9 | [ ] |
| T11 | Add Mode (Bulk Write) Implementation | T2, T5, T8, T9 | [ ] |
| T12 | End-to-End Integration Testing | T1-T11 | [ ] |
| T13 | Documentation and Final Polish | T12 | [ ] |

## Dependency Graph

```
Phase 1 (Data):         T1 ──► T2
                              │
Phase 2 (UART):    T3 ──► T4 ──► T5
                              │
Phase 3 (Settings): T6 ◄──────┼──► T7
                              │
Phase 4 (UI):      T8 ◄───────┘
                    │
                   T9
                    │
              T10 ◄─┴─► T11
                    │
Phase 5:          T12 ──► T13
```

## Notes

- Prompts can be executed in parallel where dependencies allow (e.g., T1-T2 and T3-T5 can run in parallel)
- Each prompt should result in working, tested code
- Hardware testing (with actual RFID module) is recommended after T5, T10, and T11
- The specification document (TAGS_FEATURE_SPEC.md) should be referenced throughout implementation
