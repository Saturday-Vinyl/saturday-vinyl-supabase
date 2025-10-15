import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/gcode_file.dart';
import 'package:saturday_app/models/step_gcode_file.dart';
import 'package:saturday_app/repositories/gcode_file_repository.dart';

/// Provider for gCode file repository
final gcodeFileRepositoryProvider = Provider<GCodeFileRepository>((ref) {
  return GCodeFileRepository();
});

/// Provider for fetching all gCode files
final allGCodeFilesProvider = FutureProvider<List<GCodeFile>>((ref) async {
  final repository = ref.read(gcodeFileRepositoryProvider);
  return repository.getAllGCodeFiles();
});

/// Provider for fetching gCode files by machine type
final gcodeFilesByMachineTypeProvider = FutureProvider.family<List<GCodeFile>, String>(
  (ref, machineType) async {
    final repository = ref.read(gcodeFileRepositoryProvider);
    return repository.getGCodeFilesByMachineType(machineType);
  },
);

/// Provider for fetching gCode files for a specific step
final stepGCodeFilesProvider = FutureProvider.family<List<StepGCodeFile>, String>(
  (ref, stepId) async {
    final repository = ref.read(gcodeFileRepositoryProvider);
    return repository.getGCodeFilesForStep(stepId);
  },
);

/// Provider for gCode file management operations
final gcodeFileManagementProvider = Provider<GCodeFileManagement>((ref) {
  final repository = ref.read(gcodeFileRepositoryProvider);
  return GCodeFileManagement(repository);
});

/// Class for managing gCode file operations
class GCodeFileManagement {
  final GCodeFileRepository _repository;

  GCodeFileManagement(this._repository);

  /// Get all gCode files
  Future<List<GCodeFile>> getAllGCodeFiles() async {
    return await _repository.getAllGCodeFiles();
  }

  /// Get gCode files by machine type
  Future<List<GCodeFile>> getGCodeFilesByMachineType(String machineType) async {
    return await _repository.getGCodeFilesByMachineType(machineType);
  }

  /// Get a single gCode file by ID
  Future<GCodeFile?> getGCodeFileById(String id) async {
    return await _repository.getGCodeFileById(id);
  }

  /// Get a gCode file by GitHub path
  Future<GCodeFile?> getGCodeFileByPath(String githubPath) async {
    return await _repository.getGCodeFileByPath(githubPath);
  }

  /// Create a new gCode file
  Future<GCodeFile> createGCodeFile(GCodeFile file) async {
    return await _repository.createGCodeFile(file);
  }

  /// Update an existing gCode file
  Future<GCodeFile> updateGCodeFile(GCodeFile file) async {
    return await _repository.updateGCodeFile(file);
  }

  /// Upsert a gCode file (insert or update based on github_path)
  Future<GCodeFile> upsertGCodeFile(GCodeFile file) async {
    return await _repository.upsertGCodeFile(file);
  }

  /// Delete a gCode file
  Future<void> deleteGCodeFile(String id) async {
    await _repository.deleteGCodeFile(id);
  }

  /// Batch upsert gCode files (for syncing from GitHub)
  Future<List<GCodeFile>> batchUpsertGCodeFiles(List<GCodeFile> files) async {
    return await _repository.batchUpsertGCodeFiles(files);
  }

  /// Get all gCode files for a production step
  Future<List<StepGCodeFile>> getGCodeFilesForStep(String stepId) async {
    return await _repository.getGCodeFilesForStep(stepId);
  }

  /// Add a gCode file to a production step
  Future<StepGCodeFile> addGCodeFileToStep({
    required String stepId,
    required String gcodeFileId,
    required int executionOrder,
  }) async {
    return await _repository.addGCodeFileToStep(
      stepId: stepId,
      gcodeFileId: gcodeFileId,
      executionOrder: executionOrder,
    );
  }

  /// Remove a gCode file from a production step
  Future<void> removeGCodeFileFromStep(String stepGcodeFileId) async {
    await _repository.removeGCodeFileFromStep(stepGcodeFileId);
  }

  /// Remove all gCode files from a production step
  Future<void> removeAllGCodeFilesFromStep(String stepId) async {
    await _repository.removeAllGCodeFilesFromStep(stepId);
  }

  /// Update execution order for a step-gCode association
  Future<StepGCodeFile> updateExecutionOrder({
    required String stepGcodeFileId,
    required int newExecutionOrder,
  }) async {
    return await _repository.updateExecutionOrder(
      stepGcodeFileId: stepGcodeFileId,
      newExecutionOrder: newExecutionOrder,
    );
  }

  /// Batch update gCode files for a step (replaces all existing associations)
  Future<List<StepGCodeFile>> updateGCodeFilesForStep({
    required String stepId,
    required List<String> gcodeFileIds,
  }) async {
    return await _repository.updateGCodeFilesForStep(
      stepId: stepId,
      gcodeFileIds: gcodeFileIds,
    );
  }
}
