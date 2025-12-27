# Machine Control Feature Documentation

## Overview

The Saturday! Admin App includes a comprehensive CNC/Laser machine control system designed for production steps that require automated machining operations. This feature enables workers to control CNC mills and laser cutters directly from the app, execute gCode programs, and automatically engrave QR codes on production units.

This document covers the complete machine control system implemented across Prompts 36-41, including serial communication, gCode streaming, image-to-gCode conversion, and the full-screen machine control interface.

---

## Feature Components

### 1. Database Schema

**Migration**: `010_production_step_types.sql`

Updated the `production_steps` table to support machine-specific steps:

```sql
-- Add step type enum
CREATE TYPE step_type AS ENUM ('general', 'cnc_milling', 'laser_cutting');

ALTER TABLE public.production_steps
ADD COLUMN step_type step_type NOT NULL DEFAULT 'general';

-- Add QR engraving parameters for laser steps
ALTER TABLE public.production_steps
ADD COLUMN engrave_qr BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN qr_x_offset NUMERIC(10,3),
ADD COLUMN qr_y_offset NUMERIC(10,3),
ADD COLUMN qr_size NUMERIC(10,3),
ADD COLUMN qr_power_percent INTEGER,
ADD COLUMN qr_speed_mm_min INTEGER;

-- Add constraints for QR parameters
ALTER TABLE public.production_steps
ADD CONSTRAINT qr_params_when_engraving CHECK (
  (engrave_qr = false) OR
  (engrave_qr = true AND qr_x_offset IS NOT NULL AND qr_y_offset IS NOT NULL
   AND qr_size IS NOT NULL AND qr_power_percent IS NOT NULL
   AND qr_speed_mm_min IS NOT NULL)
);
```

**Key Design Decisions:**
- **Step type enum** - Explicit categorization of production steps (general, cnc_milling, laser_cutting)
- **Optional QR engraving** - Laser steps can automatically engrave unit QR codes
- **Parametrized engraving** - Complete control over position, size, power, and speed
- **Data integrity** - Constraint ensures all QR parameters are provided when engraving is enabled

---

**Related Table**: `step_gcode_files` (many-to-many relationship)

```sql
CREATE TABLE public.step_gcode_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id UUID NOT NULL REFERENCES public.production_steps(id) ON DELETE CASCADE,
  gcode_file_id UUID NOT NULL REFERENCES public.gcode_files(id) ON DELETE CASCADE,
  execution_order INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT positive_execution_order CHECK (execution_order > 0),
  CONSTRAINT unique_step_gcode_file UNIQUE (step_id, gcode_file_id)
);
```

**Key Design Decisions:**
- **Many-to-many relationship** - Steps can have multiple gCode files; files can be used by multiple steps
- **Execution order** - Files run sequentially in specified order
- **Cascade delete** - Cleanup when steps or files are deleted

---

### 2. Data Models

#### StepType Enum (`lib/models/step_type.dart`)

```dart
enum StepType {
  general('general'),
  cncMilling('cnc_milling'),
  laserCutting('laser_cutting');

  const StepType(this.value);
  final String value;

  String get displayName { /* ... */ }
  String? get machineType { /* cnc or laser */ }
  bool get requiresMachine { /* true for cnc/laser */ }
  bool get isCnc { /* ... */ }
  bool get isLaser { /* ... */ }
}
```

#### GCodeFile Model (`lib/models/gcode_file.dart`)

Represents gCode files stored in GitHub repository:

```dart
class GCodeFile {
  final String id;
  final String githubPath;       // e.g., "cnc/drill-holes.gcode"
  final String fileName;         // Display name
  final String? description;     // From README
  final String machineType;      // 'cnc' or 'laser'
  final DateTime createdAt;
  final DateTime updatedAt;
}
```

#### StepGCodeFile Model (`lib/models/step_gcode_file.dart`)

Join table model linking steps to gCode files:

```dart
class StepGCodeFile {
  final String id;
  final String stepId;
  final String gcodeFileId;
  final int executionOrder;
  final GCodeFile? gcodeFile;    // Populated via join
  final DateTime createdAt;
}
```

---

### 3. Serial Communication Layer

#### MachineConnectionService (`lib/services/machine_connection_service.dart`)

Handles serial port communication with CNC/Laser machines using the grbl protocol.

**Key Features:**
- Serial port discovery and connection
- grbl command protocol (G-code + grbl-specific commands)
- Real-time status polling and parsing
- State management (disconnected, connecting, connected, idle, running, paused, alarm, error)
- Emergency stop functionality

**Core Methods:**
```dart
class MachineConnectionService {
  // Connection management
  Future<bool> connect({
    required String portName,
    required MachineType machineType,
    int baudRate = 115200,
  });
  Future<void> disconnect();

  // Machine control
  Future<bool> sendCommand(String command);
  Future<void> emergencyStop();  // Ctrl-X soft reset
  Future<bool> home();            // $H command
  Future<bool> setZero({bool x, bool y, bool z});  // G10 L20 P0

  // Status monitoring
  Future<void> requestStatus();   // ? command
  Stream<MachineState> get stateStream;
  Stream<MachineStatus> get machineStatusStream;

  // Port utilities
  static List<String> listAvailablePorts();
  List<String> getAvailablePorts();
  Map<String, String> getPortInfo(String portName);
}
```

**State Machine:**
```
disconnected → connecting → connected → idle ⇄ running
                                ↓         ↓
                              alarm    paused
                                ↓         ↓
                              error ← ← ←
```

**grbl Status Parsing:**
Parses real-time status reports like:
```
<Idle|MPos:0.000,0.000,0.000|FS:0,0>
```

Extracts:
- Machine state (Idle, Run, Hold, Alarm, etc.)
- Machine position (X, Y, Z)
- Feed rate and spindle speed

---

### 4. GCode Streaming Layer

#### GCodeStreamingService (`lib/services/gcode_streaming_service.dart`)

Streams gCode commands line-by-line to the machine with flow control.

**Key Features:**
- Line-by-line streaming with acknowledgment tracking
- Flow control (max pending lines)
- Pause/Resume functionality
- Progress tracking
- Error detection and handling

**Core Methods:**
```dart
class GCodeStreamingService {
  // Streaming control
  Future<bool> startStreaming(String gcodeContent, {int maxPendingLines = 5});
  Future<StreamingResult> streamGCode(String gcodeContent);
  void pause();
  void resume();
  void stop();
  Future<void> cancel();

  // Status
  Stream<StreamingProgress> get progressStream;
  bool get isStreaming;
  bool get isPaused;
}

class StreamingResult {
  final bool success;
  final String? message;
  final int? linesCompleted;
}

class StreamingProgress {
  final int totalLines;
  final int sentLines;
  final int completedLines;
  final StreamingStatus status;
  final String? currentLine;
  final String? error;

  double get percentComplete { /* ... */ }
  int get currentLineNumber { /* ... */ }
  String get lastCommand { /* ... */ }
}
```

**Streaming Algorithm:**
1. Parse gCode (remove comments, empty lines, convert to uppercase)
2. Send initial batch of lines (up to maxPendingLines)
3. Wait for "ok" acknowledgments from machine
4. Send next line for each "ok" received
5. Track progress and emit updates
6. Handle errors ("error:", "ALARM:") from machine
7. Complete when all lines acknowledged

**Safety Features:**
- Flow control prevents buffer overflow
- Pause maintains position (grbl feed hold: `!`)
- Resume continues from paused position (grbl cycle start: `~`)
- Emergency stop sends immediate soft reset (`Ctrl-X`)

---

### 5. GCode File Management

#### GCodeSyncService (`lib/services/gcode_sync_service.dart`)

Synchronizes gCode files from GitHub repository to local database.

**Key Features:**
- Scans GitHub repository for `.gcode` files
- Extracts metadata from README files
- Determines machine type from path structure
- Syncs to local Supabase database
- Fetches gCode content for execution

**Core Methods:**
```dart
class GCodeSyncService {
  // Repository sync
  Future<SyncResult> syncRepository();

  // Content fetching
  Future<String> fetchGCodeContent(GCodeFile file);

  // Validation
  Future<bool> validateConnection();
  Future<Map<String, dynamic>?> getRepositoryInfo();
}
```

**Repository Structure:**
```
github-repo/
├── cnc/
│   ├── README.md           (# Drill Mounting Holes)
│   ├── drill-holes.gcode
│   └── pocket-cutout.gcode
└── laser/
    ├── README.md           (# Engrave Serial Number)
    └── engrave-text.gcode
```

**Sync Algorithm:**
1. Recursively scan repository for `.gcode` files
2. For each directory, read README.md for descriptions
3. Determine machine type from path (cnc/, laser/, or keywords)
4. Extract display name from README H1 heading
5. Upsert files to database with metadata
6. Delete database entries for files no longer in GitHub

---

### 6. Image-to-GCode Conversion

#### ImageToGCodeService (`lib/services/image_to_gcode_service.dart`)

Converts PNG images (specifically QR codes) to raster-scanned laser engraving gCode.

**Key Features:**
- PNG decoding and grayscale conversion
- Pixel intensity → laser power mapping
- Raster scanning with zigzag optimization
- Physical dimension calculations (mm)
- grbl-compatible gCode generation

**Core Method:**
```dart
Future<String> convertImageToGCode({
  required Uint8List pngData,
  required double widthMM,
  required double heightMM,
  required double startX,
  required double startY,
  required int maxPower,    // 0-100%
  required int feedRate,    // mm/min
});
```

**Algorithm:**
1. Decode PNG to image object
2. Convert to grayscale
3. Calculate step size (mm per pixel)
4. Generate gCode header with parameters
5. Raster scan image:
   - Alternate scan direction per row (zigzag)
   - Map pixel intensity to laser power (0=white/off, 255=black/max power)
   - Generate G1 moves with S power values
   - Skip white pixels with G0 rapid moves
6. Generate footer (return to start, laser off)

**Generated GCode Structure:**
```gcode
; Header with metadata
G21                     ; Set units to millimeters
G90                     ; Absolute positioning
M3                      ; Enable laser (constant power mode)
S0                      ; Laser off initially
F2000                   ; Set feed rate

G0 X10.000 Y20.000      ; Move to start position

; Raster scan
G1 X10.100 Y20.000 S85  ; Fire laser at 85% power
G1 X10.200 Y20.000 S92  ; Fire laser at 92% power
G0 X10.300 Y20.000 S0   ; Skip white pixel
...

S0                      ; Laser off
M5                      ; Disable laser
G0 X10.000 Y20.000      ; Return to start
```

**QR Code Engraving Integration:**
```dart
Future<String> generateQREngraveGCode({
  required ProductionUnit unit,
  required ProductionStep step,
});
```

This method:
1. Validates step has QR engraving enabled
2. Fetches QR code image from Supabase storage
3. Converts to gCode using step parameters
4. Returns ready-to-stream gCode

---

### 7. Configuration Storage

#### MachineConfigStorage (`lib/services/machine_config_storage.dart`)

Persists machine configuration preferences using SharedPreferences.

**Stored Configuration:**
- CNC serial port preference
- Laser serial port preference
- CNC baud rate (default: 115200)
- Laser baud rate (default: 115200)

**Core Methods:**
```dart
class MachineConfigStorage {
  // Port preferences
  String? getCncPort();
  Future<bool> setCncPort(String port);
  String? getLaserPort();
  Future<bool> setLaserPort(String port);

  // Baud rate preferences
  int getCncBaudRate();
  Future<bool> setCncBaudRate(int baudRate);
  int getLaserBaudRate();
  Future<bool> setLaserBaudRate(int baudRate);

  // Cleanup
  Future<bool> clearAll();
}
```

---

### 8. State Management (Riverpod Providers)

#### Machine Providers (`lib/providers/machine_provider.dart`)

**Service Providers:**
```dart
// Separate instances for CNC and Laser machines
final cncMachineServiceProvider = Provider<MachineConnectionService>((ref) => ...);
final laserMachineServiceProvider = Provider<MachineConnectionService>((ref) => ...);

// Streaming services tied to their respective machines
final cncStreamingServiceProvider = Provider<GCodeStreamingService>((ref) => ...);
final laserStreamingServiceProvider = Provider<GCodeStreamingService>((ref) => ...);

// Configuration storage
final machineConfigStorageProvider = Provider<MachineConfigStorage>((ref) => ...);

// GitHub and sync services
final githubServiceProvider = Provider<GitHubService>((ref) => ...);
final gcodeSyncServiceProvider = Provider<GCodeSyncService>((ref) => ...);
```

#### GCode File Providers (`lib/providers/gcode_file_provider.dart`)

```dart
// All gCode files
final gcodeFilesProvider = FutureProvider<List<GCodeFile>>((ref) => ...);

// Files for a specific step
final stepGCodeFilesProvider = FutureProvider.family<List<StepGCodeFile>, String>(
  (ref, stepId) => ...
);
```

#### Image-to-GCode Provider (`lib/providers/image_to_gcode_provider.dart`)

```dart
final imageToGCodeServiceProvider = Provider<ImageToGCodeService>((ref) => ...);
```

---

### 9. User Interface

#### MachineControlScreen (`lib/screens/production/machine_control_screen.dart`)

Full-screen interface for controlling CNC/Laser machines during production.

**Screen Sections:**

**1. Machine Status Section**
- Serial port dropdown (auto-populated with available ports)
- Port refresh button
- Connection status indicator (colored dot + text)
- Connect/Disconnect buttons
- Emergency Stop button (prominent, always accessible when connected)

**2. Machine Controls Section**
- Home button ($H) - Homes all axes
- Set X0 / Set Y0 / Set Z0 buttons - Zero individual axes
- Only enabled when machine is idle

**3. Execution Queue Section**
- Lists all gCode files for the step (ordered by `execution_order`)
- Shows completion status with numbered badges/checkmarks
- "Run" button for each file
- QR engraving card (if `engrave_qr` is true)
  - Displays engraving parameters
  - "Run Engrave" button

**4. Progress Section** (visible during streaming)
- Linear progress bar
- Line count (current / total)
- Percentage complete
- Last executed command
- Pause/Resume button
- Stop button

**5. Navigation**
- "Back to Unit" button

**State Management:**
```dart
class _MachineControlScreenState extends ConsumerState<MachineControlScreen> {
  late final MachineConnectionService _machine;
  late final GCodeStreamingService _streaming;

  MachineState _machineState = MachineState.disconnected;
  String? _selectedPort;
  List<String> _availablePorts = [];

  Map<String, bool> _gcodeFileCompleted = {};
  bool _qrEngraveCompleted = false;
  StreamingProgress? _currentProgress;
}
```

**Key Methods:**
- `_connect()` - Connects to machine, saves port preference
- `_disconnect()` - Disconnects from machine
- `_emergencyStop()` - Triggers emergency stop on machine and streaming
- `_home()` - Homes the machine
- `_setZero({x, y, z})` - Zeros specified axes
- `_runGCodeFile(GCodeFile)` - Fetches content from GitHub and streams to machine
- `_runQREngrave()` - Generates QR gCode and streams to machine

**Workflow:**
1. Worker opens Machine Control from Complete Step screen
2. Selects serial port and connects to machine
3. Optionally homes machine and sets zero positions
4. Runs gCode files in sequence
5. Optionally runs QR engraving
6. Returns to Complete Step screen

---

#### Integration with CompleteStepScreen (`lib/screens/production/complete_step_screen.dart`)

**Added Button:**
```dart
if (widget.step.stepType.requiresMachine &&
    (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
  OutlinedButton.icon(
    onPressed: _openMachineControl,
    icon: Icon(Icons.precision_manufacturing),
    label: Text('Open Machine Control'),
  );
}
```

**Navigation:**
```dart
void _openMachineControl() {
  final unit = ref.read(unitByIdProvider(widget.unitId)).value;

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => MachineControlScreen(
        step: widget.step,
        unit: unit,
      ),
    ),
  );
}
```

---

## Technical Architecture

### Component Interaction Flow

```
[Worker] → [CompleteStepScreen]
              ↓ (Opens Machine Control)
           [MachineControlScreen]
              ↓ (Uses)
           [MachineConnectionService] ← → [Serial Port]
              ↑                              ↓
              |                         [CNC/Laser Machine]
              |                              ↑
           [GCodeStreamingService] → → → → → ┘
              ↑
              |
           [GCodeSyncService] ← → [GitHubService] ← → [GitHub API]
              ↑
              |
           [ImageToGCodeService] ← → [QRCodeFetchService] ← → [Supabase Storage]
```

### Data Flow: Running a GCode File

1. **User clicks "Run" on gCode file**
2. `_runGCodeFile()` is called
3. **Fetch gCode content:**
   - GCodeSyncService.fetchGCodeContent()
   - GitHubService.getFileContents()
   - Returns raw gCode string from GitHub
4. **Stream to machine:**
   - GCodeStreamingService.streamGCode()
   - Prepares gCode (removes comments, uppercase)
   - Sends lines with flow control
   - Waits for acknowledgments
   - Emits progress updates
5. **UI updates:**
   - Progress bar fills
   - Line count increments
   - Last command updates
6. **Completion:**
   - Mark file as completed
   - Show success snackbar
   - Return to idle state

### Data Flow: QR Code Engraving

1. **User clicks "Run Engrave" on QR card**
2. `_runQREngrave()` is called
3. **Generate gCode:**
   - ImageToGCodeService.generateQREngraveGCode()
   - QRCodeFetchService.fetchQRCodeImage() (from Supabase)
   - ImageToGCodeService.convertImageToGCode()
   - Returns raster-scanned gCode string
4. **Stream to machine:**
   - (Same as above)
5. **Completion:**
   - Mark QR engraving as completed
   - Show success snackbar

---

## Safety Considerations

### Emergency Stop
- **Hardware-level:** Sends Ctrl-X (0x18) soft reset to grbl
- **Software-level:** Immediately stops streaming service
- **UI:** Large red button always visible when connected
- **Effect:** Halts all motion immediately, resets grbl state

### Connection Safety
- **Port validation:** Checks port exists before connecting
- **Error handling:** All serial operations wrapped in try-catch
- **State management:** Clear state machine prevents invalid operations
- **Disconnect cleanup:** Properly closes port and resets state

### Streaming Safety
- **Flow control:** Limits pending lines to prevent buffer overflow
- **Acknowledgment tracking:** Ensures all commands are received
- **Error detection:** Monitors for "error:" and "ALARM:" responses
- **Pause/Resume:** Uses grbl feed hold/cycle start for safe pausing

### Laser Safety
- **Laser off by default:** S0 command sent initially
- **Explicit enable:** M3 command required to enable laser
- **Disable on completion:** M5 command disables laser at end
- **Disconnect safety:** Laser turns off when connection lost (grbl behavior)

---

## Configuration Examples

### CNC Milling Step Configuration

```dart
ProductionStep(
  name: 'CNC Mill Top Panel',
  stepType: StepType.cncMilling,
  engraveQr: false,
  gcodeFiles: [
    StepGCodeFile(
      gcodeFile: GCodeFile(
        fileName: 'face-mill-top.gcode',
        machineType: 'cnc',
      ),
      executionOrder: 1,
    ),
    StepGCodeFile(
      gcodeFile: GCodeFile(
        fileName: 'drill-mounting-holes.gcode',
        machineType: 'cnc',
      ),
      executionOrder: 2,
    ),
  ],
)
```

### Laser Cutting Step with QR Engraving

```dart
ProductionStep(
  name: 'Laser Cut and Mark',
  stepType: StepType.laserCutting,
  engraveQr: true,
  qrXOffset: 10.0,        // mm from machine zero
  qrYOffset: 10.0,        // mm from machine zero
  qrSize: 20.0,           // 20mm x 20mm square
  qrPowerPercent: 80,     // 80% laser power
  qrSpeedMmMin: 2000,     // 2000 mm/min feed rate
  gcodeFiles: [
    StepGCodeFile(
      gcodeFile: GCodeFile(
        fileName: 'cut-outline.gcode',
        machineType: 'laser',
      ),
      executionOrder: 1,
    ),
  ],
)
```

---

## Testing Recommendations

### Unit Testing
- ✅ MachineConnectionService state transitions
- ✅ GCodeStreamingService flow control
- ✅ ImageToGCodeService pixel-to-power conversion
- ✅ Configuration storage persistence

### Integration Testing
- ✅ Serial communication with mock grbl
- ✅ GCode streaming with simulated responses
- ✅ GitHub API integration
- ✅ QR code fetching from Supabase

### Manual Testing
- ✅ Connect/disconnect from real machine
- ✅ Home and zero operations
- ✅ Stream simple gCode file (G0 moves only)
- ✅ Stream complex gCode file (multiple operations)
- ✅ QR code engraving on scrap material
- ✅ Emergency stop during operation
- ✅ Pause/resume during streaming
- ✅ Error handling (disconnect during streaming)

### Safety Testing
- ✅ Emergency stop responds immediately
- ✅ Machine doesn't move unexpectedly
- ✅ Laser turns off when connection lost
- ✅ Pause doesn't skip commands
- ✅ Resume continues from correct position

---

## Performance Considerations

### Serial Communication
- **Baud rate:** 115200 (grbl default)
- **Flow control:** Max 5 pending lines (configurable)
- **Status polling:** Every 500ms during streaming
- **Timeout:** 2 minutes for command execution

### GCode Streaming
- **Memory:** Loads entire gCode file into memory (acceptable for typical files <1MB)
- **Parsing:** Pre-processes gCode once before streaming
- **Progress updates:** Emitted after each acknowledged line
- **Optimization:** Zigzag raster scanning for image conversion

### UI Responsiveness
- **State updates:** Stream-based for reactive UI
- **Progress bar:** Updates in real-time without blocking
- **Background operations:** All serial I/O on separate isolate (via flutter_libserialport)

---

## Troubleshooting

### Common Issues

**"Failed to connect"**
- Check serial port is not in use by another application
- Verify correct baud rate (115200 for grbl)
- Ensure USB cable is properly connected
- Try unplugging and replugging machine

**"Emergency stop activated" / Machine in ALARM state**
- Run homing cycle ($H) to clear alarm
- Check machine limit switches
- Verify machine is not at physical limit

**GCode file execution fails**
- Check gCode is compatible with grbl
- Verify machine has been homed
- Ensure work coordinates are set correctly
- Check for invalid G-codes or parameters

**QR engraving doesn't appear**
- Verify laser power is sufficient for material
- Check focus distance is correct
- Ensure feed rate is appropriate (too fast = incomplete burn)
- Verify QR code size fits on workpiece

---

## Future Enhancements

### Potential Improvements
- **gCode preview:** 3D visualization before running
- **Dry run mode:** Execute without firing laser/spindle
- **Tool change detection:** Pause for manual tool changes
- **Multiple machine support:** Connect to multiple machines simultaneously
- **Job queue:** Schedule multiple units for automated production
- **Custom gCode snippets:** User-defined reusable gCode sequences
- **Machine maintenance tracking:** Hours counter, calibration reminders
- **Video feed integration:** Live camera view during machining
- **Advanced error recovery:** Resume from specific line after error

---

## Related Documentation

- [Label Printing Feature](LABEL_PRINTING_FEATURE.md)
- [Multiple Labels Implementation Guide](MULTIPLE_LABELS_IMPLEMENTATION_GUIDE.md)
- [Production Units & QR Codes](PROMPT_14_PRODUCTION_UNITS_QR.md)
- [QR Scanning Feature](PROMPT_18_QR_SCANNING.md)

---

**Document Version**: 1.0
**Created**: 2025-01-13
**Author**: Saturday! Development Team
**Prompts Covered**: 36-41 (Machine Control System)
