import 'dart:async';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/models/service_mode_manifest.dart';
import 'package:saturday_app/models/service_mode_state.dart';
import 'package:saturday_app/models/thread_credentials.dart';
import 'package:saturday_app/models/production_unit_with_consumer_info.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
import 'package:saturday_app/providers/production_unit_provider.dart';
import 'package:saturday_app/repositories/firmware_repository.dart';
import 'package:saturday_app/repositories/production_unit_repository.dart';
import 'package:saturday_app/services/esp_flash_service.dart';
import 'package:saturday_app/services/service_mode_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Provider for ServiceModeService singleton
final serviceModeServiceProvider = Provider<ServiceModeService>((ref) {
  final service = ServiceModeService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for EspFlashService singleton (reused from firmware provisioning)
final espFlashServiceProvider = Provider<EspFlashService>((ref) {
  final service = EspFlashService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider to check if esptool is available
final esptoolAvailableProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(espFlashServiceProvider);
  return await service.isEsptoolAvailable();
});

/// Provider for available serial ports
final availablePortsProvider = Provider<List<String>>((ref) {
  return SerialPort.availablePorts;
});

/// Auto-refresh provider for available serial ports
final availablePortsAutoRefreshProvider =
    StreamProvider<List<String>>((ref) async* {
  while (true) {
    yield SerialPort.availablePorts;
    await Future.delayed(const Duration(seconds: 2));
  }
});

/// Provider for port info
final portInfoProvider =
    Provider.family<Map<String, String>, String>((ref, portName) {
  final service = ref.watch(espFlashServiceProvider);
  return service.getPortInfo(portName);
});

/// Provider for units without MAC address (for fresh device assignment)
final unitsWithoutMacProvider =
    FutureProvider.family<List<ProductionUnit>, String?>((ref, productId) async {
  final repository = ref.read(productionUnitRepositoryProvider);
  return await repository.getUnitsWithoutMacAddress(productId: productId);
});

/// Provider for available Thread credentials (for non-BR device testing)
///
/// Used when testing Thread connectivity on devices that need to join an
/// existing Thread network (not border routers that create their own).
final availableThreadCredentialsProvider =
    FutureProvider<List<ThreadCredentialsWithUnit>>((ref) async {
  final repository = ref.read(productionUnitRepositoryProvider);
  return await repository.getAllThreadCredentials();
});

/// Provider for units available for provisioning (all units, with consumer device info)
///
/// Returns all incomplete production units with information about whether
/// they have a linked consumer device. Used for the new provisioning flow
/// that allows re-provisioning units that may already be linked.
final unitsForProvisioningProvider =
    FutureProvider.family<List<ProductionUnitWithConsumerInfo>, String?>(
        (ref, productId) async {
  final repository = ref.read(productionUnitRepositoryProvider);
  return await repository.getUnitsForProvisioning(productId: productId);
});

/// Provider for units by firmware ID
final unitsByFirmwareIdProvider =
    FutureProvider.family<List<ProductionUnit>, String>((ref, firmwareId) async {
  final repository = ref.read(productionUnitRepositoryProvider);
  final firmwareRepo = ref.read(firmwareRepositoryProvider);

  // Get the firmware to find its device type
  final firmware = await firmwareRepo.getFirmwareVersion(firmwareId);
  if (firmware == null) return [];

  // Get units that use products with this device type
  return await repository.getUnitsByDeviceType(firmware.deviceTypeId);
});

/// Arguments for navigating to Service Mode screen with context
class ServiceModeArgs {
  final ProductionUnit? unit;
  final ProductionStep? step;
  final FirmwareVersion? firmware;

  const ServiceModeArgs({
    this.unit,
    this.step,
    this.firmware,
  });
}

/// Main state provider for Service Mode screen
final serviceModeStateProvider =
    StateNotifierProvider<ServiceModeStateNotifier, ServiceModeState>((ref) {
  return ServiceModeStateNotifier(ref);
});

/// State notifier for Service Mode operations
class ServiceModeStateNotifier extends StateNotifier<ServiceModeState> {
  final Ref ref;

  StreamSubscription? _logSubscription;
  StreamSubscription? _beaconSubscription;
  StreamSubscription? _connectionSubscription;

  File? _downloadedFirmware;

  ServiceModeStateNotifier(this.ref) : super(ServiceModeState.initial());

  ServiceModeService get _service => ref.read(serviceModeServiceProvider);
  EspFlashService get _flashService => ref.read(espFlashServiceProvider);
  FirmwareRepository get _firmwareRepository =>
      ref.read(firmwareRepositoryProvider);
  ProductionUnitRepository get _unitRepository =>
      ref.read(productionUnitRepositoryProvider);

  // ============================================
  // Logging
  // ============================================

  void _addLog(String line) {
    state = state.addLog(line);
  }

  // ============================================
  // Device Info Merging
  // ============================================

  /// Merge beacon info with existing device info, preserving fields that
  /// beacons don't include (like thread credentials and configuration flags
  /// from get_status)
  DeviceInfo _mergeDeviceInfo(DeviceInfo? existing, DeviceInfo beacon) {
    if (existing == null) return beacon;

    // Beacon provides real-time updates for some fields, but doesn't include
    // everything that get_status provides (like thread credentials and
    // configuration flags). Beacons typically only report current connection
    // state, not configuration state.
    //
    // Configuration flags (cloudConfigured, wifiConfigured, etc.) should be
    // preserved from get_status since beacons don't reliably include them.
    // Connection state (wifiConnected, threadConnected) can be updated from
    // beacon if the beacon includes wifi/thread info.
    return DeviceInfo(
      deviceType: beacon.deviceType,
      firmwareId: beacon.firmwareId ?? existing.firmwareId,
      firmwareVersion: beacon.firmwareVersion,
      macAddress: beacon.macAddress.isNotEmpty ? beacon.macAddress : existing.macAddress,
      unitId: beacon.unitId ?? existing.unitId,
      // Preserve configuration flags - beacons don't reliably include these
      cloudConfigured: existing.cloudConfigured || beacon.cloudConfigured,
      cloudUrl: beacon.cloudUrl ?? existing.cloudUrl,
      wifiConfigured: existing.wifiConfigured || beacon.wifiConfigured,
      // Connection state can be updated by beacon if it has wifi info
      wifiConnected: beacon.wifiSsid != null ? beacon.wifiConnected : existing.wifiConnected,
      wifiSsid: beacon.wifiSsid ?? existing.wifiSsid,
      wifiRssi: beacon.wifiRssi ?? existing.wifiRssi,
      ipAddress: beacon.ipAddress ?? existing.ipAddress,
      bluetoothEnabled: beacon.bluetoothEnabled ?? existing.bluetoothEnabled,
      // Preserve thread configuration, update connection state if beacon has thread info
      threadConfigured: existing.threadConfigured ?? beacon.threadConfigured,
      threadConnected: beacon.threadConnected ?? existing.threadConnected,
      // Preserve thread credentials - beacons don't include these
      thread: existing.thread,
      freeHeap: beacon.freeHeap ?? existing.freeHeap,
      uptimeMs: beacon.uptimeMs ?? existing.uptimeMs,
      batteryLevel: beacon.batteryLevel ?? existing.batteryLevel,
      batteryCharging: beacon.batteryCharging ?? existing.batteryCharging,
      lastTests: beacon.lastTests ?? existing.lastTests,
    );
  }

  void clearLogs() {
    state = state.clearLogs();
  }

  // ============================================
  // Port Selection
  // ============================================

  void selectPort(String? port) {
    state = state.copyWith(selectedPort: port);
  }

  // ============================================
  // Connection Management
  // ============================================

  /// Connect to selected port and automatically try to enter service mode
  ///
  /// This method immediately starts spamming enter_service_mode commands
  /// after connecting, to catch the device's boot window. The device only
  /// listens for this command during the first 10 seconds after boot.
  ///
  /// Set [monitorOnly] to true to just connect and monitor logs without
  /// attempting to enter service mode.
  Future<bool> connect({bool monitorOnly = false}) async {
    if (state.selectedPort == null) {
      _addLog('[ERROR] No port selected');
      return false;
    }

    state = state.copyWith(
      phase: ServiceModePhase.connecting,
      clearErrorMessage: true,
      clearDeviceInfo: true,
      clearManifest: true,
    );

    // Set up stream subscriptions
    _setupStreamSubscriptions();

    try {
      final success = await _service.connect(state.selectedPort!);

      if (success) {
        if (monitorOnly) {
          // Monitor-only mode: just watch logs, don't enter service mode
          state = state.copyWith(
            phase: ServiceModePhase.monitoring,
          );
          _addLog('[INFO] Connected in monitor-only mode');
          _addLog('[INFO] Watching device logs (not entering service mode)');
          return true;
        }

        state = state.copyWith(
          phase: ServiceModePhase.enteringServiceMode,
        );

        // Immediately start trying to enter service mode
        // This spams enter_service_mode every 200ms for 10 seconds
        _addLog('[INFO] Connected - attempting to enter service mode...');
        _addLog('[INFO] Reboot the device now if not already booting');

        final enteredServiceMode = await _service.enterServiceMode();

        if (enteredServiceMode) {
          state = state.copyWith(
            phase: ServiceModePhase.inServiceMode,
          );

          // Get device status
          final status = await _service.getStatus();
          if (status != null) {
            state = state.copyWith(deviceInfo: status);

            // If provisioned device, look up the unit
            if (status.isProvisioned) {
              await lookupUnitFromDevice();
            }
          }

          // Get manifest
          await _fetchManifest();

          _addLog('[INFO] Device in service mode');
          return true;
        } else {
          // Failed to enter service mode - boot window may have expired
          _addLog('[WARN] Could not enter service mode - boot window may have expired');
          _addLog('[INFO] Reboot the device and try connecting again');
          state = state.copyWith(
            phase: ServiceModePhase.waitingForDevice,
          );
          return true;
        }
      } else {
        state = state.copyWith(
          phase: ServiceModePhase.error,
          errorMessage: 'Failed to connect to port',
        );
        return false;
      }
    } catch (e) {
      _addLog('[ERROR] Connection failed: $e');
      state = state.copyWith(
        phase: ServiceModePhase.error,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// Set up stream subscriptions for service
  void _setupStreamSubscriptions() {
    _logSubscription?.cancel();
    _logSubscription = _service.rawLogStream.listen((line) {
      _addLog(line);
    });

    _beaconSubscription?.cancel();
    _beaconSubscription = _service.beaconStream.listen((beaconInfo) {
      // Merge beacon info with existing device info to preserve fields
      // that beacons don't include (like thread credentials)
      final existingInfo = state.deviceInfo;
      final mergedInfo = _mergeDeviceInfo(existingInfo, beaconInfo);
      state = state.copyWith(
        deviceInfo: mergedInfo,
        lastBeaconAt: DateTime.now(),
      );
    });

    _connectionSubscription?.cancel();
    _connectionSubscription = _service.connectionStateStream.listen((connected) {
      if (!connected && state.phase != ServiceModePhase.disconnected) {
        state = state.copyWith(
          phase: ServiceModePhase.disconnected,
          clearDeviceInfo: true,
        );
      }
    });
  }

  /// Disconnect from device
  Future<void> disconnect() async {
    await _service.disconnect();
    _cancelSubscriptions();
    state = state.copyWith(
      phase: ServiceModePhase.disconnected,
      clearDeviceInfo: true,
      clearManifest: true,
    );
  }

  void _cancelSubscriptions() {
    _logSubscription?.cancel();
    _logSubscription = null;
    _beaconSubscription?.cancel();
    _beaconSubscription = null;
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
  }

  // ============================================
  // Service Mode Lifecycle
  // ============================================

  /// Enter service mode on a provisioned device
  Future<bool> enterServiceMode() async {
    if (!_service.isConnected) {
      _addLog('[ERROR] Not connected');
      return false;
    }

    state = state.copyWith(
      phase: ServiceModePhase.enteringServiceMode,
    );

    final success = await _service.enterServiceMode();

    if (success) {
      state = state.copyWith(phase: ServiceModePhase.inServiceMode);

      // Get updated status and manifest
      final status = await _service.getStatus();
      if (status != null) {
        state = state.copyWith(deviceInfo: status);
      }

      await _fetchManifest();
      return true;
    } else {
      state = state.copyWith(
        phase: ServiceModePhase.error,
        errorMessage: 'Failed to enter service mode - boot window may have expired',
      );
      return false;
    }
  }

  /// Exit service mode
  Future<bool> exitServiceMode() async {
    final success = await _service.exitServiceMode();
    if (success) {
      // Device will exit service mode, we should disconnect
      await disconnect();
    }
    return success;
  }

  /// Fetch manifest from device
  Future<void> _fetchManifest() async {
    final manifest = await _service.getManifest();
    if (manifest != null) {
      state = state.copyWith(manifest: manifest);
      _addLog('[INFO] Got device manifest: ${manifest.deviceName} v${manifest.firmwareVersion}');
    } else {
      _addLog('[WARN] Could not fetch device manifest');
    }
  }

  // ============================================
  // Unit Context Management
  // ============================================

  /// Set production unit directly (from step navigation)
  void setProductionUnit(ProductionUnit? unit) {
    state = state.copyWith(associatedUnit: unit, clearAssociatedUnit: unit == null);
    if (unit != null) {
      _addLog('[INFO] Associated with unit: ${unit.unitId}');
    }
  }

  /// Look up unit from device's unit_id
  Future<void> lookupUnitFromDevice() async {
    final deviceInfo = state.deviceInfo;
    if (deviceInfo == null || !deviceInfo.isProvisioned) {
      return;
    }

    try {
      final unit =
          await _unitRepository.getUnitBySerialNumber(deviceInfo.unitId!);
      if (unit != null) {
        state = state.copyWith(associatedUnit: unit);
        _addLog('[INFO] Found unit in database: ${unit.unitId}');
      } else {
        _addLog('[WARN] Unit ${deviceInfo.unitId} not found in database');
      }
    } catch (e) {
      _addLog('[ERROR] Failed to look up unit: $e');
    }
  }

  /// Select a unit for a fresh device
  void selectUnitForFreshDevice(ProductionUnit unit) {
    state = state.copyWith(associatedUnit: unit);
    _addLog('[INFO] Selected unit for provisioning: ${unit.unitId}');
  }

  // ============================================
  // Provisioning
  // ============================================

  /// Provision the device
  Future<bool> provision({Map<String, dynamic>? sessionData}) async {
    if (!state.isInServiceMode) {
      _addLog('[ERROR] Device not in service mode');
      return false;
    }

    if (!state.isFreshDevice) {
      _addLog('[ERROR] Device is already provisioned');
      return false;
    }

    if (!state.hasAssociatedUnit) {
      _addLog('[ERROR] No unit selected for provisioning');
      return false;
    }

    state = state.copyWith(
      phase: ServiceModePhase.executingCommand,
      currentCommand: 'provision',
    );

    try {
      // Build provisioning data
      final unit = state.associatedUnit!;
      final manifest = state.manifest;

      // Determine what data to send based on manifest provisioning_fields
      String? cloudUrl;
      String? cloudAnonKey;

      if (manifest?.provisioningFields.allFields.contains('cloud_url') ?? false) {
        cloudUrl = dotenv.env['SUPABASE_URL'];
      }
      if (manifest?.provisioningFields.allFields.contains('cloud_anon_key') ?? false) {
        cloudAnonKey = dotenv.env['SUPABASE_ANON_KEY'];
      }

      final success = await _service.provision(
        unitId: unit.unitId,
        cloudUrl: cloudUrl,
        cloudAnonKey: cloudAnonKey,
        additionalData: sessionData,
      );

      if (success) {
        // Refresh device status
        final status = await _service.getStatus();
        if (status != null) {
          state = state.copyWith(deviceInfo: status);
        }

        // Save MAC address to database if available
        if (state.deviceInfo?.macAddress != null &&
            state.deviceInfo!.macAddress.isNotEmpty) {
          await _saveMacAddress(unit.id, state.deviceInfo!.macAddress);
        }

        // Save Thread credentials if present AND device has thread_br capability
        // Only Thread Border Routers create/provide thread credentials
        final hasThreadBrCapability = manifest?.capabilities.threadBr ?? false;
        if (hasThreadBrCapability &&
            (state.deviceInfo?.hasThreadCredentials ?? false)) {
          await _saveThreadCredentials(unit.id);
        }

        state = state.copyWith(
          phase: ServiceModePhase.inServiceMode,
          clearCurrentCommand: true,
        );
        return true;
      } else {
        state = state.copyWith(
          phase: ServiceModePhase.error,
          errorMessage: 'Provisioning failed',
          clearCurrentCommand: true,
        );
        return false;
      }
    } catch (e) {
      _addLog('[ERROR] Provisioning failed: $e');
      state = state.copyWith(
        phase: ServiceModePhase.error,
        errorMessage: e.toString(),
        clearCurrentCommand: true,
      );
      return false;
    }
  }

  Future<void> _saveMacAddress(String unitId, String macAddress) async {
    try {
      await _unitRepository.updateMacAddress(unitId, macAddress);
      _addLog('[INFO] Saved MAC address to database: $macAddress');
      ref.invalidate(unitByIdProvider(unitId));
    } catch (e) {
      _addLog('[WARN] Failed to save MAC address: $e');
    }
  }

  /// Save Thread Border Router credentials from device status
  ///
  /// Called during Hub provisioning when the device reports Thread credentials
  /// in its get_status response. These credentials are used by the mobile app
  /// to provision crates to join the Hub's Thread network.
  Future<void> _saveThreadCredentials(String unitId) async {
    final deviceInfo = state.deviceInfo;
    if (deviceInfo == null || !deviceInfo.hasThreadCredentials) {
      return;
    }

    try {
      final credentials = deviceInfo.getThreadCredentials(unitId);
      if (credentials == null) {
        _addLog('[WARN] Failed to parse Thread credentials from device');
        return;
      }

      // Validate before saving
      final validationError = credentials.validate();
      if (validationError != null) {
        _addLog('[WARN] Invalid Thread credentials: $validationError');
        return;
      }

      await _unitRepository.saveThreadCredentials(credentials);
      _addLog('[INFO] Saved Thread credentials: ${credentials.networkName} (ch${credentials.channel})');
    } catch (e) {
      _addLog('[WARN] Failed to save Thread credentials: $e');
    }
  }

  // ============================================
  // Testing
  // ============================================

  /// Run a single test
  Future<TestResult> runTest(
    String testName, {
    Map<String, dynamic>? testData,
  }) async {
    if (!state.isInServiceMode) {
      return TestResult(
        testId: testName,
        status: TestStatus.failed,
        message: 'Device not in service mode',
        timestamp: DateTime.now(),
      );
    }

    state = state.copyWith(
      phase: ServiceModePhase.executingCommand,
      currentCommand: 'test_$testName',
    );

    state = state.updateTestResult(TestResult(
      testId: testName,
      status: TestStatus.running,
      timestamp: DateTime.now(),
    ));

    final result = await _service.runTest(testName, testData: testData);

    state = state.updateTestResult(result);
    state = state.copyWith(
      phase: ServiceModePhase.inServiceMode,
      clearCurrentCommand: true,
    );

    return result;
  }

  /// Run Wi-Fi test
  Future<TestResult> testWifi({String? ssid, String? password}) async {
    if (!state.isInServiceMode) {
      return TestResult(
        testId: 'wifi',
        status: TestStatus.failed,
        message: 'Device not in service mode',
        timestamp: DateTime.now(),
      );
    }

    state = state.copyWith(
      phase: ServiceModePhase.executingCommand,
      currentCommand: 'test_wifi',
    );

    state = state.updateTestResult(TestResult(
      testId: 'wifi',
      status: TestStatus.running,
      timestamp: DateTime.now(),
    ));

    final result = await _service.testWifi(ssid: ssid, password: password);

    state = state.updateTestResult(result);
    state = state.copyWith(
      phase: ServiceModePhase.inServiceMode,
      clearCurrentCommand: true,
    );

    return result;
  }

  /// Run all tests
  Future<TestResult> testAll({String? wifiSsid, String? wifiPassword}) async {
    if (!state.isInServiceMode) {
      return TestResult(
        testId: 'all',
        status: TestStatus.failed,
        message: 'Device not in service mode',
        timestamp: DateTime.now(),
      );
    }

    state = state.copyWith(
      phase: ServiceModePhase.executingCommand,
      currentCommand: 'test_all',
    );

    state = state.updateTestResult(TestResult(
      testId: 'all',
      status: TestStatus.running,
      timestamp: DateTime.now(),
    ));

    final result =
        await _service.testAll(wifiSsid: wifiSsid, wifiPassword: wifiPassword);

    state = state.updateTestResult(result);

    // If result contains individual test results, update those too
    if (result.data != null) {
      for (final entry in result.data!.entries) {
        if (entry.key.endsWith('_ok') && entry.value is bool) {
          final testName = entry.key.replaceAll('_ok', '');
          state = state.updateTestResult(TestResult(
            testId: testName,
            status: (entry.value as bool) ? TestStatus.passed : TestStatus.failed,
            timestamp: DateTime.now(),
          ));
        }
      }
    }

    state = state.copyWith(
      phase: ServiceModePhase.inServiceMode,
      clearCurrentCommand: true,
    );

    return result;
  }

  // ============================================
  // Reset Operations
  // ============================================

  /// Customer reset
  Future<bool> customerReset() async {
    if (!state.isInServiceMode) {
      _addLog('[ERROR] Device not in service mode');
      return false;
    }

    state = state.copyWith(
      phase: ServiceModePhase.executingCommand,
      currentCommand: 'customer_reset',
    );

    final success = await _service.customerReset();

    if (success) {
      // Device will reboot, disconnect
      await disconnect();
    } else {
      state = state.copyWith(
        phase: ServiceModePhase.error,
        errorMessage: 'Customer reset failed',
        clearCurrentCommand: true,
      );
    }

    return success;
  }

  /// Factory reset
  Future<bool> factoryReset() async {
    if (!state.isInServiceMode) {
      _addLog('[ERROR] Device not in service mode');
      return false;
    }

    state = state.copyWith(
      phase: ServiceModePhase.executingCommand,
      currentCommand: 'factory_reset',
    );

    final success = await _service.factoryReset();

    if (success) {
      // Device will reboot, disconnect
      await disconnect();
    } else {
      state = state.copyWith(
        phase: ServiceModePhase.error,
        errorMessage: 'Factory reset failed',
        clearCurrentCommand: true,
      );
    }

    return success;
  }

  /// Reboot device
  Future<bool> reboot() async {
    state = state.copyWith(
      phase: ServiceModePhase.executingCommand,
      currentCommand: 'reboot',
    );

    final success = await _service.reboot();

    if (success) {
      // Device will reboot, disconnect and wait for reconnection
      await disconnect();
    } else {
      state = state.copyWith(
        phase: ServiceModePhase.error,
        errorMessage: 'Reboot failed',
        clearCurrentCommand: true,
      );
    }

    return success;
  }

  // ============================================
  // Firmware Flashing
  // ============================================

  /// Flash firmware to device (if firmware is provided)
  Future<bool> flashFirmware(FirmwareVersion firmware, String chipType) async {
    if (state.selectedPort == null) {
      _addLog('[ERROR] No port selected');
      return false;
    }

    // Disconnect service mode connection first
    if (_service.isConnected) {
      await disconnect();
    }

    state = state.copyWith(
      phase: ServiceModePhase.executingCommand,
      currentCommand: 'flash_firmware',
    );

    StreamSubscription? flashLogSubscription;

    try {
      // Subscribe to flash logs
      flashLogSubscription = _flashService.logStream.listen((line) {
        _addLog(line);
      });

      // Download firmware if needed
      _addLog('[INFO] Downloading firmware binary...');
      _downloadedFirmware =
          await _firmwareRepository.downloadFirmwareBinary(firmware.id);
      _addLog('[INFO] Firmware downloaded: ${_downloadedFirmware!.path}');

      // Flash the firmware
      final result = await _flashService.flashFirmware(
        binaryPath: _downloadedFirmware!.path,
        port: state.selectedPort!,
        chipType: chipType,
      );

      if (result.success) {
        _addLog('[SUCCESS] Firmware flashed successfully');
        state = state.copyWith(
          phase: ServiceModePhase.disconnected,
          clearCurrentCommand: true,
        );
        return true;
      } else {
        _addLog('[ERROR] Flash failed: ${result.errorMessage}');
        state = state.copyWith(
          phase: ServiceModePhase.error,
          errorMessage: result.errorMessage,
          clearCurrentCommand: true,
        );
        return false;
      }
    } catch (e) {
      _addLog('[ERROR] Flash failed: $e');
      state = state.copyWith(
        phase: ServiceModePhase.error,
        errorMessage: e.toString(),
        clearCurrentCommand: true,
      );
      return false;
    } finally {
      await flashLogSubscription?.cancel();
    }
  }

  // ============================================
  // State Management
  // ============================================

  /// Reset state for new session
  void reset() {
    _cancelSubscriptions();
    _downloadedFirmware?.delete().catchError((_) {});
    _downloadedFirmware = null;

    state = ServiceModeState.initial().copyWith(
      selectedPort: state.selectedPort,
    );
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _service.disconnect();
    _downloadedFirmware?.delete().catchError((_) {});
    super.dispose();
  }
}
