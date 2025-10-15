import 'package:saturday_app/models/gcode_file.dart';
import 'package:saturday_app/models/step_gcode_file.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing gCode files and step-gCode associations
class GCodeFileRepository {
  final _supabase = SupabaseService.instance.client;

  /// Get all gCode files
  Future<List<GCodeFile>> getAllGCodeFiles() async {
    try {
      AppLogger.info('Fetching all gCode files');

      final response = await _supabase
          .from('gcode_files')
          .select()
          .order('machine_type')
          .order('file_name');

      final files = (response as List)
          .map((json) => GCodeFile.fromJson(json))
          .toList();

      AppLogger.info('Found ${files.length} gCode files');
      return files;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching gCode files', error, stackTrace);
      rethrow;
    }
  }

  /// Get gCode files by machine type ('cnc' or 'laser')
  Future<List<GCodeFile>> getGCodeFilesByMachineType(String machineType) async {
    try {
      AppLogger.info('Fetching gCode files for machine type: $machineType');

      final response = await _supabase
          .from('gcode_files')
          .select()
          .eq('machine_type', machineType)
          .order('file_name');

      final files = (response as List)
          .map((json) => GCodeFile.fromJson(json))
          .toList();

      AppLogger.info('Found ${files.length} gCode files for $machineType');
      return files;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching gCode files by machine type', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single gCode file by ID
  Future<GCodeFile?> getGCodeFileById(String id) async {
    try {
      AppLogger.info('Fetching gCode file: $id');

      final response = await _supabase
          .from('gcode_files')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('gCode file not found: $id');
        return null;
      }

      return GCodeFile.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching gCode file', error, stackTrace);
      rethrow;
    }
  }

  /// Get a gCode file by GitHub path
  Future<GCodeFile?> getGCodeFileByPath(String githubPath) async {
    try {
      AppLogger.info('Fetching gCode file by path: $githubPath');

      final response = await _supabase
          .from('gcode_files')
          .select()
          .eq('github_path', githubPath)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('gCode file not found at path: $githubPath');
        return null;
      }

      return GCodeFile.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching gCode file by path', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new gCode file
  Future<GCodeFile> createGCodeFile(GCodeFile file) async {
    try {
      AppLogger.info('Creating gCode file: ${file.fileName}');

      final response = await _supabase
          .from('gcode_files')
          .insert(file.toJson())
          .select()
          .single();

      final createdFile = GCodeFile.fromJson(response);
      AppLogger.info('Created gCode file: ${createdFile.id}');
      return createdFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error creating gCode file', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing gCode file
  Future<GCodeFile> updateGCodeFile(GCodeFile file) async {
    try {
      AppLogger.info('Updating gCode file: ${file.id}');

      final response = await _supabase
          .from('gcode_files')
          .update(file.toJson())
          .eq('id', file.id)
          .select()
          .single();

      final updatedFile = GCodeFile.fromJson(response);
      AppLogger.info('Updated gCode file: ${updatedFile.id}');
      return updatedFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating gCode file', error, stackTrace);
      rethrow;
    }
  }

  /// Upsert a gCode file (insert or update based on github_path)
  Future<GCodeFile> upsertGCodeFile(GCodeFile file) async {
    try {
      AppLogger.info('Upserting gCode file: ${file.fileName}');

      // Convert to JSON and remove empty id field (let database generate it)
      final json = file.toJson();
      if (json['id'] == null || json['id'] == '') {
        json.remove('id');
      }

      final response = await _supabase
          .from('gcode_files')
          .upsert(
            json,
            onConflict: 'github_path',
          )
          .select()
          .single();

      final upsertedFile = GCodeFile.fromJson(response);
      AppLogger.info('Upserted gCode file: ${upsertedFile.id}');
      return upsertedFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error upserting gCode file', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a gCode file
  Future<void> deleteGCodeFile(String id) async {
    try {
      AppLogger.info('Deleting gCode file: $id');

      await _supabase
          .from('gcode_files')
          .delete()
          .eq('id', id);

      AppLogger.info('Deleted gCode file: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting gCode file', error, stackTrace);
      rethrow;
    }
  }

  /// Batch upsert gCode files (for syncing from GitHub)
  Future<List<GCodeFile>> batchUpsertGCodeFiles(List<GCodeFile> files) async {
    try {
      AppLogger.info('Batch upserting ${files.length} gCode files');

      // Convert to JSON and remove empty id fields
      final jsonList = files.map((f) {
        final json = f.toJson();
        if (json['id'] == null || json['id'] == '') {
          json.remove('id');
        }
        return json;
      }).toList();

      final response = await _supabase
          .from('gcode_files')
          .upsert(
            jsonList,
            onConflict: 'github_path',
          )
          .select();

      final upsertedFiles = (response as List)
          .map((json) => GCodeFile.fromJson(json))
          .toList();

      AppLogger.info('Upserted ${upsertedFiles.length} gCode files');
      return upsertedFiles;
    } catch (error, stackTrace) {
      AppLogger.error('Error batch upserting gCode files', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // Step-gCode File Associations
  // ============================================================================

  /// Get all gCode files for a production step (ordered by execution_order)
  Future<List<StepGCodeFile>> getGCodeFilesForStep(String stepId) async {
    try {
      AppLogger.info('Fetching gCode files for step: $stepId');

      final response = await _supabase
          .from('step_gcode_files')
          .select('*, gcode_files(*)')
          .eq('step_id', stepId)
          .order('execution_order');

      final stepGcodeFiles = (response as List)
          .map((json) => StepGCodeFile.fromJson(json))
          .toList();

      AppLogger.info('Found ${stepGcodeFiles.length} gCode files for step $stepId');
      return stepGcodeFiles;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching gCode files for step', error, stackTrace);
      rethrow;
    }
  }

  /// Add a gCode file to a production step
  Future<StepGCodeFile> addGCodeFileToStep({
    required String stepId,
    required String gcodeFileId,
    required int executionOrder,
  }) async {
    try {
      AppLogger.info('Adding gCode file $gcodeFileId to step $stepId (order: $executionOrder)');

      final response = await _supabase
          .from('step_gcode_files')
          .insert({
            'step_id': stepId,
            'gcode_file_id': gcodeFileId,
            'execution_order': executionOrder,
          })
          .select('*, gcode_files(*)')
          .single();

      final stepGcodeFile = StepGCodeFile.fromJson(response);
      AppLogger.info('Added gCode file to step: ${stepGcodeFile.id}');
      return stepGcodeFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error adding gCode file to step', error, stackTrace);
      rethrow;
    }
  }

  /// Remove a gCode file from a production step
  Future<void> removeGCodeFileFromStep(String stepGcodeFileId) async {
    try {
      AppLogger.info('Removing step-gCode association: $stepGcodeFileId');

      await _supabase
          .from('step_gcode_files')
          .delete()
          .eq('id', stepGcodeFileId);

      AppLogger.info('Removed step-gCode association: $stepGcodeFileId');
    } catch (error, stackTrace) {
      AppLogger.error('Error removing gCode file from step', error, stackTrace);
      rethrow;
    }
  }

  /// Remove all gCode files from a production step
  Future<void> removeAllGCodeFilesFromStep(String stepId) async {
    try {
      AppLogger.info('Removing all gCode files from step: $stepId');

      await _supabase
          .from('step_gcode_files')
          .delete()
          .eq('step_id', stepId);

      AppLogger.info('Removed all gCode files from step: $stepId');
    } catch (error, stackTrace) {
      AppLogger.error('Error removing all gCode files from step', error, stackTrace);
      rethrow;
    }
  }

  /// Update execution order for a step-gCode association
  Future<StepGCodeFile> updateExecutionOrder({
    required String stepGcodeFileId,
    required int newExecutionOrder,
  }) async {
    try {
      AppLogger.info('Updating execution order for $stepGcodeFileId to $newExecutionOrder');

      final response = await _supabase
          .from('step_gcode_files')
          .update({'execution_order': newExecutionOrder})
          .eq('id', stepGcodeFileId)
          .select('*, gcode_files(*)')
          .single();

      final stepGcodeFile = StepGCodeFile.fromJson(response);
      AppLogger.info('Updated execution order: ${stepGcodeFile.id}');
      return stepGcodeFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating execution order', error, stackTrace);
      rethrow;
    }
  }

  /// Batch update gCode files for a step (replaces all existing associations)
  Future<List<StepGCodeFile>> updateGCodeFilesForStep({
    required String stepId,
    required List<String> gcodeFileIds,
  }) async {
    try {
      AppLogger.info('Updating gCode files for step: $stepId');

      // Delete all existing associations
      await removeAllGCodeFilesFromStep(stepId);

      // Create new associations if any
      if (gcodeFileIds.isEmpty) {
        return [];
      }

      final associationsToInsert = gcodeFileIds.asMap().entries.map((entry) {
        return {
          'step_id': stepId,
          'gcode_file_id': entry.value,
          'execution_order': entry.key + 1,
        };
      }).toList();

      final response = await _supabase
          .from('step_gcode_files')
          .insert(associationsToInsert)
          .select('*, gcode_files(*)');

      final stepGcodeFiles = (response as List)
          .map((json) => StepGCodeFile.fromJson(json))
          .toList();

      AppLogger.info('Updated ${stepGcodeFiles.length} gCode files for step');
      return stepGcodeFiles;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating gCode files for step', error, stackTrace);
      rethrow;
    }
  }
}
