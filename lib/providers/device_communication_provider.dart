import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/connected_device.dart';
import 'package:saturday_app/models/device_communication_state.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/models/usb_monitor_state.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/capability_provider.dart';
import 'package:saturday_app/providers/device_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
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
      final unit = await unitRepository.getUnitBySerialNumber(serialNumber);

      if (unit != null) {
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

        // Validate response data against expected factory_output schema
        // This MUST pass before we consider provisioning successful
        final validationResult = await _validateFactoryOutput(
          deviceTypeSlug: state.connectedDevice!.deviceType,
          responseData: response.data,
        );

        if (!validationResult.isValid) {
          _addLog('[ERROR] Factory output validation failed');
          for (final field in validationResult.missingRequired) {
            _addLog('[ERROR] Missing required field: $field');
          }
          for (final field in validationResult.missingOptional) {
            _addLog('[WARN] Missing optional field: $field');
          }

          state = state.copyWith(
            phase: DeviceCommunicationPhase.error,
            errorMessage:
                'Device response missing required fields: ${validationResult.missingRequired.join(', ')}',
            clearCurrentCommand: true,
          );
          return false;
        }

        _addLog('[INFO] Factory output validated: all required fields present');
        if (validationResult.missingOptional.isNotEmpty) {
          _addLog(
              '[WARN] Missing optional fields: ${validationResult.missingOptional.join(', ')}');
        }

        // Build provision data from device response ONLY (not input params)
        // The firmware JSON schema defines what the device returns in factory_output
        final provisionData = Map<String, dynamic>.from(response.data);
        // Remove serial_number and name - tracked in units table, not provision_data
        provisionData.remove('serial_number');
        provisionData.remove('name');

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
            provisionData: provisionData,
            status: 'factory_provisioned',
          );
          _addLog('[INFO] Device record created/updated in database');
          _addLog('[INFO] Provision data stored: ${provisionData.keys.join(', ')}');
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

  /// Validate factory_provision response data against expected factory_output schemas.
  ///
  /// Looks up the device type's capabilities and checks that all expected
  /// properties from factory_output schemas are present in the response.
  /// Returns a validation result indicating success/failure and any missing fields.
  Future<_FactoryOutputValidationResult> _validateFactoryOutput({
    required String deviceTypeSlug,
    required Map<String, dynamic> responseData,
  }) async {
    try {
      // Look up device type to get its ID
      final capabilityRepo = _ref.read(capabilityRepositoryProvider);
      final deviceTypeRepo = _ref.read(deviceTypeRepositoryProvider);

      final deviceType = await deviceTypeRepo.getBySlug(deviceTypeSlug);
      final capabilities =
          await capabilityRepo.getCapabilitiesForDeviceType(deviceType.id);

      final missingRequired = <String>[];
      final missingOptional = <String>[];

      for (final cap in capabilities) {
        if (!cap.hasFactoryOutput) continue;

        final schema = cap.factoryOutputSchema;
        final properties = schema['properties'] as Map<String, dynamic>?;
        if (properties == null) continue;

        final requiredFields =
            (schema['required'] as List?)?.cast<String>() ?? [];

        for (final key in properties.keys) {
          if (!responseData.containsKey(key)) {
            if (requiredFields.contains(key)) {
              missingRequired.add('${cap.name}.$key');
            } else {
              missingOptional.add('${cap.name}.$key');
            }
          }
        }
      }

      return _FactoryOutputValidationResult(
        missingRequired: missingRequired,
        missingOptional: missingOptional,
      );
    } catch (e) {
      _addLog('[WARN] Could not validate factory output schema: $e');
      // If validation fails due to lookup error, allow provisioning to continue
      // but log the issue - we don't want to block provisioning if the admin
      // app's capability config is incomplete
      return const _FactoryOutputValidationResult(
        missingRequired: [],
        missingOptional: [],
      );
    }
  }

  /// Run a capability command
  Future<CommandResult> runCommand(
    String commandName, {
    Map<String, dynamic>? params,
  }) async {
    if (!state.phase.canSendCommands) {
      return CommandResult(
        commandName: commandName,
        passed: false,
        message: 'Not connected',
        duration: Duration.zero,
      );
    }

    state = state.copyWith(
      phase: DeviceCommunicationPhase.executing,
      currentCommand: commandName,
    );

    final startTime = DateTime.now();
    final response = await _service.runCapabilityCommand(commandName, params: params);
    final duration = DateTime.now().difference(startTime);

    final result = CommandResult.fromResponse(commandName, response, duration);

    state = state
        .copyWith(
          phase: DeviceCommunicationPhase.connected,
          clearCurrentCommand: true,
        )
        .addCommandResult(result);

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
// Validation Result Types
// ============================================

/// Result of validating factory_provision response against expected schemas
class _FactoryOutputValidationResult {
  final List<String> missingRequired;
  final List<String> missingOptional;

  const _FactoryOutputValidationResult({
    required this.missingRequired,
    required this.missingOptional,
  });

  /// Validation passes if no required fields are missing
  bool get isValid => missingRequired.isEmpty;
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
