import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:saturday_consumer_app/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Table names for the unified device architecture.
const _unitsTable = 'units';
const _devicesTable = 'devices';

/// How often to re-evaluate device connectivity status based on heartbeat staleness.
const _stalenessCheckInterval = Duration(minutes: 1);

/// State for realtime device updates.
class RealtimeDeviceState {
  /// All user devices with real-time updates.
  final List<Device> devices;

  /// Whether the initial fetch is loading.
  final bool isLoading;

  /// Error message if something went wrong.
  final String? error;

  /// When the state was last updated.
  final DateTime? lastUpdated;

  const RealtimeDeviceState({
    this.devices = const [],
    this.isLoading = true,
    this.error,
    this.lastUpdated,
  });

  /// Get all hubs.
  List<Device> get hubs =>
      devices.where((d) => d.deviceType == DeviceType.hub).toList();

  /// Get all crates.
  List<Device> get crates =>
      devices.where((d) => d.deviceType == DeviceType.crate).toList();

  /// Get devices that are effectively online (based on heartbeat staleness).
  List<Device> get onlineDevices =>
      devices.where((d) => d.isEffectivelyOnline).toList();

  /// Get devices that are offline or have stale heartbeats.
  List<Device> get offlineDevices => devices
      .where((d) => d.connectivityStatus == ConnectivityStatus.offline)
      .toList();

  /// Get devices with uncertain connectivity (maybe offline).
  List<Device> get uncertainDevices => devices
      .where((d) => d.connectivityStatus == ConnectivityStatus.uncertain)
      .toList();

  /// Get devices needing setup.
  List<Device> get devicesNeedingSetup =>
      devices.where((d) => d.status == DeviceStatus.setupRequired).toList();

  /// Get devices with low battery.
  List<Device> get lowBatteryDevices =>
      devices.where((d) => d.isLowBattery).toList();

  /// Get device by ID.
  Device? getDeviceById(String id) {
    try {
      return devices.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  RealtimeDeviceState copyWith({
    List<Device>? devices,
    bool? isLoading,
    String? error,
    DateTime? lastUpdated,
    bool clearError = false,
  }) {
    return RealtimeDeviceState(
      devices: devices ?? this.devices,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// StateNotifier for managing realtime device state.
///
/// Subscribes to both `units` and `devices` tables for the unified
/// device architecture. Units represent product ownership while devices
/// represent hardware instances with telemetry.
class RealtimeDeviceNotifier extends StateNotifier<RealtimeDeviceState> {
  RealtimeDeviceNotifier(this._ref) : super(const RealtimeDeviceState()) {
    _initialize();
  }

  final Ref _ref;
  RealtimeChannel? _unitsChannel;
  RealtimeChannel? _devicesChannel;
  Timer? _stalenessCheckTimer;

  /// In-memory cache of unit data (keyed by unit ID).
  final Map<String, Map<String, dynamic>> _unitsCache = {};

  /// In-memory cache of device data (keyed by unit ID, not device ID).
  /// We key by unit ID because that's how we merge units + devices.
  final Map<String, Map<String, dynamic>> _devicesCache = {};

  /// Track which devices we've already sent offline notifications for,
  /// to avoid duplicate notifications.
  final Set<String> _notifiedOfflineDevices = {};

  /// Initialize the realtime subscription.
  Future<void> _initialize() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    // First fetch all devices (uses JOIN query)
    await _fetchDevices(userId);

    // Then subscribe to realtime changes on both tables
    _subscribeToUnits(userId);
    _subscribeToDevices();

    // Start periodic staleness checks for heartbeat-based offline detection
    _startStalenessCheckTimer();
  }

  /// Start the periodic timer that checks for stale heartbeats.
  ///
  /// This ensures the UI updates even when no realtime events are received,
  /// which is important for detecting devices that went offline without
  /// sending an explicit disconnect signal.
  void _startStalenessCheckTimer() {
    _stalenessCheckTimer?.cancel();
    _stalenessCheckTimer = Timer.periodic(_stalenessCheckInterval, (_) {
      _checkHeartbeatStaleness();
    });
  }

  /// Check all devices for stale heartbeats and trigger notifications.
  ///
  /// This is called periodically to detect devices that have gone offline
  /// without sending an explicit disconnect signal.
  void _checkHeartbeatStaleness() {
    if (state.devices.isEmpty) return;

    for (final device in state.devices) {
      // Skip devices that are explicitly offline or need setup
      if (device.status != DeviceStatus.online) continue;

      // Check if device has crossed the offline threshold (10 min)
      if (device.isHeartbeatCriticallyStale) {
        // Only notify once per device until they come back online
        if (!_notifiedOfflineDevices.contains(device.id)) {
          _notifiedOfflineDevices.add(device.id);
          _sendDeviceOfflineNotification(device.id, device.name);
        }
      }
    }

    // Trigger a state update to refresh UI (connectivity status is derived)
    // This forces widgets watching the provider to rebuild and re-evaluate
    // the connectivityStatus getter on each device.
    state = state.copyWith(lastUpdated: DateTime.now());
  }

  /// Fetch all devices for the user using the unified units + devices schema.
  Future<void> _fetchDevices(String userId) async {
    try {
      final unitRepo = _ref.read(unitRepositoryProvider);
      final devices = await unitRepo.getUserDevices(userId);

      // Populate caches from the initial fetch for merging with realtime updates
      _unitsCache.clear();
      _devicesCache.clear();

      for (final device in devices) {
        // Store unit data in cache
        // Note: We store the raw status string that fromJoinedJson expects
        // New unit_status enum: 'in_production', 'inventory', 'assigned', 'claimed'
        final statusString = device.status == DeviceStatus.online
            ? 'claimed'
            : device.status == DeviceStatus.setupRequired
                ? 'assigned'
                : 'inventory';
        _unitsCache[device.id] = {
          'id': device.id,
          'serial_number': device.serialNumber,
          'consumer_user_id': device.userId,
          'consumer_name': device.name,
          'status': statusString,
          'created_at': device.createdAt.toIso8601String(),
        };

        // Store device data if available (keyed by unit ID)
        if (device.macAddress != null) {
          _devicesCache[device.id] = {
            'unit_id': device.id,
            'mac_address': device.macAddress,
            'firmware_version': device.firmwareVersion,
            'last_seen_at': device.lastSeenAt?.toIso8601String(),
            'latest_telemetry': device.telemetry?.toJson(),
            'status': device.isEffectivelyOnline ? 'online' : 'offline',
          };
        }
      }

      state = state.copyWith(
        devices: devices,
        isLoading: false,
        lastUpdated: DateTime.now(),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to fetch devices: $e',
      );
    }
  }

  /// Subscribe to realtime changes on the units table.
  ///
  /// Units are filtered by user_id to only receive changes for the current user's devices.
  void _subscribeToUnits(String userId) {
    final client = _ref.read(supabaseClientProvider);

    _unitsChannel = client
        .channel('units_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _unitsTable,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'consumer_user_id',
            value: userId,
          ),
          callback: (payload) {
            _handleUnitsPayload(payload);
          },
        )
        .subscribe();
  }

  /// Subscribe to realtime changes on the devices table.
  ///
  /// We subscribe to all device changes and filter in-memory based on
  /// whether we have a matching unit in our cache. This is necessary because
  /// devices don't have a direct user_id column.
  void _subscribeToDevices() {
    final client = _ref.read(supabaseClientProvider);

    _devicesChannel = client
        .channel('devices_all')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _devicesTable,
          callback: (payload) {
            _handleDevicesPayload(payload);
          },
        )
        .subscribe();
  }

  /// Handle incoming realtime payloads from the units table.
  void _handleUnitsPayload(PostgresChangePayload payload) {
    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
        _handleUnitInsert(payload.newRecord);
        break;
      case PostgresChangeEvent.update:
        _handleUnitUpdate(payload.newRecord, payload.oldRecord);
        break;
      case PostgresChangeEvent.delete:
        _handleUnitDelete(payload.oldRecord);
        break;
      default:
        break;
    }
  }

  /// Handle incoming realtime payloads from the devices table.
  void _handleDevicesPayload(PostgresChangePayload payload) {
    final record = payload.eventType == PostgresChangeEvent.delete
        ? payload.oldRecord
        : payload.newRecord;

    // Find the unit_id for this device
    final unitId = record['unit_id'] as String?;
    if (unitId == null) return;

    // Only process if we have this unit in our cache (i.e., it belongs to this user)
    if (!_unitsCache.containsKey(unitId)) return;

    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
      case PostgresChangeEvent.update:
        _handleDeviceUpdate(unitId, payload.newRecord, payload.oldRecord);
        break;
      case PostgresChangeEvent.delete:
        _handleDeviceDelete(unitId);
        break;
      default:
        break;
    }
  }

  /// Handle a new unit being claimed by the user.
  void _handleUnitInsert(Map<String, dynamic> record) {
    final unitId = record['id'] as String?;
    if (unitId == null) return;

    // Add to cache
    _unitsCache[unitId] = record;

    // Build merged device and add to state
    _rebuildDeviceState();
  }

  /// Handle an existing unit being updated.
  void _handleUnitUpdate(
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) {
    final unitId = newRecord['id'] as String?;
    if (unitId == null) return;

    // Update cache
    _unitsCache[unitId] = newRecord;

    // Rebuild state
    _rebuildDeviceState();

    // Check for notifications
    _checkForUnitNotifications(oldRecord, newRecord);
  }

  /// Handle a unit being unclaimed (deleted from user's perspective).
  void _handleUnitDelete(Map<String, dynamic> record) {
    final unitId = record['id'] as String?;
    if (unitId == null) return;

    // Remove from caches
    _unitsCache.remove(unitId);
    _devicesCache.remove(unitId);

    // Rebuild state
    _rebuildDeviceState();
  }

  /// Handle device data update (telemetry, status, etc.).
  void _handleDeviceUpdate(
    String unitId,
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) {
    // Update cache (keyed by unit_id)
    _devicesCache[unitId] = newRecord;

    // Rebuild state
    _rebuildDeviceState();

    // Check for notifications (battery, status changes)
    _checkForDeviceNotifications(unitId, oldRecord, newRecord);
  }

  /// Handle device being unlinked from unit.
  void _handleDeviceDelete(String unitId) {
    // Remove from cache
    _devicesCache.remove(unitId);

    // Rebuild state
    _rebuildDeviceState();
  }

  /// Rebuild the device state from the cached units + devices data.
  void _rebuildDeviceState() {
    final devices = <Device>[];

    for (final unitEntry in _unitsCache.entries) {
      final unitId = unitEntry.key;
      final unitData = unitEntry.value;

      // Get linked device data if available
      final deviceData = _devicesCache[unitId];

      // Build merged JSON structure expected by Device.fromJoinedJson
      final mergedJson = <String, dynamic>{
        ...unitData,
        'devices': deviceData != null ? [deviceData] : [],
      };

      try {
        devices.add(Device.fromJoinedJson(mergedJson));
      } catch (e) {
        // Skip malformed data
      }
    }

    // Sort by created_at (newest first)
    devices.sort((a, b) {
      final aTime = _unitsCache[a.id]?['created_at'] as String?;
      final bTime = _unitsCache[b.id]?['created_at'] as String?;
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    state = state.copyWith(
      devices: devices,
      lastUpdated: DateTime.now(),
    );

    // Check if any devices came back online
    for (final device in devices) {
      if (device.isEffectivelyOnline) {
        _notifiedOfflineDevices.remove(device.id);
      }
    }
  }

  /// Check if we need to send notifications for unit changes.
  void _checkForUnitNotifications(
    Map<String, dynamic> oldRecord,
    Map<String, dynamic> newRecord,
  ) {
    final oldStatus = DeviceStatus.fromString(oldRecord['status'] as String? ?? 'offline');
    final newStatus = DeviceStatus.fromString(newRecord['status'] as String? ?? 'offline');
    final deviceName = newRecord['consumer_name'] as String? ?? 'Unknown Device';
    final unitId = newRecord['id'] as String? ?? '';

    // Unit status changed to offline
    if (oldStatus == DeviceStatus.online && newStatus == DeviceStatus.offline) {
      _sendDeviceOfflineNotification(unitId, deviceName);
    }
  }

  /// Check if we need to send notifications for device telemetry changes.
  void _checkForDeviceNotifications(
    String unitId,
    Map<String, dynamic> oldRecord,
    Map<String, dynamic> newRecord,
  ) {
    // Get device name from units cache
    final unitData = _unitsCache[unitId];
    final deviceName = unitData?['consumer_name'] as String? ?? 'Unknown Device';

    // Check battery level from latest_telemetry
    final oldTelemetry = oldRecord['latest_telemetry'] as Map<String, dynamic>?;
    final newTelemetry = newRecord['latest_telemetry'] as Map<String, dynamic>?;

    final oldBattery = oldTelemetry?['battery_level'] as int?;
    final newBattery = newTelemetry?['battery_level'] as int?;

    if (newBattery != null && newBattery < 20) {
      // Only notify if it just dropped below 20%
      if (oldBattery == null || oldBattery >= 20) {
        _sendLowBatteryNotification(unitId, deviceName, newBattery);
      }
    }
  }

  /// Send a device offline notification.
  void _sendDeviceOfflineNotification(String deviceId, String deviceName) {
    try {
      NotificationService.instance.showDeviceOfflineNotification(
        deviceId: deviceId,
        deviceName: deviceName,
      );
    } catch (_) {
      // Ignore notification errors
    }
  }

  /// Send a low battery notification.
  void _sendLowBatteryNotification(
    String deviceId,
    String deviceName,
    int batteryLevel,
  ) {
    try {
      NotificationService.instance.showLowBatteryNotification(
        deviceId: deviceId,
        deviceName: deviceName,
        batteryLevel: batteryLevel,
      );
    } catch (_) {
      // Ignore notification errors
    }
  }

  /// Force refresh all devices.
  Future<void> refresh() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    state = state.copyWith(isLoading: true);
    await _fetchDevices(userId);
  }

  @override
  void dispose() {
    _stalenessCheckTimer?.cancel();
    _unitsChannel?.unsubscribe();
    _devicesChannel?.unsubscribe();
    super.dispose();
  }
}

/// Provider for realtime device state.
final realtimeDeviceProvider =
    StateNotifierProvider<RealtimeDeviceNotifier, RealtimeDeviceState>((ref) {
  return RealtimeDeviceNotifier(ref);
});

/// Provider for realtime devices list.
final realtimeDevicesProvider = Provider<List<Device>>((ref) {
  return ref.watch(realtimeDeviceProvider).devices;
});

/// Provider for realtime device by ID.
final realtimeDeviceByIdProvider =
    Provider.family<Device?, String>((ref, deviceId) {
  return ref.watch(realtimeDeviceProvider).getDeviceById(deviceId);
});

/// Provider for realtime online devices (using heartbeat-aware status).
final realtimeOnlineDevicesProvider = Provider<List<Device>>((ref) {
  return ref.watch(realtimeDeviceProvider).onlineDevices;
});

/// Provider for devices with uncertain connectivity (maybe offline).
final realtimeUncertainDevicesProvider = Provider<List<Device>>((ref) {
  return ref.watch(realtimeDeviceProvider).uncertainDevices;
});

/// Provider for realtime low battery devices.
final realtimeLowBatteryDevicesProvider = Provider<List<Device>>((ref) {
  return ref.watch(realtimeDeviceProvider).lowBatteryDevices;
});

/// Provider for realtime hubs.
final realtimeHubsProvider = Provider<List<Device>>((ref) {
  return ref.watch(realtimeDeviceProvider).hubs;
});

/// Provider for realtime crates.
final realtimeCratesProvider = Provider<List<Device>>((ref) {
  return ref.watch(realtimeDeviceProvider).crates;
});
