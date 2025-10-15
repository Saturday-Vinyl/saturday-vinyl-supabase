import 'package:saturday_app/models/step_label.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing step labels
class StepLabelRepository {
  final _supabase = SupabaseService.instance.client;

  /// Get all labels for a production step (ordered by label_order)
  Future<List<StepLabel>> getLabelsForStep(String stepId) async {
    try {
      AppLogger.info('Fetching labels for step: $stepId');

      final response = await _supabase
          .from('step_labels')
          .select()
          .eq('step_id', stepId)
          .order('label_order');

      final labels = (response as List)
          .map((json) => StepLabel.fromJson(json))
          .toList();

      AppLogger.info('Found ${labels.length} labels for step $stepId');
      return labels;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching step labels', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new step label
  Future<StepLabel> createLabel(StepLabel label) async {
    try {
      AppLogger.info('Creating step label: ${label.labelText}');

      final response = await _supabase
          .from('step_labels')
          .insert(label.toJson())
          .select()
          .single();

      final createdLabel = StepLabel.fromJson(response);
      AppLogger.info('Created step label: ${createdLabel.id}');
      return createdLabel;
    } catch (error, stackTrace) {
      AppLogger.error('Error creating step label', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing step label
  Future<StepLabel> updateLabel(StepLabel label) async {
    try {
      AppLogger.info('Updating step label: ${label.id}');

      final response = await _supabase
          .from('step_labels')
          .update(label.toJson())
          .eq('id', label.id)
          .select()
          .single();

      final updatedLabel = StepLabel.fromJson(response);
      AppLogger.info('Updated step label: ${updatedLabel.id}');
      return updatedLabel;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating step label', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a step label
  Future<void> deleteLabel(String labelId) async {
    try {
      AppLogger.info('Deleting step label: $labelId');

      await _supabase
          .from('step_labels')
          .delete()
          .eq('id', labelId);

      AppLogger.info('Deleted step label: $labelId');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting step label', error, stackTrace);
      rethrow;
    }
  }

  /// Delete all labels for a step
  Future<void> deleteLabelsForStep(String stepId) async {
    try {
      AppLogger.info('Deleting all labels for step: $stepId');

      await _supabase
          .from('step_labels')
          .delete()
          .eq('step_id', stepId);

      AppLogger.info('Deleted all labels for step: $stepId');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting step labels', error, stackTrace);
      rethrow;
    }
  }

  /// Batch create labels for a step
  Future<List<StepLabel>> batchCreateLabels(
    String stepId,
    List<String> labelTexts,
  ) async {
    try {
      AppLogger.info('Batch creating ${labelTexts.length} labels for step: $stepId');

      final labelsToInsert = labelTexts.asMap().entries.map((entry) {
        return {
          'step_id': stepId,
          'label_text': entry.value,
          'label_order': entry.key + 1,
        };
      }).toList();

      final response = await _supabase
          .from('step_labels')
          .insert(labelsToInsert)
          .select();

      final labels = (response as List)
          .map((json) => StepLabel.fromJson(json))
          .toList();

      AppLogger.info('Created ${labels.length} labels for step');
      return labels;
    } catch (error, stackTrace) {
      AppLogger.error('Error batch creating step labels', error, stackTrace);
      rethrow;
    }
  }

  /// Update labels for a step (replaces all existing labels)
  Future<List<StepLabel>> updateLabelsForStep(
    String stepId,
    List<String> labelTexts,
  ) async {
    try {
      AppLogger.info('Updating labels for step: $stepId');

      // Delete all existing labels
      await deleteLabelsForStep(stepId);

      // Create new labels if any
      if (labelTexts.isEmpty) {
        return [];
      }

      return await batchCreateLabels(stepId, labelTexts);
    } catch (error, stackTrace) {
      AppLogger.error('Error updating step labels', error, stackTrace);
      rethrow;
    }
  }
}
