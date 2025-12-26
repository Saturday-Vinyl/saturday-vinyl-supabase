import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/step_timer.dart';
import 'package:saturday_app/repositories/step_timer_repository.dart';

/// Provider for step timer repository
final stepTimerRepositoryProvider = Provider<StepTimerRepository>((ref) {
  return StepTimerRepository();
});

/// Provider for fetching timers for a specific step
final stepTimersProvider = FutureProvider.family<List<StepTimer>, String>(
  (ref, stepId) async {
    final repository = ref.read(stepTimerRepositoryProvider);
    return repository.getTimersForStep(stepId);
  },
);

/// Provider for step timer management operations
final stepTimerManagementProvider = Provider<StepTimerManagement>((ref) {
  final repository = ref.read(stepTimerRepositoryProvider);
  return StepTimerManagement(repository);
});

/// Class for managing step timer operations
class StepTimerManagement {
  final StepTimerRepository _repository;

  StepTimerManagement(this._repository);

  /// Create a new step timer
  Future<StepTimer> createTimer(StepTimer timer) async {
    return await _repository.createTimer(timer);
  }

  /// Update an existing step timer
  Future<StepTimer> updateTimer(StepTimer timer) async {
    return await _repository.updateTimer(timer);
  }

  /// Delete a step timer
  Future<void> deleteTimer(String timerId) async {
    await _repository.deleteTimer(timerId);
  }

  /// Batch create timers for a step
  /// timerConfigs should be a list of maps with 'name' and 'duration' keys
  Future<List<StepTimer>> batchCreateTimers(
    String stepId,
    List<Map<String, dynamic>> timerConfigs,
  ) async {
    return await _repository.batchCreateTimers(stepId, timerConfigs);
  }

  /// Update all timers for a step (replaces existing)
  Future<List<StepTimer>> updateTimersForStep(
    String stepId,
    List<Map<String, dynamic>> timerConfigs,
  ) async {
    return await _repository.updateTimersForStep(stepId, timerConfigs);
  }

  /// Delete all timers for a step
  Future<void> deleteTimersForStep(String stepId) async {
    await _repository.deleteTimersForStep(stepId);
  }
}
