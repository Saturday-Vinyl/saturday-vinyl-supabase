import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/models/device_command.dart';
import 'package:saturday_app/models/remote_log_entry.dart';
import 'package:saturday_app/providers/device_provider.dart';
import 'package:saturday_app/providers/unit_dashboard_provider.dart';
import 'package:saturday_app/repositories/device_command_repository.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

// ============================================================================
// State Model
// ============================================================================

/// State for the remote monitor feature
class RemoteMonitorState extends Equatable {
  /// Unit being monitored
  final String? unitId;

  /// Devices being monitored (MAC addresses)
  final List<Device> devices;

  /// Log entries (heartbeats + commands)
  final List<RemoteLogEntry> logEntries;

  /// Whether subscriptions are active
  final bool isSubscribed;

  /// Error message if any
  final String? error;

  /// Track pending commands by ID
  final Set<String> pendingCommandIds;

  const RemoteMonitorState({
    this.unitId,
    this.devices = const [],
    this.logEntries = const [],
    this.isSubscribed = false,
    this.error,
    this.pendingCommandIds = const {},
  });

  /// Check if any device has websocket capability
  bool get hasWebsocketCapability => devices.isNotEmpty;

  /// Get MAC addresses of all devices
  List<String> get macAddresses => devices.map((d) => d.macAddress).toList();

  /// Get the first device (primary) if any
  Device? get primaryDevice => devices.isNotEmpty ? devices.first : null;

  RemoteMonitorState copyWith({
    String? unitId,
    List<Device>? devices,
    List<RemoteLogEntry>? logEntries,
    bool? isSubscribed,
    String? error,
    bool clearError = false,
    Set<String>? pendingCommandIds,
  }) {
    return RemoteMonitorState(
      unitId: unitId ?? this.unitId,
      devices: devices ?? this.devices,
      logEntries: logEntries ?? this.logEntries,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      error: clearError ? null : (error ?? this.error),
      pendingCommandIds: pendingCommandIds ?? this.pendingCommandIds,
    );
  }

  @override
  List<Object?> get props => [
        unitId,
        devices,
        logEntries,
        isSubscribed,
        error,
        pendingCommandIds,
      ];
}

// ============================================================================
// Repository Provider
// ============================================================================

/// Provider for DeviceCommandRepository singleton
final deviceCommandRepositoryProvider = Provider<DeviceCommandRepository>((ref) {
  return DeviceCommandRepository();
});

// ============================================================================
// Remote Monitor Provider
// ============================================================================

/// Provider for remote device monitoring, scoped by unit ID
final remoteMonitorProvider =
    StateNotifierProvider.family<RemoteMonitorNotifier, RemoteMonitorState, String>(
        (ref, unitId) {
  return RemoteMonitorNotifier(ref, unitId);
});

/// StateNotifier for managing remote device monitoring
class RemoteMonitorNotifier extends StateNotifier<RemoteMonitorState> {
  final Ref ref;
  final String unitId;

  RealtimeChannel? _heartbeatsChannel;
  RealtimeChannel? _commandsChannel;

  /// Maximum number of log entries to keep
  static const int maxLogEntries = 500;

  RemoteMonitorNotifier(this.ref, this.unitId) : super(const RemoteMonitorState());

  /// Initialize with devices for the unit
  Future<void> initialize(List<Device> devices) async {
    state = state.copyWith(
      unitId: unitId,
      devices: devices,
      clearError: true,
    );
    AppLogger.info(
        'Remote monitor initialized for unit $unitId with ${devices.length} devices');
  }

  /// Start monitoring (subscribe to realtime channels)
  Future<void> startMonitoring() async {
    if (state.isSubscribed) {
      AppLogger.debug('Remote monitor already subscribed');
      return;
    }

    final macAddresses = state.macAddresses;
    if (macAddresses.isEmpty) {
      state = state.copyWith(
        error: 'No devices to monitor',
      );
      return;
    }

    try {
      final realtimeService = ref.read(realtimeServiceProvider);

      AppLogger.info(
          'Starting remote monitor for ${macAddresses.length} devices');

      // Load recent history first
      await _loadRecentHistory();

      // Subscribe to heartbeats
      _heartbeatsChannel = realtimeService.subscribeToHeartbeatsByMacs(
        macAddresses: macAddresses,
        onInsert: _handleHeartbeat,
      );

      // Subscribe to commands
      _commandsChannel = realtimeService.subscribeToCommandsByMacs(
        macAddresses: macAddresses,
        onInsert: _handleCommandInsert,
        onUpdate: _handleCommandUpdate,
      );

      state = state.copyWith(
        isSubscribed: true,
        clearError: true,
      );

      AppLogger.info('Remote monitor subscriptions active');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to start remote monitoring', error, stackTrace);
      state = state.copyWith(
        error: 'Failed to connect: $error',
      );
    }
  }

  /// Stop monitoring (unsubscribe from realtime channels)
  Future<void> stopMonitoring() async {
    if (!state.isSubscribed) return;

    final realtimeService = ref.read(realtimeServiceProvider);

    if (_heartbeatsChannel != null) {
      await realtimeService.unsubscribe(_heartbeatsChannel!);
      _heartbeatsChannel = null;
    }

    if (_commandsChannel != null) {
      await realtimeService.unsubscribe(_commandsChannel!);
      _commandsChannel = null;
    }

    state = state.copyWith(isSubscribed: false);
    AppLogger.info('Remote monitor subscriptions stopped');
  }

  /// Load recent history from database
  Future<void> _loadRecentHistory() async {
    try {
      final macAddresses = state.macAddresses;
      if (macAddresses.isEmpty) return;

      final supabase = SupabaseService.instance.client;

      // Load recent heartbeats (last hour)
      final since = DateTime.now().subtract(const Duration(hours: 1));

      final heartbeatsResponse = await supabase
          .from('device_heartbeats')
          .select()
          .inFilter('mac_address', macAddresses)
          .gte('received_at', since.toIso8601String())
          .order('received_at', ascending: false)
          .limit(100);

      final heartbeatEntries = (heartbeatsResponse as List)
          .map((json) =>
              RemoteLogEntry.fromHeartbeat(json as Map<String, dynamic>))
          .toList();

      // Load recent commands (last hour)
      final commandsResponse = await supabase
          .from('device_commands')
          .select()
          .inFilter('mac_address', macAddresses)
          .gte('created_at', since.toIso8601String())
          .order('created_at', ascending: false)
          .limit(100);

      final commandEntries = (commandsResponse as List)
          .map((json) =>
              RemoteLogEntry.fromCommand(json as Map<String, dynamic>))
          .toList();

      // Merge and sort by timestamp
      final allEntries = [...heartbeatEntries, ...commandEntries];
      allEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      // Keep only most recent
      final trimmedEntries = allEntries.length > maxLogEntries
          ? allEntries.sublist(allEntries.length - maxLogEntries)
          : allEntries;

      state = state.copyWith(logEntries: trimmedEntries);

      AppLogger.info(
          'Loaded ${trimmedEntries.length} history entries (${heartbeatEntries.length} heartbeats, ${commandEntries.length} commands)');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to load history', error, stackTrace);
    }
  }

  void _handleHeartbeat(PostgresChangePayload payload) {
    final entry = RemoteLogEntry.fromHeartbeat(payload.newRecord);
    _addLogEntry(entry);

    // If this is a command ack, update pending commands
    if (entry.type == RemoteLogEntryType.commandAck ||
        entry.type == RemoteLogEntryType.commandResult) {
      if (entry.commandId != null) {
        final newPending = Set<String>.from(state.pendingCommandIds);
        newPending.remove(entry.commandId);
        state = state.copyWith(pendingCommandIds: newPending);
      }
    }
  }

  void _handleCommandInsert(PostgresChangePayload payload) {
    final entry = RemoteLogEntry.fromCommand(payload.newRecord);
    _addLogEntry(entry);
  }

  void _handleCommandUpdate(PostgresChangePayload payload) {
    // Update existing command entry with new status
    final commandId = payload.newRecord['id'] as String?;
    if (commandId == null) return;

    final status =
        DeviceCommandStatusExtension.fromString(payload.newRecord['status'] as String?);

    // Find and update the existing entry, or add a new one for status change
    final existingIndex =
        state.logEntries.indexWhere((e) => e.commandId == commandId);

    if (existingIndex >= 0) {
      // Update existing entry
      final existingEntry = state.logEntries[existingIndex];
      final updatedEntry = RemoteLogEntry(
        id: existingEntry.id,
        type: status == DeviceCommandStatus.completed ||
                status == DeviceCommandStatus.failed
            ? RemoteLogEntryType.commandResult
            : status == DeviceCommandStatus.acknowledged
                ? RemoteLogEntryType.commandAck
                : existingEntry.type,
        timestamp: existingEntry.timestamp,
        macAddress: existingEntry.macAddress,
        commandId: commandId,
        command: existingEntry.command,
        commandStatus: status,
        data: {
          ...existingEntry.data,
          if (payload.newRecord['result'] != null)
            'result': payload.newRecord['result'],
          if (payload.newRecord['error_message'] != null)
            'error_message': payload.newRecord['error_message'],
        },
      );

      final updatedEntries = List<RemoteLogEntry>.from(state.logEntries);
      updatedEntries[existingIndex] = updatedEntry;
      state = state.copyWith(logEntries: updatedEntries);
    }

    // Update pending commands
    if (status.index >= DeviceCommandStatus.acknowledged.index) {
      final newPending = Set<String>.from(state.pendingCommandIds);
      newPending.remove(commandId);
      state = state.copyWith(pendingCommandIds: newPending);
    }
  }

  void _addLogEntry(RemoteLogEntry entry) {
    final updatedEntries = [...state.logEntries, entry];

    // Trim if too many entries
    final trimmedEntries = updatedEntries.length > maxLogEntries
        ? updatedEntries.sublist(updatedEntries.length - maxLogEntries)
        : updatedEntries;

    state = state.copyWith(logEntries: trimmedEntries);
  }

  /// Clear all log entries
  void clearLogs() {
    state = state.copyWith(logEntries: []);
  }

  /// Send a command to a device
  Future<DeviceCommand?> sendCommand({
    required String macAddress,
    required String command,
    String? capability,
    String? testName,
    Map<String, dynamic>? parameters,
  }) async {
    try {
      final repository = ref.read(deviceCommandRepositoryProvider);

      final deviceCommand = await repository.sendCommand(
        macAddress: macAddress,
        command: command,
        capability: capability,
        testName: testName,
        parameters: parameters,
      );

      // Track as pending
      final newPending = Set<String>.from(state.pendingCommandIds);
      newPending.add(deviceCommand.id);
      state = state.copyWith(pendingCommandIds: newPending);

      AppLogger.info('Sent command ${deviceCommand.id}: $command');
      return deviceCommand;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to send command', error, stackTrace);
      state = state.copyWith(error: 'Failed to send command: $error');
      return null;
    }
  }

  /// Send get_status command to primary device
  Future<DeviceCommand?> sendGetStatus() async {
    final device = state.primaryDevice;
    if (device == null) return null;
    return sendCommand(macAddress: device.macAddress, command: 'get_status');
  }

  /// Send reboot command
  Future<DeviceCommand?> sendReboot(String macAddress) async {
    return sendCommand(macAddress: macAddress, command: 'reboot');
  }

  /// Send consumer_reset command
  Future<DeviceCommand?> sendConsumerReset(String macAddress) async {
    return sendCommand(macAddress: macAddress, command: 'consumer_reset');
  }

  /// Send factory_reset command
  Future<DeviceCommand?> sendFactoryReset(String macAddress) async {
    return sendCommand(macAddress: macAddress, command: 'factory_reset');
  }

  /// Send run_test command
  Future<DeviceCommand?> sendRunTest({
    required String macAddress,
    required String capability,
    required String testName,
    Map<String, dynamic>? parameters,
  }) async {
    return sendCommand(
      macAddress: macAddress,
      command: 'run_test',
      capability: capability,
      testName: testName,
      parameters: parameters,
    );
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

// ============================================================================
// Helper Providers
// ============================================================================

/// Provider to check if a device type has websocket capability
final deviceTypeHasWebsocketProvider =
    FutureProvider.family<bool, String>((ref, deviceTypeSlug) async {
  // Get capabilities for device type via slug
  final supabase = SupabaseService.instance.client;

  // Query device_types by slug and join to get capabilities
  final response = await supabase
      .from('device_types')
      .select('device_type_capabilities(capabilities(name))')
      .eq('slug', deviceTypeSlug)
      .maybeSingle();

  if (response == null) return false;

  final dtCaps = response['device_type_capabilities'] as List? ?? [];
  final capabilities = dtCaps
      .map((row) => (row['capabilities'] as Map)['name'] as String)
      .toList();

  return capabilities.contains('websocket');
});

/// Provider to get devices with websocket capability for a unit
final unitDevicesWithWebsocketProvider =
    FutureProvider.family<List<Device>, String>((ref, unitId) async {
  // Get devices for unit
  final devices = await ref.watch(devicesByUnitProvider(unitId).future);

  // Filter to devices with websocket capability
  final devicesWithWebsocket = <Device>[];

  for (final device in devices) {
    if (device.deviceTypeSlug == null) continue;

    final hasWebsocket =
        await ref.watch(deviceTypeHasWebsocketProvider(device.deviceTypeSlug!).future);
    if (hasWebsocket) {
      devicesWithWebsocket.add(device);
    }
  }

  return devicesWithWebsocket;
});
