import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/models/unit_filter.dart';
import 'package:saturday_app/models/unit_list_item.dart';
import 'package:saturday_app/providers/unit_provider.dart';
import 'package:saturday_app/services/realtime_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

// ============================================================================
// Realtime Service Provider
// ============================================================================

/// Provider for RealtimeService singleton
final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  return RealtimeService();
});

// ============================================================================
// Filter State Management
// ============================================================================

/// Provider for unit filter state
final unitFilterProvider =
    StateNotifierProvider<UnitFilterNotifier, UnitFilter>((ref) {
  return UnitFilterNotifier();
});

/// StateNotifier for managing unit filter state
class UnitFilterNotifier extends StateNotifier<UnitFilter> {
  UnitFilterNotifier() : super(UnitFilter.defaultFilter);

  /// Set status filter
  void setStatus(UnitStatus? status) {
    state = state.copyWith(status: status, clearStatus: status == null);
  }

  /// Set search query
  void setSearchQuery(String? query) {
    state = state.copyWith(
      searchQuery: query,
      clearSearch: query == null || query.isEmpty,
    );
  }

  /// Set connected filter
  void setConnected(bool? isConnected) {
    state = state.copyWith(
      isConnected: isConnected,
      clearConnected: isConnected == null,
    );
  }

  /// Set sort options
  void setSortBy(UnitSortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  /// Toggle sort direction
  void toggleSortDirection() {
    state = state.copyWith(sortAscending: !state.sortAscending);
  }

  /// Set sort direction
  void setSortAscending(bool ascending) {
    state = state.copyWith(sortAscending: ascending);
  }

  /// Reset all filters to default
  void reset() {
    state = UnitFilter.defaultFilter;
  }
}

// ============================================================================
// Dashboard Data Provider
// ============================================================================

/// Provider for unit list items (dashboard view)
///
/// Watches the filter provider and refetches when filter changes.
final unitDashboardProvider =
    FutureProvider<List<UnitListItem>>((ref) async {
  final filter = ref.watch(unitFilterProvider);
  final repository = ref.watch(unitRepositoryProvider);
  return repository.getUnitListItems(filter: filter);
});

// ============================================================================
// Realtime Updates Management
// ============================================================================

/// Provider for managing realtime unit updates
///
/// Maintains a map of unit IDs to their latest state from realtime updates.
/// The UI merges these updates with the base data from unitDashboardProvider.
final unitRealtimeUpdatesProvider =
    StateNotifierProvider<UnitRealtimeNotifier, Map<String, UnitListItem>>(
        (ref) {
  return UnitRealtimeNotifier(ref);
});

/// StateNotifier for handling realtime unit updates
class UnitRealtimeNotifier extends StateNotifier<Map<String, UnitListItem>> {
  final Ref ref;
  RealtimeChannel? _devicesChannel;
  RealtimeChannel? _unitsChannel;

  UnitRealtimeNotifier(this.ref) : super({});

  /// Start listening to realtime updates
  void startListening() {
    final realtimeService = ref.read(realtimeServiceProvider);

    AppLogger.info('Starting realtime subscriptions for unit dashboard');

    // Subscribe to device updates (for last_seen_at, telemetry)
    _devicesChannel = realtimeService.subscribeToDevices(
      onInsert: _handleDeviceChange,
      onUpdate: _handleDeviceChange,
    );

    // Subscribe to unit updates (for status changes)
    _unitsChannel = realtimeService.subscribeToUnits(
      onInsert: _handleUnitInsert,
      onUpdate: _handleUnitChange,
      onDelete: _handleUnitDelete,
    );
  }

  /// Stop listening to realtime updates
  Future<void> stopListening() async {
    final realtimeService = ref.read(realtimeServiceProvider);

    if (_devicesChannel != null) {
      await realtimeService.unsubscribe(_devicesChannel!);
      _devicesChannel = null;
    }

    if (_unitsChannel != null) {
      await realtimeService.unsubscribe(_unitsChannel!);
      _unitsChannel = null;
    }

    AppLogger.info('Stopped realtime subscriptions for unit dashboard');
  }

  void _handleDeviceChange(PostgresChangePayload payload) {
    final deviceData = payload.newRecord;
    final unitId = deviceData['unit_id'] as String?;

    if (unitId == null) return;

    // Check if we have this unit in our state
    final existingUnit = state[unitId];
    if (existingUnit == null) {
      // Unit not in our current view, trigger a refresh
      ref.invalidate(unitDashboardProvider);
      return;
    }

    // Check if this device is the primary device for this unit
    if (existingUnit.primaryDeviceId != deviceData['id']) {
      return; // Not the primary device, ignore
    }

    // Update the unit with new device data
    final updatedUnit = existingUnit.copyWith(
      lastSeenAt: deviceData['last_seen_at'] != null
          ? DateTime.parse(deviceData['last_seen_at'] as String)
          : null,
      firmwareVersion: deviceData['firmware_version'] as String?,
      latestTelemetry: deviceData['latest_telemetry'] != null
          ? Map<String, dynamic>.from(deviceData['latest_telemetry'] as Map)
          : null,
    );

    state = {...state, unitId: updatedUnit};
    AppLogger.debug('Realtime: Updated device for unit $unitId');
  }

  void _handleUnitInsert(PostgresChangePayload payload) {
    // New unit inserted - trigger a full refresh to get it with device data
    ref.invalidate(unitDashboardProvider);
    AppLogger.debug('Realtime: New unit inserted, refreshing dashboard');
  }

  void _handleUnitChange(PostgresChangePayload payload) {
    final unitData = payload.newRecord;
    final unitId = unitData['id'] as String?;

    if (unitId == null) return;

    final existingUnit = state[unitId];
    if (existingUnit == null) {
      // Unit not in our current view, might be due to filter
      // Check if it should now be visible
      ref.invalidate(unitDashboardProvider);
      return;
    }

    // Update unit fields
    final updatedUnit = existingUnit.copyWith(
      serialNumber: unitData['serial_number'] as String?,
      deviceName: unitData['device_name'] as String?,
      status: UnitStatusExtension.fromString(unitData['status'] as String?),
      userId: unitData['user_id'] as String?,
    );

    state = {...state, unitId: updatedUnit};
    AppLogger.debug('Realtime: Updated unit $unitId');
  }

  void _handleUnitDelete(PostgresChangePayload payload) {
    final unitData = payload.oldRecord;
    final unitId = unitData['id'] as String?;

    if (unitId == null) return;

    // Remove from state
    final newState = Map<String, UnitListItem>.from(state);
    newState.remove(unitId);
    state = newState;

    AppLogger.debug('Realtime: Removed unit $unitId');
  }

  /// Initialize state from loaded units
  void initializeFromUnits(List<UnitListItem> units) {
    state = {for (var unit in units) unit.id: unit};
  }

  /// Get a unit by ID (from realtime state or null if not tracked)
  UnitListItem? getUnit(String unitId) => state[unitId];

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

