import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/unit_timer.dart';
import 'package:saturday_app/models/unit_timer_with_details.dart';
import 'package:saturday_app/repositories/unit_timer_repository.dart';

/// Provider for unit timer repository
final unitTimerRepositoryProvider = Provider<UnitTimerRepository>((ref) {
  return UnitTimerRepository();
});

/// Provider for fetching all timers for a specific unit
final unitTimersProvider = FutureProvider.family<List<UnitTimer>, String>(
  (ref, unitId) async {
    final repository = ref.read(unitTimerRepositoryProvider);
    return repository.getTimersForUnit(unitId);
  },
);

/// Provider for fetching active timers with details for a specific unit
final activeUnitTimersWithDetailsProvider =
    FutureProvider.family<List<UnitTimerWithDetails>, String>(
  (ref, unitId) async {
    final repository = ref.read(unitTimerRepositoryProvider);
    return repository.getActiveTimersWithDetailsForUnit(unitId);
  },
);

/// Provider for fetching active timers for a specific unit
final activeUnitTimersProvider = FutureProvider.family<List<UnitTimer>, String>(
  (ref, unitId) async {
    final repository = ref.read(unitTimerRepositoryProvider);
    return repository.getActiveTimersForUnit(unitId);
  },
);

/// Provider for fetching all active timers across all units
final allActiveTimersProvider = FutureProvider<List<UnitTimer>>(
  (ref) async {
    final repository = ref.read(unitTimerRepositoryProvider);
    return repository.getAllActiveTimers();
  },
);

/// Provider for fetching expired active timers (for notifications)
final expiredActiveTimersProvider = FutureProvider<List<UnitTimer>>(
  (ref) async {
    final repository = ref.read(unitTimerRepositoryProvider);
    return repository.getExpiredActiveTimers();
  },
);

/// Provider for unit timer management operations
final unitTimerManagementProvider = Provider<UnitTimerManagement>((ref) {
  final repository = ref.read(unitTimerRepositoryProvider);
  return UnitTimerManagement(repository, ref);
});

/// Class for managing unit timer operations
class UnitTimerManagement {
  final UnitTimerRepository _repository;
  final Ref _ref;

  UnitTimerManagement(this._repository, this._ref);

  /// Start a timer for a production unit
  Future<UnitTimer> startTimer({
    required String unitId,
    required String stepTimerId,
    required int durationMinutes,
  }) async {
    final timer = await _repository.startTimer(
      unitId: unitId,
      stepTimerId: stepTimerId,
      durationMinutes: durationMinutes,
    );

    // Invalidate providers to refresh UI
    _ref.invalidate(unitTimersProvider(unitId));
    _ref.invalidate(activeUnitTimersProvider(unitId));
    _ref.invalidate(activeUnitTimersWithDetailsProvider(unitId));
    _ref.invalidate(allActiveTimersProvider);

    return timer;
  }

  /// Mark a timer as completed
  Future<UnitTimer> completeTimer(String timerId, String unitId) async {
    final timer = await _repository.completeTimer(timerId);

    // Invalidate providers to refresh UI
    _ref.invalidate(unitTimersProvider(unitId));
    _ref.invalidate(activeUnitTimersProvider(unitId));
    _ref.invalidate(activeUnitTimersWithDetailsProvider(unitId));
    _ref.invalidate(allActiveTimersProvider);
    _ref.invalidate(expiredActiveTimersProvider);

    return timer;
  }

  /// Cancel a timer
  Future<UnitTimer> cancelTimer(String timerId, String unitId) async {
    final timer = await _repository.cancelTimer(timerId);

    // Invalidate providers to refresh UI
    _ref.invalidate(unitTimersProvider(unitId));
    _ref.invalidate(activeUnitTimersProvider(unitId));
    _ref.invalidate(activeUnitTimersWithDetailsProvider(unitId));
    _ref.invalidate(allActiveTimersProvider);

    return timer;
  }

  /// Delete a timer
  Future<void> deleteTimer(String timerId, String unitId) async {
    await _repository.deleteTimer(timerId);

    // Invalidate providers to refresh UI
    _ref.invalidate(unitTimersProvider(unitId));
    _ref.invalidate(activeUnitTimersProvider(unitId));
    _ref.invalidate(activeUnitTimersWithDetailsProvider(unitId));
    _ref.invalidate(allActiveTimersProvider);
  }

  /// Get expired active timers
  Future<List<UnitTimer>> getExpiredActiveTimers() async {
    return await _repository.getExpiredActiveTimers();
  }
}
