# File Library Implementation Plan

## Overview

Refactor file management from GitHub-synced gcode files to a unified file library system backed by Supabase Storage. This provides a simpler, more maintainable approach where users can upload and manage files directly in the app.

## Goals

- ✅ Create a generic file library system that can support multiple file types
- ✅ Simplify production step file attachments (consolidate single file + gcode files into one system)
- ✅ Remove complexity of GitHub repository syncing
- ✅ Enable users to manage files directly in the app

## Design Decisions

### File Storage
- **Structure**: Flat file structure in Supabase Storage
- **Location**: Single `files` bucket
- **Access**: Private, requires authentication
- **Size Limit**: 50MB per file
- **Naming**: Unique file names enforced

### File Associations
- **Unified Approach**: One `step_files` junction table for ALL file types (replaces separate single file + gcode many-to-many)
- **Machine Control**: Filters attached files by extension (.gcode, .nc) at runtime
- **Ordering**: Files have `execution_order` for sequencing (important for gcode)

### File Metadata
- File name (user editable, unique)
- File description (user editable)
- File type/MIME type
- File size
- Created at timestamp
- Uploaded by (user name only, no FK - preserves name even if user deleted)

### UI/UX
- **New "Files" screen**: Top-level navigation item for file library management
- **File picker**: Multi-file selection in production step configuration
- **No categorization**: All files available to all step types (user decides what's appropriate)

### Migration Strategy
- **Option C - Deprecate**: No automatic migration
- **Rationale**: Early adoption phase, not many production steps yet
- **Approach**: Show notice in UI, users manually re-configure steps

---

## Implementation Phases

### Phase 1: Database Schema ✅

**Files Table:**
```sql
CREATE TABLE public.files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  storage_path TEXT NOT NULL UNIQUE,
  file_name TEXT NOT NULL UNIQUE,
  description TEXT,
  mime_type TEXT NOT NULL,
  file_size_bytes INTEGER NOT NULL,
  uploaded_by_name TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT file_size_limit CHECK (file_size_bytes > 0 AND file_size_bytes <= 52428800)
);
```

**Step Files Junction Table:**
```sql
CREATE TABLE public.step_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  step_id UUID NOT NULL REFERENCES public.production_steps(id) ON DELETE CASCADE,
  file_id UUID NOT NULL REFERENCES public.files(id) ON DELETE CASCADE,
  execution_order INTEGER NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
  CONSTRAINT unique_step_file UNIQUE(step_id, file_id),
  CONSTRAINT unique_step_execution_order UNIQUE(step_id, execution_order),
  CONSTRAINT positive_execution_order CHECK (execution_order > 0)
);
```

**Deprecate Old Columns:**
- Mark `production_steps.file_url`, `file_name`, `file_type` as deprecated (don't drop for backward compat)
- Keep `gcode_files` and `step_gcode_files` tables (deprecated but don't break existing data)

**Tasks:**
- [ ] Create migration file `013_file_library.sql`
- [ ] Add comments to deprecated fields/tables
- [ ] Create indexes on new tables
- [ ] Set up RLS policies

---

### Phase 2: Supabase Storage Setup ✅

**Storage Bucket Configuration:**
- Bucket name: `files`
- Public: No (requires authentication)
- File size limit: 50MB (52428800 bytes)
- Allowed MIME types: All (no restriction)

**RLS Policies:**
- Authenticated users can: SELECT, INSERT, UPDATE, DELETE
- Pattern: `{uuid}.{extension}` for storage paths

**Tasks:**
- [ ] Create storage bucket via Supabase dashboard or SQL
- [ ] Configure RLS policies for authenticated access
- [ ] Test upload/download with authenticated user

---

### Phase 3: Models & Repositories ✅

**Dart Models:**

1. **AppFile** (`lib/models/app_file.dart`)
   ```dart
   class AppFile extends Equatable {
     final String id;
     final String storagePath;
     final String fileName;
     final String? description;
     final String mimeType;
     final int fileSizeBytes;
     final String uploadedByName;
     final DateTime createdAt;
     final DateTime updatedAt;

     // Helper methods
     String get fileSizeMB;
     String get fileExtension;
     bool get isGCodeFile; // checks .gcode, .nc extensions
   }
   ```

2. **StepFile** (`lib/models/step_file.dart`)
   ```dart
   class StepFile extends Equatable {
     final String id;
     final String stepId;
     final String fileId;
     final int executionOrder;
     final DateTime createdAt;
     final AppFile? file; // Optional loaded file object
   }
   ```

3. **Update ProductionStep** (`lib/models/production_step.dart`)
   - Remove/deprecate: `fileUrl`, `fileName`, `fileType` fields
   - Add comment noting to use `step_files` relationship instead

**Repositories:**

1. **FileRepository** (`lib/repositories/file_repository.dart`)
   ```dart
   class FileRepository {
     Future<List<AppFile>> getAllFiles();
     Future<AppFile?> getFileById(String id);
     Future<AppFile> createFile(AppFile file);
     Future<AppFile> updateFile(AppFile file);
     Future<void> deleteFile(String id);
     Future<AppFile?> getFileByName(String fileName);
     Future<List<AppFile>> searchFiles(String query);
   }
   ```

2. **FileStorageService** (`lib/services/file_storage_service.dart`)
   ```dart
   class FileStorageService {
     Future<String> uploadFile(Uint8List fileBytes, String fileName, String mimeType);
     Future<Uint8List> downloadFile(String storagePath);
     Future<void> deleteFile(String storagePath);
     Future<String> getPublicUrl(String storagePath); // For authenticated download
   }
   ```

3. **StepFileRepository** (`lib/repositories/step_file_repository.dart`)
   ```dart
   class StepFileRepository {
     Future<List<StepFile>> getFilesForStep(String stepId);
     Future<List<StepFile>> getFilesForStepWithDetails(String stepId);
     Future<void> addFileToStep(String stepId, String fileId, int order);
     Future<void> removeFileFromStep(String stepFileId);
     Future<void> updateFilesForStep(String stepId, List<String> fileIds);
     Future<void> updateExecutionOrder(String stepFileId, int newOrder);
   }
   ```

**Tasks:**
- [ ] Create models with fromJson/toJson
- [ ] Create repositories
- [ ] Create file storage service
- [ ] Update ProductionStep model
- [ ] Write unit tests for models

---

### Phase 4: Providers ✅

**Riverpod Providers:**

1. **File Providers** (`lib/providers/file_provider.dart`)
   ```dart
   final fileRepositoryProvider = Provider<FileRepository>(...);
   final fileStorageServiceProvider = Provider<FileStorageService>(...);

   final allFilesProvider = FutureProvider<List<AppFile>>(...);
   final fileByIdProvider = FutureProvider.family<AppFile?, String>(...);

   // Search provider for file picker
   final fileSearchProvider = FutureProvider.family<List<AppFile>, String>(...);
   ```

2. **Step File Providers** (`lib/providers/step_file_provider.dart`)
   ```dart
   final stepFileRepositoryProvider = Provider<StepFileRepository>(...);

   final stepFilesProvider = FutureProvider.family<List<StepFile>, String>(...);
   ```

**Tasks:**
- [ ] Create provider files
- [ ] Integrate with existing provider structure
- [ ] Test provider refresh/invalidation

---

### Phase 5: UI - Files Library Screen ✅

**New Screen:** `lib/screens/files/files_screen.dart`

**Features:**
- List all files with search/filter
- Display file metadata (name, description, type, size, uploaded by, date)
- Upload new file button (opens dialog)
- Edit file metadata (name, description)
- Delete file (with confirmation)
- Download file option

**Components:**
- `lib/screens/files/files_screen.dart` - Main screen
- `lib/widgets/files/file_upload_dialog.dart` - Upload dialog
- `lib/widgets/files/file_list_item.dart` - List item widget
- `lib/widgets/files/file_edit_dialog.dart` - Edit metadata dialog

**Validation:**
- File name uniqueness check
- 50MB size limit
- Non-empty file name

**Tasks:**
- [ ] Create files screen
- [ ] Create upload dialog with file picker
- [ ] Create edit dialog
- [ ] Add to main navigation
- [ ] Implement search/filter
- [ ] Add delete confirmation dialog

---

### Phase 6: UI - Production Step File Picker ✅

**Update:** `lib/widgets/products/step_type_config.dart`

**Features:**
- Multi-file selection from file library
- Display attached files in reorderable list
- Show file metadata (name, size, type)
- Drag to reorder files (for gcode execution order)
- Remove file from step
- Add file button (opens file picker dialog)

**New Component:** `lib/widgets/files/file_picker_dialog.dart`
- Browse file library
- Search files
- Select multiple files
- Show already-attached files (disabled/grayed)

**Tasks:**
- [ ] Create file picker dialog
- [ ] Update step_type_config to use new file system
- [ ] Add reorderable file list
- [ ] Remove old file upload UI
- [ ] Show deprecation notice for legacy files

---

### Phase 7: Integration - Machine Control ✅

**Update:** `lib/screens/production/machine_control_screen.dart`

**Changes:**
- Fetch files from `step_files` relationship
- Filter for gcode files (`.gcode`, `.nc` extensions)
- Download file content from Supabase Storage
- Use `execution_order` for sequencing

**Fallback:**
- If no files in new system, check legacy `step_gcode_files`
- Show notice: "Using legacy gcode files. Please update step configuration."

**Tasks:**
- [ ] Update machine control to use new file system
- [ ] Add gcode file filtering logic
- [ ] Implement file content fetching
- [ ] Add legacy system fallback
- [ ] Test with multiple gcode files

---

### Phase 8: Cleanup & Documentation ✅

**Remove:**
- `lib/services/gcode_sync_service.dart` ❌
- `lib/widgets/settings/gcode_sync_card.dart` ❌
- Gcode sync UI from settings screen ❌
- `lib/providers/gcode_file_provider.dart` (old gcode-specific provider) ❌

**Keep:**
- `lib/services/github_service.dart` ✅ (may use in future)
- `lib/repositories/gcode_file_repository.dart` ✅ (for legacy data access)
- Database tables: `gcode_files`, `step_gcode_files` ✅ (deprecated but not dropped)

**Update Documentation:**
- Add deprecation note to `prompt_plan_production_steps.md` for Prompt 36 GitHub sync portion
- Note that step types (general, cnc_milling, laser_cutting) are still used
- Update any references to file attachment system

**Migration Notice:**
- Add banner/notice in production step config if:
  - Step has `file_url` (old single file)
  - Step has `step_gcode_files` (old gcode system)
- Message: "This step uses legacy file attachments. Please re-attach files using the Files library."

**Tasks:**
- [ ] Remove deprecated services and UI
- [ ] Update documentation
- [ ] Add migration notices in UI
- [ ] Test that legacy data doesn't cause errors
- [ ] Update README if needed

---

## Testing Checklist

### Files Library
- [ ] Upload file (< 50MB)
- [ ] Upload file validation (> 50MB should fail)
- [ ] Upload duplicate file name (should fail)
- [ ] Edit file metadata (name, description)
- [ ] Edit to duplicate name (should fail)
- [ ] Delete file
- [ ] Delete file that's attached to step (should cascade)
- [ ] Search/filter files
- [ ] Download file

### Production Step Files
- [ ] Attach single file to step
- [ ] Attach multiple files to step
- [ ] Reorder files
- [ ] Remove file from step
- [ ] File picker shows all files
- [ ] File picker disables already-attached files
- [ ] Save step with attached files

### Machine Control
- [ ] Load step with gcode files
- [ ] Only gcode files shown in machine control
- [ ] Files execute in correct order
- [ ] File content loads from storage
- [ ] Non-gcode files ignored in machine control

### Legacy Compatibility
- [ ] Steps with old file_url still display (read-only)
- [ ] Steps with old step_gcode_files still work in machine control
- [ ] Migration notices appear correctly

### Permissions
- [ ] Authenticated users can access files
- [ ] Unauthenticated users cannot access files
- [ ] File storage is private

---

## Database Migration Notes

### Safe Rollback Strategy
If needed, we can rollback by:
1. Not dropping old columns/tables (just deprecate)
2. Keeping legacy data accessible
3. Adding fallback logic in code

### Future Cleanup
After confirming new system works and all steps migrated:
1. Drop `production_steps.file_url`, `file_name`, `file_type` columns
2. Drop `gcode_files` table
3. Drop `step_gcode_files` table
4. Remove legacy fallback code

---

## Questions Resolved

1. ✅ **File execution order**: Yes, users can reorder files (important for gcode sequencing)
2. ✅ **File display**: One unified list (simpler, no categorization)
3. ✅ **Migration notice**: Yes, show banner if legacy data detected

---

## Timeline Estimate

- Phase 1 (Database): 1 hour
- Phase 2 (Storage): 30 min
- Phase 3 (Models/Repos): 2 hours
- Phase 4 (Providers): 1 hour
- Phase 5 (Files Screen): 3 hours
- Phase 6 (File Picker): 2 hours
- Phase 7 (Machine Control): 1.5 hours
- Phase 8 (Cleanup): 1 hour

**Total: ~12 hours**

---

## Success Criteria

- ✅ Users can upload, edit, delete files in library
- ✅ Users can attach multiple files to production steps
- ✅ Machine control executes gcode files in order
- ✅ Legacy steps continue to work (no breaking changes)
- ✅ File storage is secure (auth required)
- ✅ GitHub sync complexity removed
- ✅ System is generic enough for future file type expansion
