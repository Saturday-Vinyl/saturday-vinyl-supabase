import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:saturday_consumer_app/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Table name for devices.
const _tableName = 'consumer_devices';

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
class RealtimeDeviceNotifier extends StateNotifier<RealtimeDeviceState> {
  RealtimeDeviceNotifier(this._ref) : super(const RealtimeDeviceState()) {
    _initialize();
  }

  final Ref _ref;
  RealtimeChannel? _channel;
  Timer? _stalenessCheckTimer;

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

    // First fetch all devices
    await _fetchDevices(userId);

    // Then subscribe to realtime changes
    _subscribeToDevices(userId);

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

  /// Fetch all devices for the user.
  Future<void> _fetchDevices(String userId) async {
    try {
      final deviceRepo = _ref.read(deviceRepositoryProvider);
      final devices = await deviceRepo.getUserDevices(userId);

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

  /// Subscribe to realtime device changes.
  void _subscribeToDevices(String userId) {
    final client = _ref.read(supabaseClientProvider);

    _channel = client
        .channel('devices_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: _tableName,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _handleRealtimePayload(payload);
          },
        )
        .subscribe();
  }

  /// Handle incoming realtime payloads.
  void _handleRealtimePayload(PostgresChangePayload payload) {
    switch (payload.eventType) {
      case PostgresChangeEvent.insert:
        _handleInsert(payload.newRecord);
        break;
      case PostgresChangeEvent.update:
        _handleUpdate(payload.newRecord, payload.oldRecord);
        break;
      case PostgresChangeEvent.delete:
        _handleDelete(payload.oldRecord);
        break;
      default:
        break;
    }
  }

  /// Handle a new device being inserted.
  void _handleInsert(Map<String, dynamic> record) {
    final device = Device.fromJson(record);
    final devices = [...state.devices, device];

    state = state.copyWith(
      devices: devices,
      lastUpdated: DateTime.now(),
    );
  }

  /// Handle an existing device being updated.
  void _handleUpdate(
    Map<String, dynamic> newRecord,
    Map<String, dynamic> oldRecord,
  ) {
    final updatedDevice = Device.fromJson(newRecord);
    final devices = state.devices.map((device) {
      if (device.id == updatedDevice.id) {
        return updatedDevice;
      }
      return device;
    }).toList();

    state = state.copyWith(
      devices: devices,
      lastUpdated: DateTime.now(),
    );

    // If device received a heartbeat (lastSeenAt updated), it's back online
    // Clear it from the notified set so we can notify again if it goes offline
    if (updatedDevice.isEffectivelyOnline) {
      _notifiedOfflineDevices.remove(updatedDevice.id);
    }

    // Check for status/battery changes and trigger notifications
    _checkForNotifications(oldRecord, newRecord);
  }

  /// Handle a device being deleted.
  void _handleDelete(Map<String, dynamic> record) {
    final deletedId = record['id'] as String?;
    if (deletedId == null) return;

    final devices =
        state.devices.where((device) => device.id != deletedId).toList();

    state = state.copyWith(
      devices: devices,
      lastUpdated: DateTime.now(),
    );
  }

  /// Check if we need to send notifications for device changes.
  void _checkForNotifications(
    Map<String, dynamic> oldRecord,
    Map<String, dynamic> newRecord,
  ) {
    final oldStatus = DeviceStatus.fromString(oldRecord['status'] as String? ?? 'offline');
    final newStatus = DeviceStatus.fromString(newRecord['status'] as String? ?? 'offline');
    final deviceName = newRecord['name'] as String? ?? 'Unknown Device';
    final deviceId = newRecord['id'] as String? ?? '';

    // Device went offline
    if (oldStatus == DeviceStatus.online && newStatus == DeviceStatus.offline) {
      _sendDeviceOfflineNotification(deviceId, deviceName);
    }

    // Battery level changed to low
    final oldBattery = oldRecord['battery_level'] as int?;
    final newBattery = newRecord['battery_level'] as int?;

    if (newBattery != null && newBattery < 20) {
      // Only notify if it just dropped below 20%
      if (oldBattery == null || oldBattery >= 20) {
        _sendLowBatteryNotification(deviceId, deviceName, newBattery);
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
    _channel?.unsubscribe();
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
