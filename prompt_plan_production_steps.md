# Production Steps Enhancement - Implementation Prompt Plan

## Overview

This document contains a series of prompts designed for implementing advanced production step types with machine control capabilities. This builds on the foundation established in Prompt 12 (Production Step Configuration) from the main prompt_plan.md.

**Feature Summary:**
- Add step type system (General, CNC Milling, Laser Cutting/Engraving)
- Integrate with GitHub gCode repository
- Add USB serial communication with CNC/Laser machines
- Implement gCode streaming and execution
- Add PNG-to-gCode conversion for QR code engraving
- Create dedicated Machine Control interface

**Technology Stack:**
- Flutter (cross-platform framework)
- Supabase (backend database)
- GitHub API (gCode repository access)
- flutter_libserialport (USB serial communication)
- grbl/grblHAL protocols (machine communication)

**Development Approach:**
- Incremental implementation across 6 prompts
- Test each phase before moving forward
- Desktop-first (machine control requires USB)
- Build on existing production step infrastructure

---

## Phase 1: Database Schema & Models

### Prompt 36: Step Types and gCode Repository Schema

> **⚠️ DEPRECATED - GitHub Repository Integration**
> The GitHub repository sync portion of this prompt has been deprecated and replaced with a unified file library system (see migration 013_file_library.sql). The step types (general, cnc_milling, laser_cutting) are still used, but files are now managed through the Files screen and Supabase Storage instead of GitHub sync.

**Context:** We currently have a basic production step system (from Prompt 12) that supports name, description, file attachments, and label printing. We need to extend this to support different step types with machine-specific configurations.

We're adding three step types:
1. **General** - Current functionality (default)
2. **CNC Milling** - Requires gCode files, uses grblHAL protocol
3. **Laser Cutting/Engraving** - Same as CNC plus QR code engraving capability

**User Story:** As an admin, I want to configure production steps with specific machine requirements and gCode files, so that workers can execute automated machining operations during production.

**Prompt:**

```
We need to enhance our production step system to support different step types with machine-specific configurations.

BACKGROUND:
- Our existing production_steps table has: name, description, step_order, file_url, file_name, file_type
- We have a step_labels table for multiple label printing (one-to-many relationship)
- Production units progress through steps sequentially

NEW REQUIREMENTS:

1. STEP TYPES
   Add support for three step types:
   - general (default, current functionality)
   - cnc_milling (CNC machine operations)
   - laser_cutting (Laser machine operations + optional QR engraving)

2. DATABASE SCHEMA CHANGES

   A. Modify production_steps table:
   ```sql
   ALTER TABLE production_steps
     ADD COLUMN step_type TEXT NOT NULL DEFAULT 'general',
     ADD COLUMN requires_machine BOOLEAN DEFAULT false,
     ADD COLUMN machine_type TEXT; -- 'cnc' or 'laser' (null for general)

   -- Laser engraving configuration fields
   ALTER TABLE production_steps
     ADD COLUMN enable_qr_engraving BOOLEAN DEFAULT false,
     ADD COLUMN qr_engrave_width DECIMAL(5,2), -- physical width in inches
     ADD COLUMN qr_engrave_height DECIMAL(5,2), -- physical height in inches
     ADD COLUMN qr_engrave_start_x DECIMAL(6,2), -- X starting position
     ADD COLUMN qr_engrave_start_y DECIMAL(6,2), -- Y starting position
     ADD COLUMN qr_engrave_power INTEGER, -- laser power (0-100 or S value)
     ADD COLUMN qr_engrave_feed_rate INTEGER; -- feed rate in mm/min

   -- Add check constraint
   ALTER TABLE production_steps
     ADD CONSTRAINT valid_step_type
     CHECK (step_type IN ('general', 'cnc_milling', 'laser_cutting'));

   -- Add index
   CREATE INDEX idx_production_steps_type ON production_steps(step_type);
   ```

   B. Create gcode_files table (cache of GitHub repo structure):
   ```sql
   CREATE TABLE gcode_files (
     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
     folder_path TEXT NOT NULL, -- e.g., "turntable-base/mill-pocket"
     file_name TEXT NOT NULL, -- e.g., "pocket.gcode"
     display_name TEXT NOT NULL, -- H1 from README (e.g., "Mill Turntable Pocket")
     github_url TEXT NOT NULL, -- raw.githubusercontent.com URL
     file_type TEXT NOT NULL, -- '.gcode' or '.nc'
     last_synced_at TIMESTAMP WITH TIME ZONE,
     created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
     updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
     CONSTRAINT unique_gcode_file UNIQUE(folder_path, file_name)
   );

   CREATE INDEX idx_gcode_files_folder ON gcode_files(folder_path);
   CREATE INDEX idx_gcode_files_display_name ON gcode_files(display_name);

   -- Add trigger for updated_at
   CREATE TRIGGER update_gcode_files_updated_at
     BEFORE UPDATE ON gcode_files
     FOR EACH ROW
     EXECUTE FUNCTION update_updated_at_column();
   ```

   C. Create step_gcode_files table (many-to-many with ordering):
   ```sql
   CREATE TABLE step_gcode_files (
     id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
     step_id UUID NOT NULL REFERENCES production_steps(id) ON DELETE CASCADE,
     gcode_file_id UUID NOT NULL REFERENCES gcode_files(id) ON DELETE CASCADE,
     execution_order INTEGER NOT NULL, -- 1-based sequence
     created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
     CONSTRAINT unique_step_gcode UNIQUE(step_id, gcode_file_id),
     CONSTRAINT unique_step_order UNIQUE(step_id, execution_order),
     CONSTRAINT positive_execution_order CHECK (execution_order > 0)
   );

   CREATE INDEX idx_step_gcode_files_step ON step_gcode_files(step_id, execution_order);
   CREATE INDEX idx_step_gcode_files_gcode ON step_gcode_files(gcode_file_id);
   ```

   D. Add RLS policies for new tables (match production_steps permissions):
   ```sql
   -- gcode_files policies
   ALTER TABLE gcode_files ENABLE ROW LEVEL SECURITY;

   CREATE POLICY "Authenticated users can read gcode files"
     ON gcode_files FOR SELECT TO authenticated USING (true);

   CREATE POLICY "Authenticated users can insert gcode files"
     ON gcode_files FOR INSERT TO authenticated WITH CHECK (true);

   CREATE POLICY "Authenticated users can update gcode files"
     ON gcode_files FOR UPDATE TO authenticated USING (true);

   CREATE POLICY "Authenticated users can delete gcode files"
     ON gcode_files FOR DELETE TO authenticated USING (true);

   -- step_gcode_files policies
   ALTER TABLE step_gcode_files ENABLE ROW LEVEL SECURITY;

   CREATE POLICY "Authenticated users can read step gcode files"
     ON step_gcode_files FOR SELECT TO authenticated USING (true);

   CREATE POLICY "Authenticated users can insert step gcode files"
     ON step_gcode_files FOR INSERT TO authenticated WITH CHECK (true);

   CREATE POLICY "Authenticated users can update step gcode files"
     ON step_gcode_files FOR UPDATE TO authenticated USING (true);

   CREATE POLICY "Authenticated users can delete step gcode files"
     ON step_gcode_files FOR DELETE TO authenticated USING (true);
   ```

3. DART MODELS

   A. Create StepType enum (lib/models/step_type.dart):
   ```dart
   enum StepType {
     general('general', 'General'),
     cncMilling('cnc_milling', 'CNC Milling'),
     laserCutting('laser_cutting', 'Laser Cutting/Engraving');

     final String value;
     final String displayName;
     const StepType(this.value, this.displayName);

     static StepType fromString(String value) { /* ... */ }
   }
   ```

   B. Create GCodeFile model (lib/models/gcode_file.dart):
   ```dart
   class GCodeFile extends Equatable {
     final String id;
     final String folderPath;
     final String fileName;
     final String displayName; // H1 from README
     final String githubUrl;
     final String fileType; // '.gcode' or '.nc'
     final DateTime? lastSyncedAt;
     final DateTime createdAt;
     final DateTime updatedAt;

     // Methods: fromJson, toJson, copyWith
   }
   ```

   C. Create StepGCodeFile model (lib/models/step_gcode_file.dart):
   ```dart
   class StepGCodeFile extends Equatable {
     final String id;
     final String stepId;
     final String gcodeFileId;
     final int executionOrder;
     final DateTime createdAt;

     // Optional: loaded GCodeFile object
     final GCodeFile? gcodeFile;

     // Methods: fromJson, toJson, copyWith
   }
   ```

   D. Update ProductionStep model (lib/models/production_step.dart):
   Add new fields:
   ```dart
   final StepType stepType;
   final bool requiresMachine;
   final String? machineType; // 'cnc' or 'laser'

   // Laser engraving fields
   final bool enableQrEngraving;
   final double? qrEngraveWidth;
   final double? qrEngraveHeight;
   final double? qrEngraveStartX;
   final double? qrEngraveStartY;
   final int? qrEngravePower;
   final int? qrEngraveFeedRate;

   // Update fromJson, toJson, copyWith to include new fields
   ```

4. REPOSITORIES

   A. Create GCodeFileRepository (lib/repositories/gcode_file_repository.dart):
   ```dart
   class GCodeFileRepository {
     // CRUD operations
     Future<List<GCodeFile>> getAllFiles();
     Future<List<GCodeFile>> getFilesByFolder(String folderPath);
     Future<GCodeFile?> getFileById(String id);
     Future<GCodeFile> createFile(GCodeFile file);
     Future<void> updateFile(GCodeFile file);
     Future<void> deleteFile(String id);
     Future<void> deleteAll(); // For cache refresh

     // Search
     Future<List<GCodeFile>> searchFiles(String query);
   }
   ```

   B. Create StepGCodeFileRepository (lib/repositories/step_gcode_file_repository.dart):
   ```dart
   class StepGCodeFileRepository {
     // Get files for a step (ordered by execution_order)
     Future<List<StepGCodeFile>> getFilesForStep(String stepId);

     // Get with loaded GCodeFile objects
     Future<List<StepGCodeFile>> getFilesForStepWithDetails(String stepId);

     // Batch operations
     Future<void> setFilesForStep(
       String stepId,
       List<String> gcodeFileIds, // Ordered list
     );

     Future<void> updateFileOrder(
       String stepId,
       Map<String, int> fileIdToOrder, // fileId -> execution_order
     );

     Future<void> deleteFilesForStep(String stepId);
   }
   ```

   C. Update ProductionStepRepository (lib/repositories/production_step_repository.dart):
   Update methods to handle new fields in ProductionStep model.

5. PROVIDERS

   A. Create gcode_file_provider.dart:
   ```dart
   final gcodeFileRepositoryProvider = Provider<GCodeFileRepository>((ref) {
     return GCodeFileRepository(ref.read(supabaseClientProvider));
   });

   final allGCodeFilesProvider = FutureProvider<List<GCodeFile>>((ref) async {
     return ref.read(gcodeFileRepositoryProvider).getAllFiles();
   });

   final gcodeFilesByFolderProvider =
     FutureProvider.family<List<GCodeFile>, String>((ref, folder) async {
       return ref.read(gcodeFileRepositoryProvider).getFilesByFolder(folder);
     });
   ```

   B. Create step_gcode_file_provider.dart:
   ```dart
   final stepGCodeFileRepositoryProvider = Provider<StepGCodeFileRepository>((ref) {
     return StepGCodeFileRepository(ref.read(supabaseClientProvider));
   });

   final stepGCodeFilesProvider =
     FutureProvider.family<List<StepGCodeFile>, String>((ref, stepId) async {
       return ref.read(stepGCodeFileRepositoryProvider)
         .getFilesForStepWithDetails(stepId);
     });
   ```

6. MIGRATION FILE

   Create: supabase/migrations/010_production_step_types.sql

   Include all SQL from above with:
   - ALTER TABLE statements for production_steps
   - CREATE TABLE statements for gcode_files and step_gcode_files
   - Indexes, constraints, triggers
   - RLS policies
   - Comments explaining each section

TESTING REQUIREMENTS:
- [ ] Migration runs successfully without errors
- [ ] Can insert/update/delete gcode_files
- [ ] Can insert/update/delete step_gcode_files
- [ ] ProductionStep model serializes with new fields
- [ ] GCodeFile model serializes correctly
- [ ] StepGCodeFile model serializes correctly
- [ ] Repositories fetch data correctly
- [ ] RLS policies work for authenticated users
- [ ] Foreign key constraints work (CASCADE delete)
- [ ] Unique constraints prevent duplicates

Please implement this complete database schema and model layer.
```

**Expected Outcome:**
- New migration file creates all tables and columns
- Dart models represent new data structures
- Repositories provide CRUD operations
- Providers expose data reactively
- Foundation ready for GitHub integration and UI

**Dependencies:** Prompt 12 (Production Step Configuration), Prompt 17 (Production Units)
**Estimated Time:** 4-6 hours
**Complexity:** Medium
**Testing Required:** Unit tests for models, Integration tests for repositories

---

## Phase 2: GitHub Integration

### Prompt 37: GitHub gCode Repository Integration

**Context:** We have a private GitHub repository at `https://github.com/Saturday-Vinyl/gcode` that contains our gCode files organized in folders. Each folder contains a README.md with an H1 title and description, plus one or more gCode files (.gcode or .nc extension).

Workers need to browse and select gCode files from this repository when configuring CNC/Laser production steps.

**User Story:** As an admin, I want to browse our GitHub gCode repository and select files for production steps, so that workers can execute the correct machining operations.

**Prompt:**

```
We need to integrate with our GitHub gCode repository to fetch and cache available gCode files.

REPOSITORY STRUCTURE:
```
Saturday-Vinyl/gcode/
├── turntable-base/
│   ├── README.md (contains: # Mill Turntable Base)
│   └── base-mill.gcode
├── platter-holes/
│   ├── README.md (contains: # Drill Platter Mounting Holes)
│   └── holes.nc
└── laser-engrave/
    ├── README.md (contains: # Engrave Logo)
    └── logo-engrave.gcode
```

REQUIREMENTS:

1. ENVIRONMENT CONFIGURATION

   Add to .env file:
   ```
   GITHUB_TOKEN=ghp_xxxxxxxxxxxxx
   GITHUB_REPO_OWNER=Saturday-Vinyl
   GITHUB_REPO_NAME=gcode
   ```

   Add to EnvConfig (lib/config/env_config.dart):
   ```dart
   static String get githubToken => _get('GITHUB_TOKEN');
   static String get githubRepoOwner => _get('GITHUB_REPO_OWNER');
   static String get githubRepoName => _get('GITHUB_REPO_NAME');
   ```

2. CREATE GITHUB SERVICE

   lib/services/github_service.dart:
   ```dart
   class GitHubService {
     final String _token;
     final String _owner;
     final String _repo;

     GitHubService({
       required String token,
       required String owner,
       required String repo,
     });

     /// Fetch repository tree (all files and folders)
     Future<List<GitHubTreeItem>> fetchRepositoryTree() async {
       // GET https://api.github.com/repos/{owner}/{repo}/git/trees/main?recursive=1
       // Headers: Authorization: Bearer {token}
       // Parse response, filter for .gcode, .nc, and .md files
     }

     /// Fetch content of a specific file
     Future<String> fetchFileContent(String path) async {
       // GET https://api.github.com/repos/{owner}/{repo}/contents/{path}
       // Decode base64 content
       // Return decoded string
     }

     /// Parse README.md to extract H1 title
     String extractH1FromMarkdown(String markdown) {
       // Parse markdown, find first # heading
       // Return heading text (without #)
       // If no H1 found, return folder name as fallback
     }

     /// Build gCode file structure from tree
     Future<List<GCodeFileData>> buildGCodeFileList() async {
       final tree = await fetchRepositoryTree();

       // Group files by folder
       // For each folder with .gcode or .nc files:
       //   - Find README.md in same folder
       //   - Fetch README content
       //   - Extract H1 title
       //   - Create GCodeFileData for each gcode file

       return gcodeFiles;
     }
   }

   class GCodeFileData {
     final String folderPath;
     final String fileName;
     final String displayName; // H1 from README
     final String githubUrl; // raw.githubusercontent.com URL
     final String fileType;
   }
   ```

3. CREATE REPOSITORY SYNC SERVICE

   lib/services/gcode_sync_service.dart:
   ```dart
   class GCodeSyncService {
     final GitHubService _githubService;
     final GCodeFileRepository _repository;

     /// Sync repository: fetch from GitHub and update database
     Future<SyncResult> syncRepository() async {
       try {
         // 1. Fetch gCode files from GitHub
         final githubFiles = await _githubService.buildGCodeFileList();

         // 2. Clear existing cache (or do smart diff)
         await _repository.deleteAll();

         // 3. Insert new files
         for (final fileData in githubFiles) {
           final gcodeFile = GCodeFile(
             id: generateUuid(),
             folderPath: fileData.folderPath,
             fileName: fileData.fileName,
             displayName: fileData.displayName,
             githubUrl: fileData.githubUrl,
             fileType: fileData.fileType,
             lastSyncedAt: DateTime.now(),
             createdAt: DateTime.now(),
             updatedAt: DateTime.now(),
           );

           await _repository.createFile(gcodeFile);
         }

         return SyncResult(
           success: true,
           fileCount: githubFiles.length,
           syncedAt: DateTime.now(),
         );
       } catch (e) {
         return SyncResult(
           success: false,
           error: e.toString(),
         );
       }
     }

     /// Fetch actual gCode content from GitHub (on-demand)
     Future<String> fetchGCodeContent(GCodeFile file) async {
       return await _githubService.fetchFileContent(
         '${file.folderPath}/${file.fileName}',
       );
     }
   }

   class SyncResult {
     final bool success;
     final int? fileCount;
     final DateTime? syncedAt;
     final String? error;
   }
   ```

4. ADD PROVIDER

   lib/providers/gcode_sync_provider.dart:
   ```dart
   final gcodeSyncServiceProvider = Provider<GCodeSyncService>((ref) {
     return GCodeSyncService(
       githubService: GitHubService(
         token: EnvConfig.githubToken,
         owner: EnvConfig.githubRepoOwner,
         repo: EnvConfig.githubRepoName,
       ),
       repository: ref.read(gcodeFileRepositoryProvider),
     );
   });

   // Provider to trigger sync and watch status
   final gcodeSyncStatusProvider = StateProvider<SyncResult?>((ref) => null);
   ```

5. ADD SETTINGS UI

   Update lib/screens/settings/settings_screen.dart:

   Add new card after Scanner Configuration:
   ```dart
   // GitHub gCode Repository Section
   Card(
     child: Padding(
       padding: EdgeInsets.all(24),
       child: Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Row(
             children: [
               Icon(Icons.code, color: SaturdayColors.primaryDark),
               SizedBox(width: 12),
               Text('gCode Repository',
                 style: Theme.of(context).textTheme.titleLarge?.copyWith(
                   fontWeight: FontWeight.bold,
                 ),
               ),
             ],
           ),
           SizedBox(height: 16),

           // Repository info
           _buildInfoRow('Repository', 'Saturday-Vinyl/gcode'),
           _buildInfoRow('Status', syncStatus?.success == true
             ? 'Synced ✓' : 'Not synced'),

           if (syncStatus?.syncedAt != null)
             _buildInfoRow('Last Synced',
               formatDateTime(syncStatus!.syncedAt)),

           if (syncStatus?.fileCount != null)
             _buildInfoRow('Cached Files',
               '${syncStatus!.fileCount} files'),

           SizedBox(height: 16),

           // Refresh button
           ElevatedButton.icon(
             onPressed: isSyncing ? null : _refreshRepository,
             icon: isSyncing
               ? SizedBox(
                   width: 16,
                   height: 16,
                   child: CircularProgressIndicator(strokeWidth: 2),
                 )
               : Icon(Icons.refresh),
             label: Text(isSyncing ? 'Syncing...' : 'Refresh Repository'),
           ),

           if (syncStatus?.error != null)
             Container(
               margin: EdgeInsets.only(top: 16),
               padding: EdgeInsets.all(12),
               decoration: BoxDecoration(
                 color: SaturdayColors.error.withOpacity(0.1),
                 borderRadius: BorderRadius.circular(8),
               ),
               child: Text(
                 'Error: ${syncStatus!.error}',
                 style: TextStyle(color: SaturdayColors.error),
               ),
             ),
         ],
       ),
     ),
   )
   ```

   Implement _refreshRepository method:
   ```dart
   Future<void> _refreshRepository() async {
     setState(() => isSyncing = true);

     try {
       final syncService = ref.read(gcodeSyncServiceProvider);
       final result = await syncService.syncRepository();

       ref.read(gcodeSyncStatusProvider.notifier).state = result;

       if (result.success) {
         // Invalidate cache to reload file list
         ref.invalidate(allGCodeFilesProvider);

         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Repository synced: ${result.fileCount} files'),
             backgroundColor: SaturdayColors.success,
           ),
         );
       } else {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Sync failed: ${result.error}'),
             backgroundColor: SaturdayColors.error,
           ),
         );
       }
     } finally {
       setState(() => isSyncing = false);
     }
   }
   ```

6. DEPENDENCIES

   Add to pubspec.yaml:
   ```yaml
   dependencies:
     http: ^1.1.0  # For GitHub API calls (if not already present)
   ```

TESTING REQUIREMENTS:
- [ ] GitHub API authentication works with token
- [ ] Can fetch repository tree
- [ ] Can parse README.md files and extract H1
- [ ] Sync populates gcode_files table correctly
- [ ] Can fetch gCode file content on-demand
- [ ] Settings UI shows sync status
- [ ] Refresh button triggers sync
- [ ] Error handling for network issues
- [ ] Error handling for invalid token
- [ ] Folder names with special characters handled correctly

EDGE CASES TO HANDLE:
- README.md with no H1 → use folder name
- Multiple README files in folder → use first one
- No README in folder → use folder name
- Empty repository → show appropriate message
- Network timeout → show error and allow retry
- Invalid GitHub token → clear error message

Please implement the complete GitHub integration with sync functionality.
```

**Expected Outcome:**
- GitHub API integration fetches repository structure
- README files parsed to extract display names
- gcode_files table populated with cached data
- Settings screen has repository sync UI
- On-demand fetching of gCode content works
- Error handling for network/auth issues

**Dependencies:** Prompt 36 (Database schema)
**Estimated Time:** 6-8 hours
**Complexity:** Medium-High
**Testing Required:** Integration tests with GitHub API, Manual testing with real repository

---

## Phase 3: Machine Communication

### Prompt 38: Serial Communication and Machine Control

**Context:** We need to communicate with CNC and Laser machines via USB serial connections. CNC machines use grblHAL protocol, Laser machines use grbl protocol. Both communicate at 115200 baud over serial, using line-by-line gCode streaming with "ok" acknowledgments.

**User Story:** As a worker, I want to connect to CNC/Laser machines and send gCode commands, so that I can automate machining operations during production steps.

**Prompt:**

```
We need to implement USB serial communication with CNC and Laser machines using grbl/grblHAL protocols.

REQUIREMENTS:

1. ADD DEPENDENCIES

   pubspec.yaml:
   ```yaml
   dependencies:
     flutter_libserialport: ^0.4.0  # Cross-platform serial port communication
   ```

2. CREATE MACHINE CONNECTION SERVICE

   lib/services/machine_connection_service.dart:
   ```dart
   enum MachineType { cnc, laser }

   enum MachineState {
     disconnected,
     connecting,
     connected,
     idle,
     running,
     paused,
     alarm,
     error,
   }

   class MachineConnectionService {
     SerialPort? _port;
     SerialPortReader? _reader;
     MachineState _state = MachineState.disconnected;

     // Stream for machine responses
     final _responseController = StreamController<String>.broadcast();
     Stream<String> get responseStream => _responseController.stream;

     // Stream for state changes
     final _stateController = StreamController<MachineState>.broadcast();
     Stream<MachineState> get stateStream => _stateController.stream;

     MachineState get currentState => _state;

     /// List available serial ports
     static List<String> listAvailablePorts() {
       return SerialPort.availablePorts;
     }

     /// Connect to machine
     Future<bool> connect(String portName) async {
       try {
         _updateState(MachineState.connecting);

         _port = SerialPort(portName);

         // Configure port (115200 baud, 8N1)
         _port!.config = SerialPortConfig()
           ..baudRate = 115200
           ..bits = 8
           ..parity = SerialPortParity.none
           ..stopBits = 1;

         // Open port
         if (!_port!.openReadWrite()) {
           throw Exception('Failed to open port: ${_port!.lastError}');
         }

         // Start reading responses
         _reader = SerialPortReader(_port!);
         _reader!.stream.listen(
           (data) {
             final response = String.fromCharCodes(data).trim();
             _responseController.add(response);
             _handleResponse(response);
           },
           onError: (error) {
             AppLogger.error('Serial read error', error);
             _updateState(MachineState.error);
           },
         );

         _updateState(MachineState.connected);

         // Query initial status
         await Future.delayed(Duration(milliseconds: 500));
         await queryStatus();

         return true;
       } catch (e) {
         AppLogger.error('Failed to connect to machine', e);
         _updateState(MachineState.disconnected);
         return false;
       }
     }

     /// Disconnect from machine
     void disconnect() {
       _reader?.close();
       _port?.close();
       _port = null;
       _updateState(MachineState.disconnected);
     }

     /// Send single line command
     Future<bool> sendCommand(String command) async {
       if (_port == null || !_port!.isOpen) {
         throw Exception('Port not connected');
       }

       try {
         final line = command.trim() + '\n';
         final bytes = line.codeUnits;

         final written = _port!.write(Uint8List.fromList(bytes));

         if (written != bytes.length) {
           throw Exception('Failed to write complete command');
         }

         AppLogger.debug('Sent: $command');
         return true;
       } catch (e) {
         AppLogger.error('Failed to send command', e);
         return false;
       }
     }

     /// Wait for "ok" response (with timeout)
     Future<bool> waitForOk({Duration timeout = const Duration(seconds: 10)}) async {
       final completer = Completer<bool>();
       StreamSubscription? subscription;

       subscription = responseStream.listen((response) {
         if (response.toLowerCase() == 'ok') {
           if (!completer.isCompleted) {
             completer.complete(true);
             subscription?.cancel();
           }
         } else if (response.toLowerCase().startsWith('error')) {
           if (!completer.isCompleted) {
             completer.complete(false);
             subscription?.cancel();
           }
         }
       });

       // Timeout
       Future.delayed(timeout, () {
         if (!completer.isCompleted) {
           completer.complete(false);
           subscription?.cancel();
         }
       });

       return completer.future;
     }

     /// Query machine status ($$ command)
     Future<void> queryStatus() async {
       await sendCommand('$$');
     }

     /// Home machine ($H command)
     Future<bool> home() async {
       _updateState(MachineState.running);
       await sendCommand('\$H');
       final success = await waitForOk(timeout: Duration(seconds: 60));

       if (success) {
         _updateState(MachineState.idle);
       } else {
         _updateState(MachineState.error);
       }

       return success;
     }

     /// Set current position as zero (G10 L20 P0 Xn Yn Zn)
     Future<bool> setZero({bool x = false, bool y = false, bool z = false}) async {
       final parts = <String>[];
       if (x) parts.add('X0');
       if (y) parts.add('Y0');
       if (z) parts.add('Z0');

       if (parts.isEmpty) return false;

       final command = 'G10 L20 P0 ${parts.join(' ')}';
       await sendCommand(command);
       return await waitForOk();
     }

     /// Emergency stop (M112 command + soft reset)
     Future<void> emergencyStop() async {
       await sendCommand('M112');
       await Future.delayed(Duration(milliseconds: 100));

       // Send soft reset (Ctrl-X = 0x18)
       if (_port != null && _port!.isOpen) {
         _port!.write(Uint8List.fromList([0x18]));
       }

       _updateState(MachineState.alarm);
     }

     /// Pause execution (!)
     Future<void> pause() async {
       await sendCommand('!');
       _updateState(MachineState.paused);
     }

     /// Resume execution (~)
     Future<void> resume() async {
       await sendCommand('~');
       _updateState(MachineState.running);
     }

     /// Handle incoming responses
     void _handleResponse(String response) {
       AppLogger.debug('Received: $response');

       // Parse status responses
       if (response.startsWith('<') && response.endsWith('>')) {
         // Real-time status report: <Idle|MPos:0.000,0.000,0.000|...>
         final status = response.substring(1, response.length - 1);
         final parts = status.split('|');

         if (parts.isNotEmpty) {
           final state = parts[0].toLowerCase();

           if (state == 'idle') {
             _updateState(MachineState.idle);
           } else if (state == 'run') {
             _updateState(MachineState.running);
           } else if (state == 'hold') {
             _updateState(MachineState.paused);
           } else if (state.contains('alarm')) {
             _updateState(MachineState.alarm);
           }
         }
       }
     }

     void _updateState(MachineState newState) {
       if (_state != newState) {
         _state = newState;
         _stateController.add(newState);
         AppLogger.info('Machine state: $newState');
       }
     }

     void dispose() {
       disconnect();
       _responseController.close();
       _stateController.close();
     }
   }
   ```

3. CREATE GCODE STREAMING SERVICE

   lib/services/gcode_streaming_service.dart:
   ```dart
   class GCodeStreamingService {
     final MachineConnectionService _machine;

     bool _isStreaming = false;
     bool _isPaused = false;
     int _currentLine = 0;
     int _totalLines = 0;

     final _progressController = StreamController<StreamProgress>.broadcast();
     Stream<StreamProgress> get progressStream => _progressController.stream;

     /// Stream gCode line-by-line with "ok" acknowledgment
     Future<StreamResult> streamGCode(String gcodeContent) async {
       if (_isStreaming) {
         throw Exception('Already streaming gCode');
       }

       try {
         _isStreaming = true;
         _isPaused = false;

         // Split into lines, filter comments and empty lines
         final lines = gcodeContent
           .split('\n')
           .map((line) => line.trim())
           .where((line) => line.isNotEmpty && !line.startsWith(';'))
           .toList();

         _totalLines = lines.length;
         _currentLine = 0;

         AppLogger.info('Streaming ${_totalLines} lines of gCode');

         for (final line in lines) {
           // Check if paused
           while (_isPaused && _isStreaming) {
             await Future.delayed(Duration(milliseconds: 100));
           }

           // Check if stopped
           if (!_isStreaming) {
             return StreamResult(
               success: false,
               linesCompleted: _currentLine,
               totalLines: _totalLines,
               message: 'Streaming cancelled',
             );
           }

           // Send line
           await _machine.sendCommand(line);

           // Wait for "ok"
           final ok = await _machine.waitForOk();

           if (!ok) {
             _isStreaming = false;
             return StreamResult(
               success: false,
               linesCompleted: _currentLine,
               totalLines: _totalLines,
               message: 'Machine did not acknowledge command: $line',
             );
           }

           _currentLine++;

           // Update progress
           _progressController.add(StreamProgress(
             currentLine: _currentLine,
             totalLines: _totalLines,
             percentComplete: (_currentLine / _totalLines * 100).round(),
             lastCommand: line,
           ));
         }

         _isStreaming = false;

         return StreamResult(
           success: true,
           linesCompleted: _currentLine,
           totalLines: _totalLines,
           message: 'Streaming completed successfully',
         );

       } catch (e) {
         _isStreaming = false;
         AppLogger.error('gCode streaming error', e);

         return StreamResult(
           success: false,
           linesCompleted: _currentLine,
           totalLines: _totalLines,
           message: 'Error: ${e.toString()}',
         );
       }
     }

     void pause() {
       if (_isStreaming) {
         _isPaused = true;
         _machine.pause();
       }
     }

     void resume() {
       if (_isStreaming && _isPaused) {
         _isPaused = false;
         _machine.resume();
       }
     }

     void stop() {
       _isStreaming = false;
       _isPaused = false;
       _machine.emergencyStop();
     }

     bool get isStreaming => _isStreaming;
     bool get isPaused => _isPaused;

     void dispose() {
       _progressController.close();
     }
   }

   class StreamProgress {
     final int currentLine;
     final int totalLines;
     final int percentComplete;
     final String lastCommand;

     StreamProgress({
       required this.currentLine,
       required this.totalLines,
       required this.percentComplete,
       required this.lastCommand,
     });
   }

   class StreamResult {
     final bool success;
     final int linesCompleted;
     final int totalLines;
     final String message;

     StreamResult({
       required this.success,
       required this.linesCompleted,
       required this.totalLines,
       required this.message,
     });
   }
   ```

4. ADD LOCAL STORAGE FOR MACHINE CONFIGS

   lib/services/machine_config_storage.dart:
   ```dart
   class MachineConfigStorage {
     static const _cncPortKey = 'cnc_serial_port';
     static const _laserPortKey = 'laser_serial_port';

     final SharedPreferences _prefs;

     MachineConfigStorage(this._prefs);

     // CNC machine port
     String? getCncPort() => _prefs.getString(_cncPortKey);
     Future<void> setCncPort(String port) => _prefs.setString(_cncPortKey, port);
     Future<void> clearCncPort() => _prefs.remove(_cncPortKey);

     // Laser machine port
     String? getLaserPort() => _prefs.getString(_laserPortKey);
     Future<void> setLaserPort(String port) => _prefs.setString(_laserPortKey, port);
     Future<void> clearLaserPort() => _prefs.remove(_laserPortKey);
   }
   ```

5. ADD PROVIDERS

   lib/providers/machine_provider.dart:
   ```dart
   final machineConfigStorageProvider = Provider<MachineConfigStorage>((ref) {
     // Assumes sharedPreferencesProvider exists
     final prefs = ref.watch(sharedPreferencesProvider);
     return MachineConfigStorage(prefs);
   });

   final cncMachineServiceProvider = Provider<MachineConnectionService>((ref) {
     return MachineConnectionService();
   });

   final laserMachineServiceProvider = Provider<MachineConnectionService>((ref) {
     return MachineConnectionService();
   });

   final cncStreamingServiceProvider = Provider<GCodeStreamingService>((ref) {
     final machine = ref.watch(cncMachineServiceProvider);
     return GCodeStreamingService(machine);
   });

   final laserStreamingServiceProvider = Provider<GCodeStreamingService>((ref) {
     final machine = ref.watch(laserMachineServiceProvider);
     return GCodeStreamingService(machine);
   });
   ```

6. ADD MACHINE CONFIGURATION UI IN SETTINGS

   Update lib/screens/settings/settings_screen.dart:

   Add Machine Configuration card:
   ```dart
   Card(
     child: Padding(
       padding: EdgeInsets.all(24),
       child: Column(
         children: [
           Text('Machine Configuration', style: titleStyle),
           SizedBox(height: 24),

           // CNC Machine section
           _buildMachineConfig(
             title: 'CNC Machine',
             subtitle: 'grblHAL Protocol',
             machineType: MachineType.cnc,
             currentPort: cncPort,
             onPortSelected: (port) => _saveCncPort(port),
             onTestConnection: () => _testCncConnection(),
           ),

           Divider(height: 32),

           // Laser Machine section
           _buildMachineConfig(
             title: 'Laser Machine',
             subtitle: 'grbl Protocol',
             machineType: MachineType.laser,
             currentPort: laserPort,
             onPortSelected: (port) => _saveLaserPort(port),
             onTestConnection: () => _testLaserConnection(),
           ),
         ],
       ),
     ),
   )
   ```

   Implement _buildMachineConfig:
   ```dart
   Widget _buildMachineConfig({
     required String title,
     required String subtitle,
     required MachineType machineType,
     required String? currentPort,
     required Function(String) onPortSelected,
     required VoidCallback onTestConnection,
   }) {
     return Column(
       crossAxisAlignment: CrossAxisAlignment.start,
       children: [
         Text(title, style: subtitleStyle),
         Text(subtitle, style: captionStyle),
         SizedBox(height: 12),

         Row(
           children: [
             Expanded(
               child: DropdownButtonFormField<String>(
                 value: currentPort,
                 decoration: InputDecoration(
                   labelText: 'Serial Port',
                   border: OutlineInputBorder(),
                 ),
                 items: availablePorts.map((port) {
                   return DropdownMenuItem(
                     value: port,
                     child: Text(port),
                   );
                 }).toList(),
                 onChanged: (port) {
                   if (port != null) onPortSelected(port);
                 },
               ),
             ),
             SizedBox(width: 8),
             ElevatedButton(
               onPressed: _refreshPorts,
               child: Icon(Icons.refresh),
             ),
           ],
         ),

         SizedBox(height: 8),

         OutlinedButton.icon(
           onPressed: currentPort == null ? null : onTestConnection,
           icon: Icon(Icons.cable),
           label: Text('Test Connection'),
         ),
       ],
     );
   }
   ```

   Implement test connection:
   ```dart
   Future<void> _testCncConnection() async {
     final machine = ref.read(cncMachineServiceProvider);
     final port = cncPort;

     if (port == null) return;

     try {
       final connected = await machine.connect(port);

       if (connected) {
         // Send status query
         await machine.queryStatus();

         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('CNC Machine connected successfully'),
             backgroundColor: SaturdayColors.success,
           ),
         );

         // Disconnect after test
         await Future.delayed(Duration(seconds: 2));
         machine.disconnect();
       } else {
         throw Exception('Failed to connect');
       }
     } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Connection failed: $e'),
           backgroundColor: SaturdayColors.error,
         ),
       );
     }
   }
   ```

TESTING REQUIREMENTS:
- [ ] Can list available serial ports
- [ ] Can connect to machine at 115200 baud
- [ ] Can send commands and receive responses
- [ ] "ok" acknowledgment detected correctly
- [ ] Can stream gCode line-by-line
- [ ] Waits for "ok" before sending next line
- [ ] Home command works ($H)
- [ ] Set zero commands work (G10 L20 P0)
- [ ] Emergency stop works (M112)
- [ ] Pause/resume works during streaming
- [ ] Connection lost detected and handled
- [ ] Machine configuration saved to local storage
- [ ] Test connection validates machine responds

EDGE CASES:
- Port in use by another application
- Machine not responding (timeout)
- Connection lost mid-stream
- Invalid gCode syntax
- Machine alarm state
- Buffer overflow prevention

Please implement complete machine communication system.
```

**Expected Outcome:**
- Serial port communication works on desktop platforms
- Can connect/disconnect from machines
- gCode streaming with "ok" acknowledgment works
- Machine control commands (home, zero, stop) work
- Settings UI for machine configuration
- Local storage persists port selections

**Dependencies:** Prompt 36 (Database schema)
**Estimated Time:** 8-10 hours
**Complexity:** High
**Testing Required:** Manual testing with actual machines, Unit tests for protocols

---

## Phase 4: Step Configuration UI

### Prompt 39: Production Step Form with Step Types

**Context:** We need to update the production step configuration form to support the new step types (General, CNC Milling, Laser Cutting) with their type-specific configurations.

For CNC/Laser steps, admins need to:
- Select gCode files from the GitHub repository cache
- Order them for sequential execution
- (Laser only) Configure QR code engraving parameters

**User Story:** As an admin, I want to configure production steps with machine-specific settings and gCode files, so that workers have the correct machining operations available during production.

**Prompt:**

```
We need to update the production step form to support different step types with conditional configuration sections.

CURRENT FORM (from Prompt 12):
- Name
- Description
- Step order
- File attachment (optional)
- Labels (multiple, from Prompt 35)

NEW REQUIREMENTS:

1. ADD STEP TYPE SELECTOR AT TOP OF FORM

   lib/screens/products/production_step_form_screen.dart:

   Add after name field:
   ```dart
   // Step Type dropdown
   DropdownButtonFormField<StepType>(
     value: _selectedStepType,
     decoration: InputDecoration(
       labelText: 'Step Type',
       border: OutlineInputBorder(),
       helper: Text('Determines available configuration options'),
     ),
     items: StepType.values.map((type) {
       return DropdownMenuItem(
         value: type,
         child: Row(
           children: [
             Icon(_getStepTypeIcon(type)),
             SizedBox(width: 8),
             Text(type.displayName),
           ],
         ),
       );
     }).toList(),
     onChanged: (stepType) {
       setState(() {
         _selectedStepType = stepType!;
         // Clear type-specific data if type changed
         if (widget.step != null && widget.step!.stepType != stepType) {
           _showTypeChangeWarning();
         }
       });
     },
     validator: (value) {
       if (value == null) return 'Please select a step type';
       return null;
     },
   )

   IconData _getStepTypeIcon(StepType type) {
     switch (type) {
       case StepType.general:
         return Icons.assignment;
       case StepType.cncMilling:
         return Icons.precision_manufacturing;
       case StepType.laserCutting:
         return Icons.flash_on;
     }
   }
   ```

2. CONDITIONAL CONFIGURATION SECTIONS

   A. For GENERAL steps - show file attachment (existing functionality):
   ```dart
   if (_selectedStepType == StepType.general) ...[
     SizedBox(height: 24),
     _buildFileAttachmentSection(),
   ],
   ```

   B. For CNC MILLING or LASER CUTTING - show machine configuration:
   ```dart
   if (_selectedStepType == StepType.cncMilling ||
       _selectedStepType == StepType.laserCutting) ...[
     SizedBox(height: 24),
     _buildMachineConfigurationSection(),
   ],
   ```

   C. For LASER CUTTING only - show QR engraving configuration:
   ```dart
   if (_selectedStepType == StepType.laserCutting) ...[
     SizedBox(height: 24),
     _buildQrEngravingSection(),
   ],
   ```

3. BUILD MACHINE CONFIGURATION SECTION

   ```dart
   Widget _buildMachineConfigurationSection() {
     return Card(
       elevation: 2,
       child: Padding(
         padding: EdgeInsets.all(16),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Row(
               children: [
                 Icon(Icons.code, color: SaturdayColors.primaryDark),
                 SizedBox(width: 8),
                 Text(
                   'gCode Files',
                   style: TextStyle(
                     fontSize: 18,
                     fontWeight: FontWeight.bold,
                   ),
                 ),
               ],
             ),
             SizedBox(height: 8),
             Text(
               'Select gCode files to run during this step',
               style: TextStyle(
                 fontSize: 14,
                 color: SaturdayColors.secondaryGrey,
               ),
             ),

             SizedBox(height: 16),

             // Selected files list (ordered, drag-to-reorder)
             if (_selectedGCodeFiles.isNotEmpty) ...[
               Text(
                 'Selected Files (${_selectedGCodeFiles.length})',
                 style: TextStyle(fontWeight: FontWeight.w600),
               ),
               SizedBox(height: 8),
               _buildSelectedFilesList(),
               SizedBox(height: 16),
             ],

             // Add file button
             OutlinedButton.icon(
               onPressed: _showGCodeFilePicker,
               icon: Icon(Icons.add),
               label: Text('Add gCode File'),
             ),
           ],
         ),
       ),
     );
   }
   ```

4. BUILD SELECTED FILES LIST (with drag-to-reorder)

   ```dart
   Widget _buildSelectedFilesList() {
     return ReorderableListView.builder(
       shrinkWrap: true,
       physics: NeverScrollableScrollPhysics(),
       itemCount: _selectedGCodeFiles.length,
       onReorder: (oldIndex, newIndex) {
         setState(() {
           if (newIndex > oldIndex) newIndex--;
           final item = _selectedGCodeFiles.removeAt(oldIndex);
           _selectedGCodeFiles.insert(newIndex, item);
         });
       },
       itemBuilder: (context, index) {
         final file = _selectedGCodeFiles[index];

         return Card(
           key: ValueKey(file.id),
           margin: EdgeInsets.only(bottom: 8),
           child: ListTile(
             leading: Row(
               mainAxisSize: MainAxisSize.min,
               children: [
                 Icon(Icons.drag_handle),
                 SizedBox(width: 8),
                 Container(
                   padding: EdgeInsets.all(8),
                   decoration: BoxDecoration(
                     color: SaturdayColors.primaryDark,
                     shape: BoxShape.circle,
                   ),
                   child: Text(
                     '${index + 1}',
                     style: TextStyle(
                       color: Colors.white,
                       fontWeight: FontWeight.bold,
                     ),
                   ),
                 ),
               ],
             ),
             title: Text(file.displayName),
             subtitle: Text(file.folderPath),
             trailing: IconButton(
               icon: Icon(Icons.delete, color: SaturdayColors.error),
               onPressed: () {
                 setState(() {
                   _selectedGCodeFiles.removeAt(index);
                 });
               },
             ),
           ),
         );
       },
     );
   }
   ```

5. CREATE GCODE FILE PICKER DIALOG

   ```dart
   Future<void> _showGCodeFilePicker() async {
     final selectedFile = await showDialog<GCodeFile>(
       context: context,
       builder: (context) => GCodeFilePickerDialog(
         excludeIds: _selectedGCodeFiles.map((f) => f.id).toList(),
       ),
     );

     if (selectedFile != null) {
       setState(() {
         _selectedGCodeFiles.add(selectedFile);
       });
     }
   }
   ```

   Create lib/widgets/production/gcode_file_picker_dialog.dart:
   ```dart
   class GCodeFilePickerDialog extends ConsumerStatefulWidget {
     final List<String> excludeIds; // Already selected file IDs

     const GCodeFilePickerDialog({
       super.key,
       this.excludeIds = const [],
     });
   }

   class _GCodeFilePickerDialogState extends ConsumerState<GCodeFilePickerDialog> {
     String _searchQuery = '';

     @override
     Widget build(BuildContext context) {
       final filesAsync = ref.watch(allGCodeFilesProvider);

       return Dialog(
         child: Container(
           width: 600,
           height: 700,
           child: Column(
             children: [
               // Header
               AppBar(
                 title: Text('Select gCode File'),
                 automaticallyImplyLeading: false,
                 actions: [
                   IconButton(
                     icon: Icon(Icons.close),
                     onPressed: () => Navigator.pop(context),
                   ),
                 ],
               ),

               // Search bar
               Padding(
                 padding: EdgeInsets.all(16),
                 child: TextField(
                   decoration: InputDecoration(
                     hintText: 'Search gCode files...',
                     prefixIcon: Icon(Icons.search),
                     border: OutlineInputBorder(),
                   ),
                   onChanged: (query) {
                     setState(() => _searchQuery = query.toLowerCase());
                   },
                 ),
               ),

               // File list
               Expanded(
                 child: filesAsync.when(
                   data: (files) {
                     // Filter out excluded files
                     var filteredFiles = files
                       .where((f) => !widget.excludeIds.contains(f.id))
                       .toList();

                     // Apply search
                     if (_searchQuery.isNotEmpty) {
                       filteredFiles = filteredFiles.where((f) {
                         return f.displayName.toLowerCase().contains(_searchQuery) ||
                                f.folderPath.toLowerCase().contains(_searchQuery);
                       }).toList();
                     }

                     if (filteredFiles.isEmpty) {
                       return Center(
                         child: Text('No gCode files found'),
                       );
                     }

                     // Group by folder
                     final grouped = <String, List<GCodeFile>>{};
                     for (final file in filteredFiles) {
                       grouped.putIfAbsent(file.folderPath, () => []).add(file);
                     }

                     return ListView.builder(
                       itemCount: grouped.length,
                       itemBuilder: (context, index) {
                         final folder = grouped.keys.elementAt(index);
                         final folderFiles = grouped[folder]!;

                         return ExpansionTile(
                           title: Text(folder),
                           subtitle: Text('${folderFiles.length} files'),
                           children: folderFiles.map((file) {
                             return ListTile(
                               leading: Icon(Icons.code_file),
                               title: Text(file.displayName),
                               subtitle: Text('${file.fileName} (${file.fileType})'),
                               onTap: () => Navigator.pop(context, file),
                             );
                           }).toList(),
                         );
                       },
                     );
                   },
                   loading: () => Center(child: CircularProgressIndicator()),
                   error: (error, stack) => Center(
                     child: Text('Error loading files: $error'),
                   ),
                 ),
               ),
             ],
           ),
         ),
       );
     }
   }
   ```

6. BUILD QR ENGRAVING SECTION (Laser only)

   ```dart
   Widget _buildQrEngravingSection() {
     return Card(
       elevation: 2,
       child: Padding(
         padding: EdgeInsets.all(16),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Row(
               children: [
                 Icon(Icons.qr_code, color: SaturdayColors.primaryDark),
                 SizedBox(width: 8),
                 Text(
                   'QR Code Engraving',
                   style: TextStyle(
                     fontSize: 18,
                     fontWeight: FontWeight.bold,
                   ),
                 ),
               ],
             ),

             SizedBox(height: 16),

             // Enable checkbox
             CheckboxListTile(
               title: Text('Enable QR Code Engraving'),
               subtitle: Text('Engrave production unit QR code during this step'),
               value: _enableQrEngraving,
               onChanged: (value) {
                 setState(() => _enableQrEngraving = value ?? false);
               },
               controlAffinity: ListTileControlAffinity.leading,
               contentPadding: EdgeInsets.zero,
             ),

             if (_enableQrEngraving) ...[
               Divider(),
               SizedBox(height: 16),

               Text(
                 'Engraving Parameters',
                 style: TextStyle(fontWeight: FontWeight.w600),
               ),
               SizedBox(height: 12),

               // Dimensions
               Row(
                 children: [
                   Expanded(
                     child: TextFormField(
                       controller: _qrWidthController,
                       decoration: InputDecoration(
                         labelText: 'Width (inches)',
                         border: OutlineInputBorder(),
                       ),
                       keyboardType: TextInputType.numberWithOptions(decimal: true),
                       validator: (value) {
                         if (value == null || value.isEmpty) return 'Required';
                         final num = double.tryParse(value);
                         if (num == null || num <= 0) return 'Must be > 0';
                         return null;
                       },
                     ),
                   ),
                   SizedBox(width: 16),
                   Expanded(
                     child: TextFormField(
                       controller: _qrHeightController,
                       decoration: InputDecoration(
                         labelText: 'Height (inches)',
                         border: OutlineInputBorder(),
                       ),
                       keyboardType: TextInputType.numberWithOptions(decimal: true),
                       validator: (value) {
                         if (value == null || value.isEmpty) return 'Required';
                         final num = double.tryParse(value);
                         if (num == null || num <= 0) return 'Must be > 0';
                         return null;
                       },
                     ),
                   ),
                 ],
               ),

               SizedBox(height: 16),

               // Starting position
               Row(
                 children: [
                   Expanded(
                     child: TextFormField(
                       controller: _qrStartXController,
                       decoration: InputDecoration(
                         labelText: 'Start X (inches)',
                         border: OutlineInputBorder(),
                         helperText: 'X position after homing',
                       ),
                       keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                       validator: (value) {
                         if (value == null || value.isEmpty) return 'Required';
                         if (double.tryParse(value) == null) return 'Invalid number';
                         return null;
                       },
                     ),
                   ),
                   SizedBox(width: 16),
                   Expanded(
                     child: TextFormField(
                       controller: _qrStartYController,
                       decoration: InputDecoration(
                         labelText: 'Start Y (inches)',
                         border: OutlineInputBorder(),
                         helperText: 'Y position after homing',
                       ),
                       keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                       validator: (value) {
                         if (value == null || value.isEmpty) return 'Required';
                         if (double.tryParse(value) == null) return 'Invalid number';
                         return null;
                       },
                     ),
                   ),
                 ],
               ),

               SizedBox(height: 16),

               // Power and feed rate
               Row(
                 children: [
                   Expanded(
                     child: TextFormField(
                       controller: _qrPowerController,
                       decoration: InputDecoration(
                         labelText: 'Laser Power (0-100)',
                         border: OutlineInputBorder(),
                         helperText: 'Maximum power for engraving',
                       ),
                       keyboardType: TextInputType.number,
                       validator: (value) {
                         if (value == null || value.isEmpty) return 'Required';
                         final num = int.tryParse(value);
                         if (num == null || num < 0 || num > 100) {
                           return 'Must be 0-100';
                         }
                         return null;
                       },
                     ),
                   ),
                   SizedBox(width: 16),
                   Expanded(
                     child: TextFormField(
                       controller: _qrFeedRateController,
                       decoration: InputDecoration(
                         labelText: 'Feed Rate (mm/min)',
                         border: OutlineInputBorder(),
                         helperText: 'Speed of engraving',
                       ),
                       keyboardType: TextInputType.number,
                       validator: (value) {
                         if (value == null || value.isEmpty) return 'Required';
                         final num = int.tryParse(value);
                         if (num == null || num <= 0) return 'Must be > 0';
                         return null;
                       },
                     ),
                   ),
                 ],
               ),

               SizedBox(height: 16),

               // Test engrave button
               OutlinedButton.icon(
                 onPressed: _testEngrave,
                 icon: Icon(Icons.play_arrow),
                 label: Text('Test Engrave'),
                 style: OutlinedButton.styleFrom(
                   foregroundColor: SaturdayColors.info,
                 ),
               ),
             ],
           ],
         ),
       ),
     );
   }
   ```

7. IMPLEMENT TEST ENGRAVE

   ```dart
   Future<void> _testEngrave() async {
     // Validate QR engraving fields
     if (!_formKey.currentState!.validate()) {
       return;
     }

     // Show dialog explaining test
     final proceed = await showDialog<bool>(
       context: context,
       builder: (context) => AlertDialog(
         title: Text('Test QR Code Engraving'),
         content: Text(
           'This will generate gCode for engraving a test QR code and '
           'open the Machine Control screen.\n\n'
           'Make sure your laser is connected and properly positioned.',
         ),
         actions: [
           TextButton(
             onPressed: () => Navigator.pop(context, false),
             child: Text('Cancel'),
           ),
           ElevatedButton(
             onPressed: () => Navigator.pop(context, true),
             child: Text('Continue'),
           ),
         ],
       ),
     );

     if (proceed != true) return;

     // TODO: Will implement in Prompt 40-41
     // Generate test QR code PNG
     // Convert to gCode
     // Open Machine Control screen with test gCode

     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text('Test engrave functionality coming in next phase'),
         backgroundColor: SaturdayColors.info,
       ),
     );
   }
   ```

8. UPDATE SAVE LOGIC

   ```dart
   Future<void> _saveStep() async {
     if (!_formKey.currentState!.validate()) return;

     // Gather all form data
     final step = ProductionStep(
       id: widget.step?.id ?? generateUuid(),
       productId: widget.productId,
       name: _nameController.text.trim(),
       description: _descriptionController.text.trim(),
       stepOrder: int.parse(_orderController.text),

       // New step type fields
       stepType: _selectedStepType,
       requiresMachine: _selectedStepType != StepType.general,
       machineType: _selectedStepType == StepType.general
         ? null
         : (_selectedStepType == StepType.cncMilling ? 'cnc' : 'laser'),

       // File attachment (general steps only)
       fileUrl: _selectedStepType == StepType.general ? _fileUrl : null,
       fileName: _selectedStepType == StepType.general ? _fileName : null,
       fileType: _selectedStepType == StepType.general ? _fileType : null,

       // QR engraving (laser steps only)
       enableQrEngraving: _selectedStepType == StepType.laserCutting
         ? _enableQrEngraving
         : false,
       qrEngraveWidth: _enableQrEngraving
         ? double.tryParse(_qrWidthController.text)
         : null,
       qrEngraveHeight: _enableQrEngraving
         ? double.tryParse(_qrHeightController.text)
         : null,
       qrEngraveStartX: _enableQrEngraving
         ? double.tryParse(_qrStartXController.text)
         : null,
       qrEngraveStartY: _enableQrEngraving
         ? double.tryParse(_qrStartYController.text)
         : null,
       qrEngravePower: _enableQrEngraving
         ? int.tryParse(_qrPowerController.text)
         : null,
       qrEngraveFeedRate: _enableQrEngraving
         ? int.tryParse(_qrFeedRateController.text)
         : null,

       createdAt: widget.step?.createdAt ?? DateTime.now(),
       updatedAt: DateTime.now(),
     );

     // Save step
     await productionStepRepository.upsert(step);

     // Save gCode file associations (if CNC/Laser step)
     if (_selectedStepType != StepType.general && _selectedGCodeFiles.isNotEmpty) {
       final fileIds = _selectedGCodeFiles.map((f) => f.id).toList();
       await stepGCodeFileRepository.setFilesForStep(step.id, fileIds);
     }

     // Save labels (existing functionality from Prompt 35)
     // ... label saving code ...

     // Navigate back
     Navigator.pop(context);
   }
   ```

TESTING REQUIREMENTS:
- [ ] Can select step type
- [ ] Changing step type shows appropriate configuration sections
- [ ] Can browse and select gCode files from cache
- [ ] Selected files display in order with drag-to-reorder
- [ ] Can remove selected files
- [ ] QR engraving section shows for laser steps only
- [ ] QR engraving parameters validate correctly
- [ ] Test engrave button available (even if not functional yet)
- [ ] Save persists step type and configurations
- [ ] gCode file associations saved correctly
- [ ] Loading existing step populates all fields correctly
- [ ] Form validation prevents invalid data

Please implement the complete step configuration UI with step types.
```

**Expected Outcome:**
- Production step form supports three step types
- Conditional sections show based on selected type
- gCode file picker browses cached repository
- Drag-and-drop ordering works for gCode files
- QR engraving parameters configurable for laser steps
- Save persists all step type-specific data
- Form loads existing step configurations correctly

**Dependencies:** Prompts 36, 37 (Database, GitHub integration)
**Estimated Time:** 8-10 hours
**Complexity:** High
**Testing Required:** Manual UI testing, Form validation tests

---

## Phase 5: PNG to gCode Conversion

### Prompt 40: QR Code Engraving - Image to gCode

**Context:** For laser cutting steps with QR engraving enabled, we need to convert the production unit's QR code PNG image into gCode commands that the laser can execute. This involves raster scanning the image line-by-line and converting pixel intensity to laser power levels.

**User Story:** As a worker, I want to engrave QR codes on production units using the laser, so that units have permanent machine-readable identification.

**Prompt:**

```
We need to implement PNG-to-gCode conversion for engraving QR codes with a laser.

BACKGROUND:
- Production units have QR code PNGs stored in Supabase storage (from Prompt 14)
- QR codes are typically 512x512 pixels, black on white background
- Laser uses grbl protocol with S parameter for power (S0-S1000 or 0-100%)
- Feed rate controlled by F parameter (e.g., F1000 = 1000 mm/min)

REQUIREMENTS:

1. CREATE IMAGE TO GCODE SERVICE

   lib/services/image_to_gcode_service.dart:
   ```dart
   import 'dart:typed_data';
   import 'dart:ui' as ui;
   import 'package:image/image.dart' as img;

   class ImageToGCodeService {
     /// Convert PNG image to raster-scanned gCode
     Future<String> convertImageToGCode({
       required Uint8List pngData,
       required double widthInches,
       required double heightInches,
       required double startX,
       required double startY,
       required int maxPower, // 0-100
       required int feedRate, // mm/min
     }) async {
       try {
         // 1. Decode PNG
         final image = img.decodeImage(pngData);
         if (image == null) {
           throw Exception('Failed to decode image');
         }

         AppLogger.info('Converting ${image.width}x${image.height} image to gCode');

         // 2. Convert to grayscale if needed
         final grayscale = img.grayscale(image);

         // 3. Calculate DPI and step size
         final dpi = grayscale.width / widthInches;
         final stepSizeMM = 25.4 / dpi; // mm per pixel

         AppLogger.info('DPI: $dpi, Step size: ${stepSizeMM}mm');

         // 4. Generate gCode
         final gcode = StringBuffer();

         // Header
         gcode.writeln('; Generated QR Code Engraving gCode');
         gcode.writeln('; Image size: ${grayscale.width}x${grayscale.height} pixels');
         gcode.writeln('; Physical size: ${widthInches}" x ${heightInches}"');
         gcode.writeln('; Max power: $maxPower%, Feed rate: ${feedRate}mm/min');
         gcode.writeln();

         // Initialize
         gcode.writeln('G21 ; Set units to millimeters');
         gcode.writeln('G90 ; Absolute positioning');
         gcode.writeln('M3 ; Enable laser (constant power mode)');
         gcode.writeln('S0 ; Laser off initially');
         gcode.writeln('F$feedRate ; Set feed rate');
         gcode.writeln();

         // Move to start position
         final startXMM = startX * 25.4; // Convert inches to mm
         final startYMM = startY * 25.4;
         gcode.writeln('G0 X${startXMM.toStringAsFixed(3)} Y${startYMM.toStringAsFixed(3)} ; Move to start');
         gcode.writeln();

         // Raster scan
         bool leftToRight = true;

         for (int y = 0; y < grayscale.height; y++) {
           final yPos = startYMM + (y * stepSizeMM);

           // Scan direction alternates (zigzag pattern for efficiency)
           final xRange = leftToRight
             ? Iterable<int>.generate(grayscale.width, (i) => i)
             : Iterable<int>.generate(grayscale.width, (i) => grayscale.width - 1 - i);

           for (final x in xRange) {
             final pixel = grayscale.getPixel(x, y);
             final intensity = pixel.r.toInt(); // 0-255

             // Convert intensity to laser power
             // 0 (black) = max power, 255 (white) = no power
             final powerPercent = ((255 - intensity) / 255.0 * maxPower).round();

             if (powerPercent > 0) {
               final xPos = startXMM + (x * stepSizeMM);

               // Move and fire laser
               gcode.writeln('G1 X${xPos.toStringAsFixed(3)} Y${yPos.toStringAsFixed(3)} S$powerPercent');
             } else {
               // Skip white pixels (optimization)
               // Just move without firing
               final xPos = startXMM + (x * stepSizeMM);
               gcode.writeln('G0 X${xPos.toStringAsFixed(3)} Y${yPos.toStringAsFixed(3)} S0');
             }
           }

           leftToRight = !leftToRight; // Alternate direction
         }

         // Footer
         gcode.writeln();
         gcode.writeln('S0 ; Laser off');
         gcode.writeln('M5 ; Disable laser');
         gcode.writeln('G0 X${startXMM.toStringAsFixed(3)} Y${startYMM.toStringAsFixed(3)} ; Return to start');
         gcode.writeln('; End of gCode');

         final gcodeString = gcode.toString();
         final lineCount = gcodeString.split('\n').length;

         AppLogger.info('Generated ${lineCount} lines of gCode');

         return gcodeString;

       } catch (e, stackTrace) {
         AppLogger.error('Failed to convert image to gCode', e, stackTrace);
         rethrow;
       }
     }

     /// Optimize gCode by combining consecutive moves with same power
     String optimizeGCode(String gcode) {
       // Optional optimization pass
       // Combine consecutive G1 commands with same S value
       // Skip for v1, implement if performance issues
       return gcode;
     }

     /// Estimate engraving time
     Duration estimateEngravingTime({
       required int lineCount,
       required int feedRate,
       required double distanceMM,
     }) {
       // Rough estimate: lines / (feedRate / 60)
       final seconds = (distanceMM / (feedRate / 60)).round();
       return Duration(seconds: seconds);
     }
   }
   ```

2. ADD PROVIDER

   lib/providers/image_to_gcode_provider.dart:
   ```dart
   final imageToGCodeServiceProvider = Provider<ImageToGCodeService>((ref) {
     return ImageToGCodeService();
   });
   ```

3. ADD DEPENDENCIES

   pubspec.yaml:
   ```yaml
   dependencies:
     image: ^4.0.0  # Image processing library
   ```

4. CREATE QR CODE FETCHER HELPER

   lib/services/qr_code_fetch_service.dart:
   ```dart
   class QRCodeFetchService {
     final SupabaseClient _supabase;

     QRCodeFetchService(this._supabase);

     /// Fetch QR code PNG from Supabase storage
     Future<Uint8List> fetchQRCodeImage(String qrCodeUrl) async {
       try {
         // Extract bucket and path from URL
         // URL format: https://{project}.supabase.co/storage/v1/object/public/{bucket}/{path}
         final uri = Uri.parse(qrCodeUrl);
         final segments = uri.pathSegments;

         // Find 'object/public/{bucket}' pattern
         final publicIndex = segments.indexOf('public');
         if (publicIndex == -1 || publicIndex >= segments.length - 1) {
           throw Exception('Invalid storage URL format');
         }

         final bucket = segments[publicIndex + 1];
         final path = segments.sublist(publicIndex + 2).join('/');

         AppLogger.info('Fetching QR code from bucket: $bucket, path: $path');

         // Download from Supabase storage
         final bytes = await _supabase.storage.from(bucket).download(path);

         AppLogger.info('Downloaded ${bytes.length} bytes');

         return bytes;

       } catch (e, stackTrace) {
         AppLogger.error('Failed to fetch QR code image', e, stackTrace);
         rethrow;
       }
     }
   }
   ```

5. TESTING UTILITIES

   Create test file: test/services/image_to_gcode_test.dart:
   ```dart
   void main() {
     group('ImageToGCodeService', () {
       late ImageToGCodeService service;

       setUp(() {
         service = ImageToGCodeService();
       });

       test('converts simple black square to gCode', () async {
         // Create 10x10 black square PNG
         final image = img.Image(10, 10);
         img.fill(image, img.getColor(0, 0, 0)); // Black

         final pngBytes = Uint8List.fromList(img.encodePng(image));

         final gcode = await service.convertImageToGCode(
           pngData: pngBytes,
           widthInches: 1.0,
           heightInches: 1.0,
           startX: 0.0,
           startY: 0.0,
           maxPower: 100,
           feedRate: 1000,
         );

         expect(gcode, contains('G21')); // Units
         expect(gcode, contains('M3')); // Enable laser
         expect(gcode, contains('M5')); // Disable laser
         expect(gcode, contains('S100')); // Max power for black pixel
       });

       test('white pixels generate S0 commands', () async {
         // Create 10x10 white square
         final image = img.Image(10, 10);
         img.fill(image, img.getColor(255, 255, 255)); // White

         final pngBytes = Uint8List.fromList(img.encodePng(image));

         final gcode = await service.convertImageToGCode(
           pngData: pngBytes,
           widthInches: 1.0,
           heightInches: 1.0,
           startX: 0.0,
           startY: 0.0,
           maxPower: 100,
           feedRate: 1000,
         );

         expect(gcode, contains('S0')); // No power for white
       });

       test('grayscale pixels map to intermediate power levels', () async {
         // Create gradient
         final image = img.Image(10, 10);
         for (int x = 0; x < 10; x++) {
           final gray = (x * 25.5).round(); // 0 to 255
           for (int y = 0; y < 10; y++) {
             image.setPixel(x, y, img.getColor(gray, gray, gray));
           }
         }

         final pngBytes = Uint8List.fromList(img.encodePng(image));

         final gcode = await service.convertImageToGCode(
           pngData: pngBytes,
           widthInches: 1.0,
           heightInches: 1.0,
           startX: 0.0,
           startY: 0.0,
           maxPower: 100,
           feedRate: 1000,
         );

         // Should have various S values between 0 and 100
         expect(gcode, contains('S100')); // Black
         expect(gcode, contains('S0')); // White
         // Check for intermediate values
         expect(gcode, matches(RegExp(r'S[1-9][0-9]?'))); // S10-S99
       });
     });
   }
   ```

6. INTEGRATION WITH MACHINE CONTROL (Preview)

   We'll fully integrate this in Prompt 41, but add helper method:
   ```dart
   // In ImageToGCodeService

   /// Generate gCode from production unit's QR code
   Future<String> generateQREngraveGCode({
     required ProductionUnit unit,
     required ProductionStep step,
   }) async {
     // Validate step has engraving config
     if (!step.enableQrEngraving) {
       throw Exception('QR engraving not enabled for this step');
     }

     // Fetch QR code image
     final qrFetchService = QRCodeFetchService(Supabase.instance.client);
     final pngData = await qrFetchService.fetchQRCodeImage(unit.qrCodeUrl);

     // Convert to gCode
     return await convertImageToGCode(
       pngData: pngData,
       widthInches: step.qrEngraveWidth!,
       heightInches: step.qrEngraveHeight!,
       startX: step.qrEngraveStartX!,
       startY: step.qrEngraveStartY!,
       maxPower: step.qrEngravePower!,
       feedRate: step.qrEngraveFeedRate!,
     );
   }
   ```

TESTING REQUIREMENTS:
- [ ] Can decode PNG images correctly
- [ ] Converts to grayscale
- [ ] Calculates correct DPI and step size
- [ ] Generates valid gCode header
- [ ] Raster scans in zigzag pattern (efficient)
- [ ] Maps black pixels to high power (S values)
- [ ] Maps white pixels to zero power (S0)
- [ ] Maps grayscale to intermediate power levels
- [ ] Generates correct movement commands (G0/G1)
- [ ] Laser turns on/off correctly (M3/M5)
- [ ] Returns to start position at end
- [ ] Can fetch QR code from Supabase storage
- [ ] Physical dimensions calculated correctly (inches to mm)

EDGE CASES:
- Very large images (> 1000x1000) - may be slow
- Non-square images
- Images with transparency
- Invalid PNG data
- Missing QR code in storage
- Zero width/height parameters
- Negative start positions

Please implement the complete image-to-gCode conversion system.
```

**Expected Outcome:**
- PNG images convert to raster-scanned gCode
- Pixel intensity maps to laser power levels
- gCode format compatible with grbl
- Can fetch QR codes from Supabase storage
- Integration point ready for Machine Control screen
- Unit tests validate conversion logic

**Dependencies:** Prompts 36, 38 (Database, Machine communication)
**Estimated Time:** 6-8 hours
**Complexity:** Medium-High
**Testing Required:** Unit tests with synthetic images, Integration test with real QR codes

---

## Phase 6: Machine Control Screen

### Prompt 41: Machine Control Interface

**Context:** We need a dedicated full-screen interface for controlling CNC/Laser machines during production step execution. This screen allows workers to connect to machines, home/zero, run gCode files, engrave QR codes, and monitor progress.

**User Story:** As a worker, I want a dedicated machine control screen where I can safely operate CNC/Laser equipment during production steps, so that I can complete machining operations efficiently.

**Prompt:**

```
We need to create a full-screen Machine Control interface for operating CNC and Laser machines during production steps.

REQUIREMENTS:

1. CREATE MACHINE CONTROL SCREEN

   lib/screens/production/machine_control_screen.dart:
   ```dart
   class MachineControlScreen extends ConsumerStatefulWidget {
     final ProductionStep step;
     final ProductionUnit unit;

     const MachineControlScreen({
       super.key,
       required this.step,
       required this.unit,
     });
   }

   class _MachineControlScreenState extends ConsumerState<MachineControlScreen> {
     // Machine services
     late final MachineConnectionService _machine;
     late final GCodeStreamingService _streaming;

     // State
     MachineState _machineState = MachineState.disconnected;
     String? _selectedPort;
     List<String> _availablePorts = [];

     // Execution tracking
     Map<String, bool> _gcodeFileCompleted = {};
     bool _qrEngraveCompleted = false;
     StreamProgress? _currentProgress;

     @override
     void initState() {
       super.initState();

       // Get machine service based on step type
       if (widget.step.machineType == 'cnc') {
         _machine = ref.read(cncMachineServiceProvider);
         _streaming = ref.read(cncStreamingServiceProvider);
       } else if (widget.step.machineType == 'laser') {
         _machine = ref.read(laserMachineServiceProvider);
         _streaming = ref.read(laserStreamingServiceProvider);
       } else {
         throw Exception('Invalid machine type: ${widget.step.machineType}');
       }

       // Listen to machine state changes
       _machine.stateStream.listen((state) {
         if (mounted) {
           setState(() => _machineState = state);
         }
       });

       // Listen to streaming progress
       _streaming.progressStream.listen((progress) {
         if (mounted) {
           setState(() => _currentProgress = progress);
         }
       });

       // Load saved port
       _loadSavedPort();

       // Refresh available ports
       _refreshPorts();
     }

     Future<void> _loadSavedPort() async {
       final storage = ref.read(machineConfigStorageProvider);
       final port = widget.step.machineType == 'cnc'
         ? storage.getCncPort()
         : storage.getLaserPort();

       if (mounted && port != null) {
         setState(() => _selectedPort = port);
       }
     }

     void _refreshPorts() {
       setState(() {
         _availablePorts = MachineConnectionService.listAvailablePorts();
       });
     }

     @override
     Widget build(BuildContext context) {
       return Scaffold(
         appBar: AppBar(
           title: Text('Machine Control - ${widget.step.machineType?.toUpperCase()}'),
           subtitle: Text('${widget.step.name} - Unit ${widget.unit.unitId}'),
           backgroundColor: SaturdayColors.primaryDark,
           foregroundColor: Colors.white,
         ),
         body: Padding(
           padding: EdgeInsets.all(24),
           child: Column(
             crossAxisAlignment: CrossAxisAlignment.stretch,
             children: [
               // Machine status section
               _buildMachineStatusSection(),

               SizedBox(height: 24),
               Divider(),
               SizedBox(height: 24),

               // Machine controls section
               _buildMachineControlsSection(),

               SizedBox(height: 24),
               Divider(),
               SizedBox(height: 24),

               // gCode files execution section
               Expanded(
                 child: _buildGCodeFilesSection(),
               ),

               SizedBox(height: 24),

               // Progress section (when streaming)
               if (_streaming.isStreaming) ...[
                 _buildProgressSection(),
                 SizedBox(height: 24),
               ],

               // Navigation buttons
               _buildNavigationButtons(),
             ],
           ),
         ),
       );
     }
   }
   ```

2. BUILD MACHINE STATUS SECTION

   ```dart
   Widget _buildMachineStatusSection() {
     return Card(
       elevation: 4,
       child: Padding(
         padding: EdgeInsets.all(16),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Row(
               children: [
                 Icon(Icons.cable, size: 28),
                 SizedBox(width: 12),
                 Text(
                   'Machine Connection',
                   style: TextStyle(
                     fontSize: 20,
                     fontWeight: FontWeight.bold,
                   ),
                 ),
               ],
             ),

             SizedBox(height: 16),

             // Port selection
             Row(
               children: [
                 Expanded(
                   child: DropdownButtonFormField<String>(
                     value: _selectedPort,
                     decoration: InputDecoration(
                       labelText: 'Serial Port',
                       border: OutlineInputBorder(),
                       enabled: _machineState == MachineState.disconnected,
                     ),
                     items: _availablePorts.map((port) {
                       return DropdownMenuItem(
                         value: port,
                         child: Text(port),
                       );
                     }).toList(),
                     onChanged: (port) {
                       setState(() => _selectedPort = port);
                     },
                   ),
                 ),
                 SizedBox(width: 8),
                 IconButton(
                   icon: Icon(Icons.refresh),
                   onPressed: _machineState == MachineState.disconnected
                     ? _refreshPorts
                     : null,
                   tooltip: 'Refresh Ports',
                 ),
               ],
             ),

             SizedBox(height: 16),

             // Status indicator
             Row(
               children: [
                 Container(
                   width: 16,
                   height: 16,
                   decoration: BoxDecoration(
                     color: _getStatusColor(_machineState),
                     shape: BoxShape.circle,
                   ),
                 ),
                 SizedBox(width: 8),
                 Text(
                   'Status: ${_machineState.toString().split('.').last.toUpperCase()}',
                   style: TextStyle(
                     fontWeight: FontWeight.w600,
                     fontSize: 16,
                   ),
                 ),
               ],
             ),

             SizedBox(height: 16),

             // Connect/Disconnect button
             Row(
               children: [
                 if (_machineState == MachineState.disconnected)
                   ElevatedButton.icon(
                     onPressed: _selectedPort != null ? _connect : null,
                     icon: Icon(Icons.power),
                     label: Text('Connect'),
                     style: ElevatedButton.styleFrom(
                       backgroundColor: SaturdayColors.success,
                       foregroundColor: Colors.white,
                     ),
                   )
                 else
                   OutlinedButton.icon(
                     onPressed: _disconnect,
                     icon: Icon(Icons.power_off),
                     label: Text('Disconnect'),
                     style: OutlinedButton.styleFrom(
                       foregroundColor: SaturdayColors.error,
                     ),
                   ),

                 SizedBox(width: 16),

                 // Emergency stop (always visible when connected)
                 if (_machineState != MachineState.disconnected)
                   ElevatedButton.icon(
                     onPressed: _emergencyStop,
                     icon: Icon(Icons.stop_circle),
                     label: Text('EMERGENCY STOP'),
                     style: ElevatedButton.styleFrom(
                       backgroundColor: SaturdayColors.error,
                       foregroundColor: Colors.white,
                       padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                     ),
                   ),
               ],
             ),
           ],
         ),
       ),
     );
   }

   Color _getStatusColor(MachineState state) {
     switch (state) {
       case MachineState.disconnected:
         return SaturdayColors.secondaryGrey;
       case MachineState.connecting:
         return SaturdayColors.info;
       case MachineState.connected:
       case MachineState.idle:
         return SaturdayColors.success;
       case MachineState.running:
         return SaturdayColors.info;
       case MachineState.paused:
         return Colors.orange;
       case MachineState.alarm:
       case MachineState.error:
         return SaturdayColors.error;
     }
   }
   ```

3. BUILD MACHINE CONTROLS SECTION

   ```dart
   Widget _buildMachineControlsSection() {
     final canControl = _machineState == MachineState.idle ||
                        _machineState == MachineState.connected;

     return Card(
       child: Padding(
         padding: EdgeInsets.all(16),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text(
               'Machine Controls',
               style: TextStyle(
                 fontSize: 18,
                 fontWeight: FontWeight.bold,
               ),
             ),

             SizedBox(height: 16),

             Wrap(
               spacing: 12,
               runSpacing: 12,
               children: [
                 // Home button
                 OutlinedButton.icon(
                   onPressed: canControl ? _home : null,
                   icon: Icon(Icons.home),
                   label: Text('Home (\$H)'),
                 ),

                 // Set X zero
                 OutlinedButton.icon(
                   onPressed: canControl ? () => _setZero(x: true) : null,
                   icon: Icon(Icons.crop_square),
                   label: Text('Set X0'),
                 ),

                 // Set Y zero
                 OutlinedButton.icon(
                   onPressed: canControl ? () => _setZero(y: true) : null,
                   icon: Icon(Icons.crop_square),
                   label: Text('Set Y0'),
                 ),

                 // Set Z zero
                 OutlinedButton.icon(
                   onPressed: canControl ? () => _setZero(z: true) : null,
                   icon: Icon(Icons.crop_square),
                   label: Text('Set Z0'),
                 ),
               ],
             ),
           ],
         ),
       ),
     );
   }
   ```

4. BUILD GCODE FILES SECTION

   ```dart
   Widget _buildGCodeFilesSection() {
     final filesAsync = ref.watch(stepGCodeFilesProvider(widget.step.id));

     return Card(
       child: Padding(
         padding: EdgeInsets.all(16),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Text(
               'Execution Queue',
               style: TextStyle(
                 fontSize: 18,
                 fontWeight: FontWeight.bold,
               ),
             ),

             SizedBox(height: 16),

             Expanded(
               child: filesAsync.when(
                 data: (files) {
                   if (files.isEmpty && !widget.step.enableQrEngraving) {
                     return Center(
                       child: Text('No gCode files configured for this step'),
                     );
                   }

                   return ListView(
                     children: [
                       // gCode files
                       ...files.asMap().entries.map((entry) {
                         final index = entry.key;
                         final stepGCodeFile = entry.value;
                         final file = stepGCodeFile.gcodeFile!;
                         final completed = _gcodeFileCompleted[file.id] ?? false;

                         return Card(
                           margin: EdgeInsets.only(bottom: 12),
                           color: completed
                             ? SaturdayColors.success.withOpacity(0.1)
                             : null,
                           child: ListTile(
                             leading: Row(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                 Container(
                                   width: 32,
                                   height: 32,
                                   decoration: BoxDecoration(
                                     color: completed
                                       ? SaturdayColors.success
                                       : SaturdayColors.primaryDark,
                                     shape: BoxShape.circle,
                                   ),
                                   child: Center(
                                     child: completed
                                       ? Icon(Icons.check, color: Colors.white, size: 20)
                                       : Text(
                                           '${index + 1}',
                                           style: TextStyle(
                                             color: Colors.white,
                                             fontWeight: FontWeight.bold,
                                           ),
                                         ),
                                   ),
                                 ),
                               ],
                             ),
                             title: Text(file.displayName),
                             subtitle: Text(file.fileName),
                             trailing: ElevatedButton.icon(
                               onPressed: _canExecute() && !completed
                                 ? () => _runGCodeFile(file)
                                 : null,
                               icon: Icon(Icons.play_arrow),
                               label: Text(completed ? 'Completed' : 'Run'),
                               style: ElevatedButton.styleFrom(
                                 backgroundColor: completed
                                   ? SaturdayColors.secondaryGrey
                                   : SaturdayColors.primaryDark,
                               ),
                             ),
                           ),
                         );
                       }),

                       // QR Engraving (if enabled)
                       if (widget.step.enableQrEngraving) ...[
                         Card(
                           margin: EdgeInsets.only(bottom: 12),
                           color: _qrEngraveCompleted
                             ? SaturdayColors.success.withOpacity(0.1)
                             : null,
                           child: ListTile(
                             leading: Icon(
                               Icons.qr_code,
                               size: 32,
                               color: _qrEngraveCompleted
                                 ? SaturdayColors.success
                                 : SaturdayColors.primaryDark,
                             ),
                             title: Text('Engrave QR Code'),
                             subtitle: Text(
                               '${widget.step.qrEngraveWidth}" x ${widget.step.qrEngraveHeight}" '
                               'at ${widget.step.qrEngravePower}% power',
                             ),
                             trailing: ElevatedButton.icon(
                               onPressed: _canExecute() && !_qrEngraveCompleted
                                 ? _runQREngrave
                                 : null,
                               icon: Icon(Icons.flash_on),
                               label: Text(_qrEngraveCompleted ? 'Completed' : 'Run Engrave'),
                               style: ElevatedButton.styleFrom(
                                 backgroundColor: _qrEngraveCompleted
                                   ? SaturdayColors.secondaryGrey
                                   : SaturdayColors.info,
                               ),
                             ),
                           ),
                         ),
                       ],
                     ],
                   );
                 },
                 loading: () => Center(child: CircularProgressIndicator()),
                 error: (error, stack) => Center(
                   child: Text('Error loading files: $error'),
                 ),
               ),
             ),
           ],
         ),
       ),
     );
   }

   bool _canExecute() {
     return _machineState == MachineState.idle && !_streaming.isStreaming;
   }
   ```

5. BUILD PROGRESS SECTION

   ```dart
   Widget _buildProgressSection() {
     if (_currentProgress == null) return SizedBox.shrink();

     return Card(
       color: SaturdayColors.info.withOpacity(0.1),
       child: Padding(
         padding: EdgeInsets.all(16),
         child: Column(
           crossAxisAlignment: CrossAxisAlignment.start,
           children: [
             Row(
               children: [
                 Icon(Icons.timelapse, color: SaturdayColors.info),
                 SizedBox(width: 8),
                 Text(
                   'Execution Progress',
                   style: TextStyle(
                     fontSize: 16,
                     fontWeight: FontWeight.bold,
                   ),
                 ),
               ],
             ),

             SizedBox(height: 12),

             // Progress bar
             LinearProgressIndicator(
               value: _currentProgress!.percentComplete / 100,
               backgroundColor: SaturdayColors.secondaryGrey.withOpacity(0.2),
               valueColor: AlwaysStoppedAnimation(SaturdayColors.success),
               minHeight: 8,
             ),

             SizedBox(height: 8),

             Row(
               mainAxisAlignment: MainAxisAlignment.spaceBetween,
               children: [
                 Text(
                   'Line ${_currentProgress!.currentLine} of ${_currentProgress!.totalLines}',
                   style: TextStyle(fontSize: 14),
                 ),
                 Text(
                   '${_currentProgress!.percentComplete}%',
                   style: TextStyle(
                     fontSize: 16,
                     fontWeight: FontWeight.bold,
                     color: SaturdayColors.success,
                   ),
                 ),
               ],
             ),

             SizedBox(height: 8),

             Text(
               'Last: ${_currentProgress!.lastCommand}',
               style: TextStyle(
                 fontSize: 12,
                 fontFamily: 'monospace',
                 color: SaturdayColors.secondaryGrey,
               ),
               maxLines: 1,
               overflow: TextOverflow.ellipsis,
             ),

             SizedBox(height: 12),

             // Control buttons
             Row(
               children: [
                 if (_streaming.isPaused)
                   ElevatedButton.icon(
                     onPressed: _streaming.resume,
                     icon: Icon(Icons.play_arrow),
                     label: Text('Resume'),
                     style: ElevatedButton.styleFrom(
                       backgroundColor: SaturdayColors.success,
                     ),
                   )
                 else
                   ElevatedButton.icon(
                     onPressed: _streaming.pause,
                     icon: Icon(Icons.pause),
                     label: Text('Pause'),
                   ),

                 SizedBox(width: 12),

                 OutlinedButton.icon(
                   onPressed: _streaming.stop,
                   icon: Icon(Icons.stop),
                   label: Text('Stop'),
                   style: OutlinedButton.styleFrom(
                     foregroundColor: SaturdayColors.error,
                   ),
                 ),
               ],
             ),
           ],
         ),
       ),
     );
   }
   ```

6. IMPLEMENT ACTION METHODS

   ```dart
   Future<void> _connect() async {
     if (_selectedPort == null) return;

     final success = await _machine.connect(_selectedPort!);

     if (success) {
       // Save port for next time
       final storage = ref.read(machineConfigStorageProvider);
       if (widget.step.machineType == 'cnc') {
         await storage.setCncPort(_selectedPort!);
       } else {
         await storage.setLaserPort(_selectedPort!);
       }

       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Connected to machine'),
           backgroundColor: SaturdayColors.success,
         ),
       );
     } else {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Failed to connect'),
           backgroundColor: SaturdayColors.error,
         ),
       );
     }
   }

   void _disconnect() {
     _machine.disconnect();
   }

   Future<void> _emergencyStop() async {
     await _machine.emergencyStop();
     _streaming.stop();

     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text('EMERGENCY STOP ACTIVATED'),
         backgroundColor: SaturdayColors.error,
         duration: Duration(seconds: 5),
       ),
     );
   }

   Future<void> _home() async {
     final success = await _machine.home();

     if (success) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Homing complete')),
       );
     } else {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Homing failed'),
           backgroundColor: SaturdayColors.error,
         ),
       );
     }
   }

   Future<void> _setZero({bool x = false, bool y = false, bool z = false}) async {
     final success = await _machine.setZero(x: x, y: y, z: z);

     final axes = <String>[];
     if (x) axes.add('X');
     if (y) axes.add('Y');
     if (z) axes.add('Z');

     if (success) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Set ${axes.join(', ')} to zero')),
       );
     } else {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Failed to set zero'),
           backgroundColor: SaturdayColors.error,
         ),
       );
     }
   }

   Future<void> _runGCodeFile(GCodeFile file) async {
     try {
       // Fetch gCode content from GitHub
       final syncService = ref.read(gcodeSync ServiceProvider);
       final gcodeContent = await syncService.fetchGCodeContent(file);

       // Stream to machine
       final result = await _streaming.streamGCode(gcodeContent);

       if (result.success) {
         setState(() {
           _gcodeFileCompleted[file.id] = true;
           _currentProgress = null;
         });

         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('${file.displayName} completed'),
             backgroundColor: SaturdayColors.success,
           ),
         );
       } else {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Execution failed: ${result.message}'),
             backgroundColor: SaturdayColors.error,
           ),
         );
       }
     } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Error: $e'),
           backgroundColor: SaturdayColors.error,
         ),
       );
     }
   }

   Future<void> _runQREngrave() async {
     try {
       // Generate gCode from QR code image
       final imageService = ref.read(imageToGCodeServiceProvider);
       final gcodeContent = await imageService.generateQREngraveGCode(
         unit: widget.unit,
         step: widget.step,
       );

       // Stream to machine
       final result = await _streaming.streamGCode(gcodeContent);

       if (result.success) {
         setState(() {
           _qrEngraveCompleted = true;
           _currentProgress = null;
         });

         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('QR code engraving completed'),
             backgroundColor: SaturdayColors.success,
           ),
         );
       } else {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: Text('Engraving failed: ${result.message}'),
             backgroundColor: SaturdayColors.error,
           ),
         );
       }
     } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text('Error: $e'),
           backgroundColor: SaturdayColors.error,
         ),
       );
     }
   }
   ```

7. BUILD NAVIGATION BUTTONS

   ```dart
   Widget _buildNavigationButtons() {
     return Row(
       children: [
         Expanded(
           child: OutlinedButton(
             onPressed: () => Navigator.pop(context),
             child: Text('Back to Unit'),
           ),
         ),
       ],
     );
   }
   ```

8. INTEGRATE WITH STEP COMPLETION

   Update lib/screens/production/complete_step_screen.dart:

   Add button to open Machine Control (for machine steps):
   ```dart
   if (widget.step.requiresMachine) ...[
     SizedBox(height: 16),
     OutlinedButton.icon(
       onPressed: () => _openMachineControl(context),
       icon: Icon(Icons.precision_manufacturing),
       label: Text('Open Machine Control'),
       style: OutlinedButton.styleFrom(
         foregroundColor: SaturdayColors.info,
       ),
     ),
   ],
   ```

   Implement navigation:
   ```dart
   void _openMachineControl(BuildContext context) {
     Navigator.push(
       context,
       MaterialPageRoute(
         builder: (context) => MachineControlScreen(
           step: widget.step,
           unit: widget.unit,
         ),
       ),
     );
   }
   ```

TESTING REQUIREMENTS:
- [ ] Machine Control screen opens for CNC/Laser steps
- [ ] Can connect/disconnect from machine
- [ ] Serial port selection works
- [ ] Machine status updates in real-time
- [ ] Home button works
- [ ] Set zero buttons work (X, Y, Z)
- [ ] Emergency stop works immediately
- [ ] gCode files display in order
- [ ] Can run individual gCode files
- [ ] Progress bar updates during streaming
- [ ] Pause/Resume works during execution
- [ ] Stop cancels execution
- [ ] QR engraving shows for laser steps
- [ ] Can run QR engraving
- [ ] Completed items marked with checkmark
- [ ] Error handling for connection failures
- [ ] Error handling for execution failures
- [ ] Back button returns to unit detail

Please implement the complete Machine Control screen.
```

**Expected Outcome:**
- Full-screen machine control interface works
- Can connect to and control CNC/Laser machines
- gCode files execute sequentially
- QR code engraving works for laser steps
- Real-time progress tracking during execution
- Emergency stop and safety controls work
- Integrates with step completion workflow
- Worker-friendly UI for production floor

**Dependencies:** Prompts 36-40 (All previous phases)
**Estimated Time:** 10-12 hours
**Complexity:** High
**Testing Required:** Extensive manual testing with real machines, Safety testing

---

## Appendix: Testing Guidelines

### Unit Testing
- Test models serialize/deserialize correctly
- Test repository CRUD operations
- Test image-to-gCode conversion logic
- Test gCode parsing and validation

### Integration Testing
- Test GitHub API integration
- Test serial communication with machines
- Test gCode streaming end-to-end
- Test database migrations

### Manual Testing
- Test complete workflow: configure step → execute → complete
- Test with actual CNC and Laser machines
- Test error scenarios (disconnection, invalid gCode, etc.)
- Test safety features (emergency stop, pause)

### Safety Testing
- Verify emergency stop works immediately
- Verify machine doesn't move unexpectedly
- Verify laser turns off when connection lost
- Test pause/resume doesn't skip commands

---

## Future Enhancements

### Phase 7+ (Potential)
- Add more step types (3D Printing, Assembly with instructions, etc.)
- Machine job queue (schedule multiple units)
- gCode simulation/preview before running
- Video instructions embedded in steps
- Automatic tool change detection
- Machine maintenance tracking
- Production analytics per machine type
- Multi-machine support (multiple CNCs/Lasers)
- Custom gCode snippets library
- AR/VR assembly instructions

---

**Document Version**: 1.0
**Created**: 2025-01-12
**Author**: Saturday! Development Team
