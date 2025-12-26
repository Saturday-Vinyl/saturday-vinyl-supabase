import 'package:saturday_app/models/app_file.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing files in the unified file library
class FileRepository {
  final _supabase = SupabaseService.instance.client;

  /// Get all files
  Future<List<AppFile>> getAllFiles() async {
    try {
      AppLogger.info('Fetching all files');

      final response = await _supabase
          .from('files')
          .select()
          .order('created_at', ascending: false);

      final files = (response as List)
          .map((json) => AppFile.fromJson(json))
          .toList();

      AppLogger.info('Found ${files.length} files');
      return files;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching files', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single file by ID
  Future<AppFile?> getFileById(String id) async {
    try {
      AppLogger.info('Fetching file: $id');

      final response = await _supabase
          .from('files')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('File not found: $id');
        return null;
      }

      return AppFile.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching file', error, stackTrace);
      rethrow;
    }
  }

  /// Get a file by name (for uniqueness validation)
  Future<AppFile?> getFileByName(String fileName) async {
    try {
      AppLogger.debug('Checking for file with name: $fileName');

      final response = await _supabase
          .from('files')
          .select()
          .eq('file_name', fileName)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return AppFile.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching file by name', error, stackTrace);
      rethrow;
    }
  }

  /// Search files by name or description
  Future<List<AppFile>> searchFiles(String query) async {
    try {
      AppLogger.info('Searching files for: $query');

      final response = await _supabase
          .from('files')
          .select()
          .or('file_name.ilike.%$query%,description.ilike.%$query%')
          .order('created_at', ascending: false);

      final files = (response as List)
          .map((json) => AppFile.fromJson(json))
          .toList();

      AppLogger.info('Found ${files.length} files matching query');
      return files;
    } catch (error, stackTrace) {
      AppLogger.error('Error searching files', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new file record
  Future<AppFile> createFile(AppFile file) async {
    try {
      AppLogger.info('Creating file: ${file.fileName}');

      final response = await _supabase
          .from('files')
          .insert(file.toJson(forInsert: true))
          .select()
          .single();

      final createdFile = AppFile.fromJson(response);
      AppLogger.info('Created file: ${createdFile.id}');
      return createdFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error creating file', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing file (metadata only, not the actual file content)
  Future<AppFile> updateFile(AppFile file) async {
    try {
      AppLogger.info('Updating file: ${file.id}');

      final response = await _supabase
          .from('files')
          .update(file.toJson())
          .eq('id', file.id)
          .select()
          .single();

      final updatedFile = AppFile.fromJson(response);
      AppLogger.info('Updated file: ${updatedFile.id}');
      return updatedFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating file', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a file record
  /// Note: This should also delete the file from storage (handled by FileStorageService)
  Future<void> deleteFile(String id) async {
    try {
      AppLogger.info('Deleting file: $id');

      await _supabase
          .from('files')
          .delete()
          .eq('id', id);

      AppLogger.info('Deleted file: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting file', error, stackTrace);
      rethrow;
    }
  }

  /// Check if a file name is available (not already used)
  Future<bool> isFileNameAvailable(String fileName, {String? excludeFileId}) async {
    try {
      var query = _supabase
          .from('files')
          .select('id')
          .eq('file_name', fileName);

      // If excluding a specific file (for updates), filter it out
      if (excludeFileId != null) {
        query = query.neq('id', excludeFileId);
      }

      final response = await query.maybeSingle();

      return response == null; // Available if no existing file found
    } catch (error, stackTrace) {
      AppLogger.error('Error checking file name availability', error, stackTrace);
      rethrow;
    }
  }
}
