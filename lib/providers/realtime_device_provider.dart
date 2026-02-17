import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:saturday_consumer_app/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Table name for the units table.
const _unitsTable = 'units';

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

  /// Get devices that are online.
  List<Device> get onlineDevices =>
      devices.where((d) => d.isEffectivelyOnline).toList();

  /// Get devices that are offline.
  List<Device> get offlineDevices => devices
      .where((d) => d.connectivityStatus == ConnectivityStatus.offline)
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
/// Subscribes to the `units` table for all telemetry and ownership updates.
/// Online/offline status is determined server-side via `is_online` column.
class RealtimeDeviceNotifier extends StateNotifier<RealtimeDeviceState> {
  RealtimeDeviceNotifier(this._ref) : super(const RealtimeDeviceState()) {
    _initialize();
  }

  final Ref _ref;
  RealtimeChannel? _unitsChannel;

  /// In-memory cache of unit data (keyed by unit ID).
  final Map<String, Map<String, dynamic>> _unitsCache = {};

  /// Initialize the realtime subscription.
  Future<void> _initialize() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      state = state.copyWith(isLoading: false);
      return;
    }

    // Fetch all devices then subscribe to realtime changes
    await _fetchDevices(userId);
    _subscribeToUnits(userId);
  }

  /// Fetch all devices for the user using the unified units + devices schema.
  Future<void> _fetchDevices(String userId) async {
    try {
      final unitRepo = _ref.read(unitRepositoryProvider);
      final devices = await unitRepo.getUserDevices(userId);

      // Populate cache from the initial fetch
      _unitsCache.clear();

      for (final device in devices) {
        _unitsCache[device.id] = {
          'id': device.id,
          'serial_number': device.serialNumber,
          'consumer_user_id': device.userId,
          'consumer_name': device.name,
          'status': device.status == DeviceStatus.setupRequired
              ? 'assigned'
              : 'claimed',
          'created_at': device.createdAt.toIso8601String(),
          // Telemetry columns (from units table)
          'last_seen_at': device.lastSeenAt?.toIso8601String(),
          'is_online': device.isOnlineDb,
          'battery_level': device.batteryLevel,
          'is_charging': device.isCharging,
          'wifi_rssi': device.wifiRssi,
          'temperature_c': device.temperatureC,
          'humidity_pct': device.humidityPct,
          'firmware_version': device.firmwareVersion,
          // Hardware info from devices join (stored inline for rebuild)
          'devices': device.macAddress != null
              ? [
                  {
                    'mac_address': device.macAddress,
                    'provision_data': device.provisionData,
                  }
                ]
              : [],
        };
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
  /// Units are filtered by consumer_user_id to only receive changes for the
  /// current user's devices. All telemetry updates (battery, online status,
  /// wifi signal, etc.) arrive through this single subscription.
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

  /// Handle a new unit being claimed by the user.
  void _handleUnitInsert(Map<String, dynamic> record) {
    final unitId = record['id'] as String?;
    if (unitId == null) return;

    // Add to cache, preserving any existing devices join data
    final existing = _unitsCache[unitId];
    _unitsCache[unitId] = {
      ...record,
      'devices': existing?['devices'] ?? [],
    };

    _rebuildDeviceState();
  }

  /// Handle an existing unit being updated (telemetry, name, status, etc.).
  void _handleUnitUpdate(
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) {
    final unitId = newRecord['id'] as String?;
    if (unitId == null) return;

    // Preserve devices join data from cache
    final existing = _unitsCache[unitId];
    _unitsCache[unitId] = {
      ...newRecord,
      'devices': existing?['devices'] ?? [],
    };

    _rebuildDeviceState();
    _checkForNotifications(oldRecord, newRecord);
  }

  /// Handle a unit being unclaimed (deleted from user's perspective).
  void _handleUnitDelete(Map<String, dynamic> record) {
    final unitId = record['id'] as String?;
    if (unitId == null) return;

    _unitsCache.remove(unitId);
    _rebuildDeviceState();
  }

  /// Rebuild the device state from the cached units data.
  void _rebuildDeviceState() {
    final devices = <Device>[];

    for (final unitData in _unitsCache.values) {
      try {
        devices.add(Device.fromJoinedJson(unitData));
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
  }

  /// Check if we need to send notifications for unit changes.
  void _checkForNotifications(
    Map<String, dynamic> oldRecord,
    Map<String, dynamic> newRecord,
  ) {
    final unitId = newRecord['id'] as String? ?? '';
    final deviceName =
        newRecord['consumer_name'] as String? ?? 'Unknown Device';

    // Check for offline transition
    final oldOnline = oldRecord['is_online'] as bool?;
    final newOnline = newRecord['is_online'] as bool?;
    if (oldOnline == true && newOnline == false) {
      _sendDeviceOfflineNotification(unitId, deviceName);
    }

    // Check battery level
    final oldBattery = oldRecord['battery_level'] as int?;
    final newBattery = newRecord['battery_level'] as int?;
    if (newBattery != null && newBattery < 20) {
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
    _unitsChannel?.unsubscribe();
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

/// Provider for realtime online devices.
final realtimeOnlineDevicesProvider = Provider<List<Device>>((ref) {
  return ref.watch(realtimeDeviceProvider).onlineDevices;
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
