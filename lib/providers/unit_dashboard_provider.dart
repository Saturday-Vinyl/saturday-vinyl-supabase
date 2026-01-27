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
    if (_devicesChannel != null || _unitsChannel != null) {
      AppLogger.debug('Realtime subscriptions already active, skipping');
      return;
    }

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

    AppLogger.info('Realtime subscriptions initiated for devices and units tables');
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
    final deviceId = deviceData['id'] as String?;
    final macAddress = deviceData['mac_address'] as String?;

    AppLogger.info(
        'Processing device change: device=$deviceId, mac=$macAddress, unit=$unitId');

    if (unitId == null) {
      AppLogger.debug('Ignoring device change: no unit_id (device not linked to unit)');
      return;
    }

    // Check if we have this unit in our state
    final existingUnit = state[unitId];
    if (existingUnit == null) {
      AppLogger.info(
          'Unit $unitId not in current state (${state.length} units tracked), triggering refresh');
      ref.invalidate(unitDashboardProvider);
      return;
    }

    // Check if this device is the primary device for this unit
    if (existingUnit.primaryDeviceId != deviceId) {
      AppLogger.debug(
          'Ignoring device change: device $deviceId is not primary for unit $unitId '
          '(primary=${existingUnit.primaryDeviceId})');
      return;
    }

    // Update the unit with new device data
    final lastSeenAt = deviceData['last_seen_at'] != null
        ? DateTime.parse(deviceData['last_seen_at'] as String)
        : null;
    final updatedUnit = existingUnit.copyWith(
      lastSeenAt: lastSeenAt,
      firmwareVersion: deviceData['firmware_version'] as String?,
      latestTelemetry: deviceData['latest_telemetry'] != null
          ? Map<String, dynamic>.from(deviceData['latest_telemetry'] as Map)
          : null,
    );

    // Use Map.from to create a mutable copy, then update with the variable key
    final newState = Map<String, UnitListItem>.from(state);
    newState[unitId] = updatedUnit;
    state = newState;
    AppLogger.info(
        'Realtime: Updated unit $unitId - lastSeen=$lastSeenAt, isConnected=${updatedUnit.isConnected}');
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

    // Use Map.from to create a mutable copy, then update with the variable key
    final newState = Map<String, UnitListItem>.from(state);
    newState[unitId] = updatedUnit;
    state = newState;
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
    final unitsWithDevices = units.where((u) => u.primaryDeviceId != null).length;
    AppLogger.info(
        'Initializing realtime state with ${units.length} units ($unitsWithDevices have devices)');
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

