import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/connected_device.dart';
import 'package:saturday_app/models/device_communication_state.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/models/usb_monitor_state.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/device_provider.dart';
import 'package:saturday_app/providers/unit_provider.dart';
import 'package:saturday_app/services/device_communication_service.dart';
import 'package:saturday_app/services/usb_monitor_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

// ============================================
// USB Monitor Providers
// ============================================

/// Provider for USBMonitorService singleton
final usbMonitorServiceProvider = Provider<USBMonitorService>((ref) {
  final service = USBMonitorService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for USB monitor state
final usbMonitorProvider =
    StateNotifierProvider<USBMonitorNotifier, USBMonitorState>((ref) {
  final service = ref.watch(usbMonitorServiceProvider);
  return USBMonitorNotifier(service, ref);
});

/// State notifier for USB monitoring
class USBMonitorNotifier extends StateNotifier<USBMonitorState> {
  final USBMonitorService _service;
  final Ref _ref;
  StreamSubscription? _eventSubscription;

  USBMonitorNotifier(this._service, this._ref) : super(const USBMonitorState());

  /// Start monitoring for USB devices
  Future<void> startMonitoring() async {
    if (state.isMonitoring) return;

    state = state.copyWith(isMonitoring: true, clearError: true);

    // Subscribe to events
    _eventSubscription = _service.eventStream.listen(_handleEvent);

    // Start the service
    await _service.startMonitoring();

    // Update state with any devices found
    state = state.copyWith(
      connectedDevices: _service.connectedDevices,
      lastScanAt: DateTime.now(),
    );
  }

  /// Stop monitoring
  void stopMonitoring() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
    _service.stopMonitoring();
    state = const USBMonitorState();
  }

  /// Force refresh of connected devices
  Future<void> refreshDevices() async {
    if (!state.isMonitoring) return;

    await _service.refreshDevices();
    state = state.copyWith(
      connectedDevices: _service.connectedDevices,
      lastScanAt: DateTime.now(),
    );
  }

  void _handleEvent(USBDeviceEvent event) {
    switch (event.type) {
      case USBDeviceEventType.deviceIdentified:
        if (event.device != null) {
          state = state.withDevice(event.device!);
          AppLogger.info(
              'USB device identified: ${event.device!.deviceType} on ${event.portName}');
        }
        break;

      case USBDeviceEventType.deviceDisconnected:
        state = state.withoutDevice(event.portName);
        AppLogger.info('USB device disconnected: ${event.portName}');
        break;

      case USBDeviceEventType.portRemoved:
        // Device already removed in deviceDisconnected, but ensure cleanup
        if (state.connectedDevices.containsKey(event.portName)) {
          state = state.withoutDevice(event.portName);
        }
        break;

      case USBDeviceEventType.identificationFailed:
        // Not a Saturday device, nothing to do
        break;

      case USBDeviceEventType.portAdded:
        // Will be followed by deviceIdentified or identificationFailed
        break;
    }

    state = state.copyWith(lastScanAt: DateTime.now());
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for connected devices list
final connectedDevicesProvider = Provider<List<ConnectedDevice>>((ref) {
  final state = ref.watch(usbMonitorProvider);
  return state.devices;
});

/// Provider for number of connected devices
final connectedDeviceCountProvider = Provider<int>((ref) {
  return ref.watch(usbMonitorProvider).deviceCount;
});

/// Provider for checking if any devices are connected
final hasConnectedDevicesProvider = Provider<bool>((ref) {
  return ref.watch(usbMonitorProvider).hasDevices;
});

// ============================================
// Device Communication Providers
// ============================================

/// Provider for DeviceCommunicationService singleton
final deviceCommunicationServiceProvider =
    Provider<DeviceCommunicationService>((ref) {
  final service = DeviceCommunicationService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for device communication state
final deviceCommunicationStateProvider = StateNotifierProvider<
    DeviceCommunicationNotifier, DeviceCommunicationState>((ref) {
  return DeviceCommunicationNotifier(ref);
});

/// State notifier for device communication session
class DeviceCommunicationNotifier
    extends StateNotifier<DeviceCommunicationState> {
  final Ref _ref;
  StreamSubscription? _logSubscription;
  StreamSubscription? _responseSubscription;
  StreamSubscription? _connectionSubscription;

  DeviceCommunicationNotifier(this._ref)
      : super(const DeviceCommunicationState());

  DeviceCommunicationService get _service =>
      _ref.read(deviceCommunicationServiceProvider);

  void _addLog(String line) {
    state = state.addLog(line);
  }

  // ============================================
  // Connection Management
  // ============================================

  /// Connect to a device on the specified port
  ///
  /// This opens the serial port and keeps it open for communication.
  /// If get_status succeeds, device info will be populated.
  /// If get_status fails/times out, the connection stays open for manual debugging.
  Future<bool> connectToPort(String portName) async {
    if (state.phase.canSendCommands) {
      await disconnect();
    }

    state = state.copyWith(
      phase: DeviceCommunicationPhase.connecting,
      portName: portName,
      clearErrorMessage: true,
      clearConnectedDevice: true,
      clearAssociatedUnit: true,
    );

    _setupStreamSubscriptions();

    try {
      final success = await _service.connect(portName);

      if (success) {
        _addLog('[INFO] Port opened successfully');

        // Try to get device status, but don't fail if it times out
        _addLog('[INFO] Sending get_status command...');
        final response = await _service.getStatus();

        if (response.isSuccess) {
          final device = ConnectedDevice.fromStatusResponse(
            portName: portName,
            data: response.data,
          );

          state = state.copyWith(
            phase: DeviceCommunicationPhase.connected,
            connectedDevice: device,
            lastStatusAt: DateTime.now(),
          );

          // Look up associated unit if device is provisioned
          if (device.isProvisioned && device.serialNumber != null) {
            await _lookupUnit(device.serialNumber!);
          }

          _addLog('[INFO] Connected to ${device.displayName}');
        } else {
          // get_status failed or timed out, but keep connection open
          _addLog('[WARN] get_status failed: ${response.message ?? "timeout"}');
          _addLog('[INFO] Connection remains open for manual debugging');

          state = state.copyWith(
            phase: DeviceCommunicationPhase.connected,
            // No device info since get_status didn't work
          );
        }

        return true;
      } else {
        state = state.copyWith(
          phase: DeviceCommunicationPhase.error,
          errorMessage: 'Failed to open port',
        );
        return false;
      }
    } catch (e) {
      _addLog('[ERROR] Connection failed: $e');
      state = state.copyWith(
        phase: DeviceCommunicationPhase.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Connect to a device that was detected by USB monitor
  Future<bool> connectToDevice(ConnectedDevice device) async {
    return connectToPort(device.portName);
  }

  /// Disconnect from current device
  Future<void> disconnect() async {
    await _service.disconnect();
    _cancelSubscriptions();
    state = const DeviceCommunicationState();
  }

  void _setupStreamSubscriptions() {
    _cancelSubscriptions();

    _logSubscription = _service.rawLogStream.listen((line) {
      _addLog(line);
    });

    _connectionSubscription = _service.connectionStateStream.listen((connected) {
      if (!connected && state.phase != DeviceCommunicationPhase.disconnected) {
        state = state.copyWith(
          phase: DeviceCommunicationPhase.disconnected,
          clearConnectedDevice: true,
        );
      }
    });
  }

  void _cancelSubscriptions() {
    _logSubscription?.cancel();
    _logSubscription = null;
    _responseSubscription?.cancel();
    _responseSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
  }

  // ============================================
  // Unit Management
  // ============================================

  Future<void> _lookupUnit(String serialNumber) async {
    try {
      final unitRepository = _ref.read(unitRepositoryProvider);
      final foundUnit = await unitRepository.getUnitBySerialNumber(serialNumber);

      if (foundUnit != null) {
        var unit = foundUnit;

        // Check if database status is out of sync with device
        // Device has a serial number, so it's provisioned - but database might say 'unprovisioned'
        if (unit.status == UnitStatus.unprovisioned) {
          _addLog('[INFO] Device is provisioned but database shows unprovisioned - syncing status...');

          try {
            // Get current user to record who triggered the sync
            final currentUser = await _ref.read(currentUserProvider.future);
            final userId = currentUser?.id ?? 'system';

            // Update unit status to match device reality
            final unitManagement = _ref.read(unitManagementProvider);
            unit = await unitManagement.markFactoryProvisioned(
              unitId: unit.id,
              userId: userId,
            );
            _addLog('[INFO] Database status synced to factory_provisioned');
          } catch (e) {
            _addLog('[WARN] Could not sync status to database: $e');
            // Continue with the original unit data
          }
        }

        state = state.copyWith(associatedUnit: unit, unitNotFoundInDb: false);
        _addLog('[INFO] Found unit: ${unit.displayName} (status: ${unit.status.name})');
      } else {
        state = state.copyWith(unitNotFoundInDb: true);
        _addLog('[WARN] Unit $serialNumber not found in database');
      }
    } catch (e) {
      _addLog('[ERROR] Failed to look up unit: $e');
    }
  }

  /// Set unit for provisioning
  void setUnitForProvisioning(Unit unit) {
    state = state.copyWith(associatedUnit: unit);
    _addLog('[INFO] Selected unit for provisioning: ${unit.serialNumber}');
  }

  /// Clear associated unit
  void clearAssociatedUnit() {
    state = state.copyWith(clearAssociatedUnit: true);
  }

  // ============================================
  // Commands
  // ============================================

  /// Refresh device status
  Future<void> refreshStatus() async {
    if (!state.phase.canSendCommands) {
      _addLog('[ERROR] Not connected');
      return;
    }

    final response = await _service.getStatus();
    if (response.isSuccess && state.connectedDevice != null) {
      final updatedDevice =
          state.connectedDevice!.copyWithStatus(response.data);
      state = state.copyWith(
        connectedDevice: updatedDevice,
        lastStatusAt: DateTime.now(),
      );
    }
  }

  /// Factory provision the device
  Future<bool> factoryProvision({
    String? cloudUrl,
    String? cloudAnonKey,
    Map<String, dynamic>? additionalParams,
  }) async {
    if (!state.canProvision) {
      _addLog('[ERROR] Cannot provision: device not connected or already provisioned');
      return false;
    }

    if (state.associatedUnit == null) {
      _addLog('[ERROR] No unit selected for provisioning');
      return false;
    }

    state = state.copyWith(
      phase: DeviceCommunicationPhase.executing,
      currentCommand: 'factory_provision',
    );

    try {
      final unit = state.associatedUnit!;

      // Ensure unit has a serial number
      if (unit.serialNumber == null) {
        _addLog('[ERROR] Unit does not have a serial number');
        return false;
      }

      // Get cloud credentials from environment if not provided
      final effectiveCloudUrl = cloudUrl ?? dotenv.env['SUPABASE_URL'];
      final effectiveAnonKey = cloudAnonKey ?? dotenv.env['SUPABASE_ANON_KEY'];

      final params = FactoryProvisionParams(
        serialNumber: unit.serialNumber!,
        name: unit.displayName,
        cloudUrl: effectiveCloudUrl,
        cloudAnonKey: effectiveAnonKey,
        additionalParams: additionalParams ?? {},
      );

      final response = await _service.factoryProvision(params);

      if (response.isSuccess) {
        // Refresh status to get updated device info
        await refreshStatus();

        // Create or update device record in database
        try {
          final deviceManagement = _ref.read(deviceManagementProvider);
          final currentUser = await _ref.read(currentUserProvider.future);

          await deviceManagement.upsertDevice(
            macAddress: state.connectedDevice!.macAddress,
            deviceTypeSlug: state.connectedDevice!.deviceType,
            unitId: unit.id,
            firmwareVersion: state.connectedDevice!.firmwareVersion,
            factoryProvisionedAt: DateTime.now(),
            factoryProvisionedBy: currentUser?.id,
            status: 'factory_provisioned',
          );
          _addLog('[INFO] Device record created/updated in database');
        } catch (e) {
          _addLog('[WARN] Failed to create device record: $e');
          // Don't fail provisioning - device record is for tracking
        }

        state = state.copyWith(
          phase: DeviceCommunicationPhase.connected,
          clearCurrentCommand: true,
        );

        _addLog('[SUCCESS] Device provisioned as ${unit.serialNumber}');
        return true;
      } else {
        state = state.copyWith(
          phase: DeviceCommunicationPhase.error,
          errorMessage: 'Provisioning failed: ${response.message}',
          clearCurrentCommand: true,
        );
        return false;
      }
    } catch (e) {
      _addLog('[ERROR] Provisioning failed: $e');
      state = state.copyWith(
        phase: DeviceCommunicationPhase.error,
        errorMessage: e.toString(),
        clearCurrentCommand: true,
      );
      return false;
    }
  }

  /// Run a capability test
  Future<TestResult> runTest(
    String capability,
    String testName, {
    Map<String, dynamic>? params,
  }) async {
    if (!state.phase.canSendCommands) {
      return TestResult(
        capability: capability,
        testName: testName,
        passed: false,
        message: 'Not connected',
        duration: Duration.zero,
      );
    }

    state = state.copyWith(
      phase: DeviceCommunicationPhase.executing,
      currentCommand: 'run_test:$capability:$testName',
    );

    final startTime = DateTime.now();
    final response = await _service.runTest(capability, testName, params: params);
    final duration = DateTime.now().difference(startTime);

    final result = TestResult.fromResponse(capability, testName, response, duration);

    state = state
        .copyWith(
          phase: DeviceCommunicationPhase.connected,
          clearCurrentCommand: true,
        )
        .addTestResult(result);

    return result;
  }

  /// Consumer reset
  Future<bool> consumerReset() async {
    if (!state.phase.canSendCommands) {
      _addLog('[ERROR] Not connected');
      return false;
    }

    state = state.copyWith(
      phase: DeviceCommunicationPhase.executing,
      currentCommand: 'consumer_reset',
    );

    final response = await _service.consumerReset();

    if (response.isSuccess) {
      // Device may reboot, disconnect
      await disconnect();
      return true;
    } else {
      state = state.copyWith(
        phase: DeviceCommunicationPhase.error,
        errorMessage: 'Consumer reset failed: ${response.message}',
        clearCurrentCommand: true,
      );
      return false;
    }
  }

  /// Factory reset
  Future<bool> factoryReset() async {
    if (!state.phase.canSendCommands) {
      _addLog('[ERROR] Not connected');
      return false;
    }

    state = state.copyWith(
      phase: DeviceCommunicationPhase.executing,
      currentCommand: 'factory_reset',
    );

    final response = await _service.factoryReset();

    if (response.isSuccess) {
      // Device will reboot, disconnect
      await disconnect();
      return true;
    } else {
      state = state.copyWith(
        phase: DeviceCommunicationPhase.error,
        errorMessage: 'Factory reset failed: ${response.message}',
        clearCurrentCommand: true,
      );
      return false;
    }
  }

  /// Reboot device
  Future<bool> reboot() async {
    if (!state.phase.canSendCommands) {
      _addLog('[ERROR] Not connected');
      return false;
    }

    state = state.copyWith(
      phase: DeviceCommunicationPhase.executing,
      currentCommand: 'reboot',
    );

    final response = await _service.reboot();

    if (response.isSuccess) {
      // Device will reboot, disconnect
      await disconnect();
      return true;
    } else {
      state = state.copyWith(
        phase: DeviceCommunicationPhase.error,
        errorMessage: 'Reboot failed: ${response.message}',
        clearCurrentCommand: true,
      );
      return false;
    }
  }

  // ============================================
  // Utility
  // ============================================

  /// Clear logs
  void clearLogs() {
    state = state.clearLogs();
  }

  /// Reset state for new session
  void reset() {
    _cancelSubscriptions();
    state = const DeviceCommunicationState();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _service.disconnect();
    super.dispose();
  }
}

// ============================================
// Helper Providers
// ============================================

/// Provider for currently connected device info
final currentDeviceProvider = Provider<ConnectedDevice?>((ref) {
  return ref.watch(deviceCommunicationStateProvider).connectedDevice;
});

/// Provider for current connection phase
final connectionPhaseProvider = Provider<DeviceCommunicationPhase>((ref) {
  return ref.watch(deviceCommunicationStateProvider).phase;
});

/// Provider for checking if connected to a device
final isDeviceConnectedProvider = Provider<bool>((ref) {
  return ref.watch(deviceCommunicationStateProvider).isConnected;
});

/// Provider for associated unit (if any)
final associatedUnitProvider = Provider<Unit?>((ref) {
  return ref.watch(deviceCommunicationStateProvider).associatedUnit;
});
