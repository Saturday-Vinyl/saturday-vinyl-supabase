import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/step_label.dart';
import 'package:saturday_app/repositories/step_label_repository.dart';

/// Provider for step label repository
final stepLabelRepositoryProvider = Provider<StepLabelRepository>((ref) {
  return StepLabelRepository();
});

/// Provider for fetching labels for a specific step
final stepLabelsProvider = FutureProvider.family<List<StepLabel>, String>(
  (ref, stepId) async {
    final repository = ref.read(stepLabelRepositoryProvider);
    return repository.getLabelsForStep(stepId);
  },
);

/// Provider for step label management operations
final stepLabelManagementProvider = Provider<StepLabelManagement>((ref) {
  final repository = ref.read(stepLabelRepositoryProvider);
  return StepLabelManagement(repository);
});

/// Class for managing step label operations
class StepLabelManagement {
  final StepLabelRepository _repository;

  StepLabelManagement(this._repository);

  /// Create a new step label
  Future<StepLabel> createLabel(StepLabel label) async {
    return await _repository.createLabel(label);
  }

  /// Update an existing step label
  Future<StepLabel> updateLabel(StepLabel label) async {
    return await _repository.updateLabel(label);
  }

  /// Delete a step label
  Future<void> deleteLabel(String labelId) async {
    await _repository.deleteLabel(labelId);
  }

  /// Batch create labels for a step
  Future<List<StepLabel>> batchCreateLabels(
    String stepId,
    List<String> labelTexts,
  ) async {
    return await _repository.batchCreateLabels(stepId, labelTexts);
  }

  /// Update all labels for a step (replaces existing)
  Future<List<StepLabel>> updateLabelsForStep(
    String stepId,
    List<String> labelTexts,
  ) async {
    return await _repository.updateLabelsForStep(stepId, labelTexts);
  }

  /// Delete all labels for a step
  Future<void> deleteLabelsForStep(String stepId) async {
    await _repository.deleteLabelsForStep(stepId);
  }
}
