import 'package:saturday_app/models/step_timer.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing step timers
class StepTimerRepository {
  final _supabase = SupabaseService.instance.client;

  /// Get all timers for a production step (ordered by timer_order)
  Future<List<StepTimer>> getTimersForStep(String stepId) async {
    try {
      AppLogger.info('Fetching timers for step: $stepId');

      final response = await _supabase
          .from('step_timers')
          .select()
          .eq('step_id', stepId)
          .order('timer_order');

      final timers = (response as List)
          .map((json) => StepTimer.fromJson(json))
          .toList();

      AppLogger.info('Found ${timers.length} timers for step $stepId');
      return timers;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching step timers', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new step timer
  Future<StepTimer> createTimer(StepTimer timer) async {
    try {
      AppLogger.info('Creating step timer: ${timer.timerName}');

      final response = await _supabase
          .from('step_timers')
          .insert(timer.toJson())
          .select()
          .single();

      final createdTimer = StepTimer.fromJson(response);
      AppLogger.info('Created step timer: ${createdTimer.id}');
      return createdTimer;
    } catch (error, stackTrace) {
      AppLogger.error('Error creating step timer', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing step timer
  Future<StepTimer> updateTimer(StepTimer timer) async {
    try {
      AppLogger.info('Updating step timer: ${timer.id}');

      final response = await _supabase
          .from('step_timers')
          .update(timer.toJson())
          .eq('id', timer.id)
          .select()
          .single();

      final updatedTimer = StepTimer.fromJson(response);
      AppLogger.info('Updated step timer: ${updatedTimer.id}');
      return updatedTimer;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating step timer', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a step timer
  Future<void> deleteTimer(String timerId) async {
    try {
      AppLogger.info('Deleting step timer: $timerId');

      await _supabase
          .from('step_timers')
          .delete()
          .eq('id', timerId);

      AppLogger.info('Deleted step timer: $timerId');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting step timer', error, stackTrace);
      rethrow;
    }
  }

  /// Delete all timers for a step
  Future<void> deleteTimersForStep(String stepId) async {
    try {
      AppLogger.info('Deleting all timers for step: $stepId');

      await _supabase
          .from('step_timers')
          .delete()
          .eq('step_id', stepId);

      AppLogger.info('Deleted all timers for step: $stepId');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting step timers', error, stackTrace);
      rethrow;
    }
  }

  /// Batch create timers for a step
  /// Takes a list of timer configurations with name and duration
  Future<List<StepTimer>> batchCreateTimers(
    String stepId,
    List<Map<String, dynamic>> timerConfigs,
  ) async {
    try {
      AppLogger.info('Batch creating ${timerConfigs.length} timers for step: $stepId');

      final timersToInsert = timerConfigs.asMap().entries.map((entry) {
        return {
          'step_id': stepId,
          'timer_name': entry.value['name'] as String,
          'duration_minutes': entry.value['duration'] as int,
          'timer_order': entry.key + 1,
        };
      }).toList();

      final response = await _supabase
          .from('step_timers')
          .insert(timersToInsert)
          .select();

      final timers = (response as List)
          .map((json) => StepTimer.fromJson(json))
          .toList();

      AppLogger.info('Created ${timers.length} timers for step');
      return timers;
    } catch (error, stackTrace) {
      AppLogger.error('Error batch creating step timers', error, stackTrace);
      rethrow;
    }
  }

  /// Update timers for a step (replaces all existing timers)
  Future<List<StepTimer>> updateTimersForStep(
    String stepId,
    List<Map<String, dynamic>> timerConfigs,
  ) async {
    try {
      AppLogger.info('Updating timers for step: $stepId');

      // Delete all existing timers
      await deleteTimersForStep(stepId);

      // Create new timers if any
      if (timerConfigs.isEmpty) {
        return [];
      }

      return await batchCreateTimers(stepId, timerConfigs);
    } catch (error, stackTrace) {
      AppLogger.error('Error updating step timers', error, stackTrace);
      rethrow;
    }
  }
}
