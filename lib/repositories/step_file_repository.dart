import 'package:saturday_app/models/step_file.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing step-file associations (junction table)
class StepFileRepository {
  final _supabase = SupabaseService.instance.client;

  /// Get all files for a production step (ordered by execution_order)
  Future<List<StepFile>> getFilesForStep(String stepId) async {
    try {
      AppLogger.info('Fetching files for step: $stepId');

      final response = await _supabase
          .from('step_files')
          .select('*, files(*)')
          .eq('step_id', stepId)
          .order('execution_order');

      final stepFiles = (response as List)
          .map((json) => StepFile.fromJson(json))
          .toList();

      AppLogger.info('Found ${stepFiles.length} files for step $stepId');
      return stepFiles;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching files for step', error, stackTrace);
      rethrow;
    }
  }

  /// Add a file to a production step
  Future<StepFile> addFileToStep({
    required String stepId,
    required String fileId,
    required int executionOrder,
  }) async {
    try {
      AppLogger.info(
        'Adding file $fileId to step $stepId (order: $executionOrder)',
      );

      final response = await _supabase
          .from('step_files')
          .insert({
            'step_id': stepId,
            'file_id': fileId,
            'execution_order': executionOrder,
          })
          .select('*, files(*)')
          .single();

      final stepFile = StepFile.fromJson(response);
      AppLogger.info('Added file to step: ${stepFile.id}');
      return stepFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error adding file to step', error, stackTrace);
      rethrow;
    }
  }

  /// Remove a file from a production step
  Future<void> removeFileFromStep(String stepFileId) async {
    try {
      AppLogger.info('Removing step-file association: $stepFileId');

      await _supabase
          .from('step_files')
          .delete()
          .eq('id', stepFileId);

      AppLogger.info('Removed step-file association: $stepFileId');
    } catch (error, stackTrace) {
      AppLogger.error('Error removing file from step', error, stackTrace);
      rethrow;
    }
  }

  /// Remove all files from a production step
  Future<void> removeAllFilesFromStep(String stepId) async {
    try {
      AppLogger.info('Removing all files from step: $stepId');

      await _supabase
          .from('step_files')
          .delete()
          .eq('step_id', stepId);

      AppLogger.info('Removed all files from step: $stepId');
    } catch (error, stackTrace) {
      AppLogger.error('Error removing all files from step', error, stackTrace);
      rethrow;
    }
  }

  /// Update execution order for a step-file association
  Future<StepFile> updateExecutionOrder({
    required String stepFileId,
    required int newExecutionOrder,
  }) async {
    try {
      AppLogger.info(
        'Updating execution order for $stepFileId to $newExecutionOrder',
      );

      final response = await _supabase
          .from('step_files')
          .update({'execution_order': newExecutionOrder})
          .eq('id', stepFileId)
          .select('*, files(*)')
          .single();

      final stepFile = StepFile.fromJson(response);
      AppLogger.info('Updated execution order: ${stepFile.id}');
      return stepFile;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating execution order', error, stackTrace);
      rethrow;
    }
  }

  /// Batch update files for a step (replaces all existing associations)
  /// fileIds should be in the desired execution order
  Future<List<StepFile>> updateFilesForStep({
    required String stepId,
    required List<String> fileIds,
  }) async {
    try {
      AppLogger.info('Updating files for step: $stepId');

      // Delete all existing associations
      await removeAllFilesFromStep(stepId);

      // Create new associations if any
      if (fileIds.isEmpty) {
        return [];
      }

      final associationsToInsert = fileIds.asMap().entries.map((entry) {
        return {
          'step_id': stepId,
          'file_id': entry.value,
          'execution_order': entry.key + 1, // 1-based indexing
        };
      }).toList();

      final response = await _supabase
          .from('step_files')
          .insert(associationsToInsert)
          .select('*, files(*)');

      final stepFiles = (response as List)
          .map((json) => StepFile.fromJson(json))
          .toList();

      AppLogger.info('Updated ${stepFiles.length} files for step');
      return stepFiles;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating files for step', error, stackTrace);
      rethrow;
    }
  }

  /// Get all steps that use a specific file
  /// Useful for showing where a file is used before deletion
  Future<List<StepFile>> getStepsUsingFile(String fileId) async {
    try {
      AppLogger.info('Finding steps using file: $fileId');

      final response = await _supabase
          .from('step_files')
          .select('*, files(*)')
          .eq('file_id', fileId);

      final stepFiles = (response as List)
          .map((json) => StepFile.fromJson(json))
          .toList();

      AppLogger.info('Found ${stepFiles.length} steps using file');
      return stepFiles;
    } catch (error, stackTrace) {
      AppLogger.error('Error finding steps using file', error, stackTrace);
      rethrow;
    }
  }
}
