import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/rfid_tag_roll.dart';
import 'package:saturday_app/repositories/rfid_tag_roll_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Provider for RfidTagRollRepository
final rfidTagRollRepositoryProvider = Provider<RfidTagRollRepository>((ref) {
  return RfidTagRollRepository();
});

/// Provider for all rolls (newest first)
final allRfidTagRollsProvider = FutureProvider<List<RfidTagRoll>>((ref) async {
  final repository = ref.watch(rfidTagRollRepositoryProvider);
  return await repository.getRolls();
});

/// Provider for rolls filtered by status
final rfidTagRollsByStatusProvider =
    FutureProvider.family<List<RfidTagRoll>, RfidTagRollStatus?>(
        (ref, status) async {
  final repository = ref.watch(rfidTagRollRepositoryProvider);
  return await repository.getRolls(status: status);
});

/// Provider for a single roll by ID
final rfidTagRollByIdProvider =
    FutureProvider.family<RfidTagRoll?, String>((ref, id) async {
  final repository = ref.watch(rfidTagRollRepositoryProvider);
  return await repository.getRollById(id);
});

/// Provider for tags belonging to a specific roll
final tagsForRollProvider =
    FutureProvider.family<List<RfidTag>, String>((ref, rollId) async {
  final repository = ref.watch(rfidTagRollRepositoryProvider);
  return await repository.getTagsForRoll(rollId);
});

/// Provider for tag count on a specific roll
final tagCountForRollProvider =
    FutureProvider.family<int, String>((ref, rollId) async {
  final repository = ref.watch(rfidTagRollRepositoryProvider);
  return await repository.getTagCountForRoll(rollId);
});

/// Provider for next position on a specific roll
final nextPositionForRollProvider =
    FutureProvider.family<int, String>((ref, rollId) async {
  final repository = ref.watch(rfidTagRollRepositoryProvider);
  return await repository.getNextPositionForRoll(rollId);
});

/// Provider for roll count
final rfidTagRollCountProvider =
    FutureProvider.family<int, RfidTagRollStatus?>((ref, status) async {
  final repository = ref.watch(rfidTagRollRepositoryProvider);
  return await repository.getRollCount(status: status);
});

/// Provider for total roll count (all statuses)
final totalRfidTagRollCountProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(rfidTagRollRepositoryProvider);
  return await repository.getRollCount();
});

/// Provider for roll management actions
final rfidTagRollManagementProvider =
    Provider((ref) => RfidTagRollManagement(ref));

/// Roll management actions
class RfidTagRollManagement {
  final Ref ref;

  RfidTagRollManagement(this.ref);

  /// Create a new roll
  Future<RfidTagRoll> createRoll({
    required double labelWidthMm,
    required double labelHeightMm,
    required int labelCount,
    String? manufacturerUrl,
    String? createdBy,
  }) async {
    try {
      final repository = ref.read(rfidTagRollRepositoryProvider);
      final roll = await repository.createRoll(
        labelWidthMm: labelWidthMm,
        labelHeightMm: labelHeightMm,
        labelCount: labelCount,
        manufacturerUrl: manufacturerUrl,
        createdBy: createdBy,
      );

      // Invalidate roll lists to refresh
      _invalidateRollLists();

      AppLogger.info('Roll created successfully');
      return roll;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create roll', error, stackTrace);
      rethrow;
    }
  }

  /// Update roll status
  Future<RfidTagRoll> updateRollStatus(
    String id,
    RfidTagRollStatus status,
  ) async {
    try {
      final repository = ref.read(rfidTagRollRepositoryProvider);
      final roll = await repository.updateRollStatus(id, status);

      // Invalidate related providers
      _invalidateRollLists();
      ref.invalidate(rfidTagRollByIdProvider(id));

      AppLogger.info('Roll status updated successfully');
      return roll;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update roll status', error, stackTrace);
      rethrow;
    }
  }

  /// Mark roll as ready to print
  Future<RfidTagRoll> markReadyToPrint(String id) async {
    return updateRollStatus(id, RfidTagRollStatus.readyToPrint);
  }

  /// Start printing a roll
  Future<RfidTagRoll> startPrinting(String id) async {
    return updateRollStatus(id, RfidTagRollStatus.printing);
  }

  /// Complete a roll
  Future<RfidTagRoll> completeRoll(String id) async {
    return updateRollStatus(id, RfidTagRollStatus.completed);
  }

  /// Update last printed position
  Future<RfidTagRoll> updateLastPrintedPosition(
    String id,
    int position,
  ) async {
    try {
      final repository = ref.read(rfidTagRollRepositoryProvider);
      final roll = await repository.updateLastPrintedPosition(id, position);

      // Invalidate related providers
      ref.invalidate(rfidTagRollByIdProvider(id));

      AppLogger.info('Roll print position updated to $position');
      return roll;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update roll print position', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a roll
  Future<void> deleteRoll(String id) async {
    try {
      final repository = ref.read(rfidTagRollRepositoryProvider);
      await repository.deleteRoll(id);

      // Invalidate roll lists
      _invalidateRollLists();

      AppLogger.info('Roll deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete roll', error, stackTrace);
      rethrow;
    }
  }

  /// Invalidate all roll list providers to trigger refresh
  void _invalidateRollLists() {
    ref.invalidate(allRfidTagRollsProvider);
    ref.invalidate(totalRfidTagRollCountProvider);
  }

  /// Manually refresh all roll data
  void refreshRolls() {
    _invalidateRollLists();
  }
}

/// State for tracking the currently selected roll (for write/print workflows)
class CurrentRollNotifier extends StateNotifier<RfidTagRoll?> {
  CurrentRollNotifier() : super(null);

  void setRoll(RfidTagRoll roll) {
    state = roll;
  }

  void clearRoll() {
    state = null;
  }

  void updateRoll(RfidTagRoll roll) {
    if (state?.id == roll.id) {
      state = roll;
    }
  }
}

/// Provider for the currently selected roll
final currentRollProvider =
    StateNotifierProvider<CurrentRollNotifier, RfidTagRoll?>((ref) {
  return CurrentRollNotifier();
});
