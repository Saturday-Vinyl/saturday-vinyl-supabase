import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/services/ble_service.dart';

/// Provider for the BLE service singleton.
final bleServiceProvider = Provider<BleService>((ref) {
  return BleService.instance;
});

/// State for the device setup/provisioning flow.
class DeviceSetupState {
  final BleConnectionState connectionState;
  final List<DiscoveredDevice> discoveredDevices;
  final DiscoveredDevice? selectedDevice;
  final BleDeviceInfo? deviceInfo;
  final BleProvisioningStatus? provisioningStatus;
  final List<WifiNetwork> wifiNetworks;
  final String? errorMessage;
  final bool isScanning;
  final bool hasScanCompleted;

  /// User-defined name for the device (defaults to production unit name).
  final String? customDeviceName;

  /// WiFi SSID used for provisioning (stored in provision_data).
  final String? wifiSsid;

  /// Thread dataset used for provisioning (stored in provision_data).
  final String? threadDataset;

  /// Hub ID used for crate provisioning (to track which hub provided Thread credentials).
  final String? selectedHubId;

  /// Specific error code from Response characteristic (more detailed than status).
  /// Added in BLE Provisioning Protocol v1.2.0.
  final BleErrorCode? errorCode;

  const DeviceSetupState({
    this.connectionState = BleConnectionState.disconnected,
    this.discoveredDevices = const [],
    this.selectedDevice,
    this.deviceInfo,
    this.provisioningStatus,
    this.wifiNetworks = const [],
    this.errorMessage,
    this.isScanning = false,
    this.hasScanCompleted = false,
    this.customDeviceName,
    this.wifiSsid,
    this.threadDataset,
    this.selectedHubId,
    this.errorCode,
  });

  DeviceSetupState copyWith({
    BleConnectionState? connectionState,
    List<DiscoveredDevice>? discoveredDevices,
    DiscoveredDevice? selectedDevice,
    BleDeviceInfo? deviceInfo,
    BleProvisioningStatus? provisioningStatus,
    List<WifiNetwork>? wifiNetworks,
    String? errorMessage,
    bool? isScanning,
    bool? hasScanCompleted,
    String? customDeviceName,
    String? wifiSsid,
    String? threadDataset,
    String? selectedHubId,
    BleErrorCode? errorCode,
    bool clearErrorCode = false,
  }) {
    return DeviceSetupState(
      connectionState: connectionState ?? this.connectionState,
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      selectedDevice: selectedDevice ?? this.selectedDevice,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      provisioningStatus: provisioningStatus ?? this.provisioningStatus,
      wifiNetworks: wifiNetworks ?? this.wifiNetworks,
      errorMessage: errorMessage,
      isScanning: isScanning ?? this.isScanning,
      hasScanCompleted: hasScanCompleted ?? this.hasScanCompleted,
      customDeviceName: customDeviceName ?? this.customDeviceName,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      threadDataset: threadDataset ?? this.threadDataset,
      selectedHubId: selectedHubId ?? this.selectedHubId,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
    );
  }

  /// Get the effective device name (custom name or default from device info).
  String get effectiveDeviceName {
    if (customDeviceName != null && customDeviceName!.isNotEmpty) {
      return customDeviceName!;
    }
    if (deviceInfo != null) {
      return deviceInfo!.isHub
          ? 'Saturday Hub ${deviceInfo!.serialNumber}'
          : 'Saturday Crate ${deviceInfo!.serialNumber}';
    }
    return 'Saturday Device';
  }

  /// Whether we're in an error state.
  bool get hasError => errorMessage != null || provisioningStatus?.isError == true;

  /// Whether provisioning was successful.
  bool get isSuccess => provisioningStatus == BleProvisioningStatus.success;

  /// Whether we're connected to a device.
  bool get isConnected =>
      connectionState == BleConnectionState.connected ||
      connectionState == BleConnectionState.ready ||
      connectionState == BleConnectionState.discovering ||
      connectionState == BleConnectionState.provisioning;

  /// Whether we're in the process of provisioning.
  bool get isProvisioning => connectionState == BleConnectionState.provisioning;

  /// Get the current step in the setup flow.
  SetupStep get currentStep {
    debugPrint('[BLE Provider] currentStep: connectionState=$connectionState, isScanning=$isScanning, hasScanCompleted=$hasScanCompleted, devices=${discoveredDevices.length}, selectedDevice=$selectedDevice');

    // If we found devices OR scan completed (even with no devices), show the selection screen
    if ((discoveredDevices.isNotEmpty || hasScanCompleted) && selectedDevice == null) {
      debugPrint('[BLE Provider] -> selectDevice (found ${discoveredDevices.length} devices, scanCompleted=$hasScanCompleted)');
      return SetupStep.selectDevice;
    }
    // Still scanning - show scanning screen
    if (isScanning) {
      debugPrint('[BLE Provider] -> scanning (isScanning=$isScanning)');
      return SetupStep.scanning;
    }
    if (connectionState == BleConnectionState.connecting ||
        connectionState == BleConnectionState.discovering) {
      debugPrint('[BLE Provider] -> connecting');
      return SetupStep.connecting;
    }
    if (deviceInfo == null && selectedDevice != null) {
      debugPrint('[BLE Provider] -> connecting (no deviceInfo)');
      return SetupStep.connecting;
    }
    if (isSuccess) {
      debugPrint('[BLE Provider] -> complete');
      return SetupStep.complete;
    }
    if (deviceInfo != null) {
      debugPrint('[BLE Provider] -> configure');
      return SetupStep.configure;
    }
    // Default to scanning (initial state before scan starts)
    debugPrint('[BLE Provider] -> scanning (default/initial)');
    return SetupStep.scanning;
  }
}

/// Steps in the device setup flow.
enum SetupStep {
  selectType,
  scanning,
  selectDevice,
  connecting,
  configure,
  complete,
}

/// Notifier for managing device setup state.
class DeviceSetupNotifier extends StateNotifier<DeviceSetupState> {
  final BleService _bleService;
  StreamSubscription<BleConnectionState>? _connectionSub;
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;
  StreamSubscription<BleProvisioningStatus>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _responseSub;

  DeviceSetupNotifier(this._bleService) : super(const DeviceSetupState()) {
    _setupSubscriptions();
  }

  void _setupSubscriptions() {
    debugPrint('[BLE Provider] Setting up subscriptions');
    _connectionSub = _bleService.connectionStateStream.listen((connectionState) {
      debugPrint('[BLE Provider] Connection state changed: $connectionState');
      state = state.copyWith(connectionState: connectionState);
    });

    _devicesSub = _bleService.discoveredDevicesStream.listen((devices) {
      debugPrint('[BLE Provider] Received ${devices.length} discovered devices');
      for (final d in devices) {
        debugPrint('[BLE Provider]   - ${d.name}');
      }
      state = state.copyWith(discoveredDevices: devices);
      debugPrint('[BLE Provider] State updated, discoveredDevices count: ${state.discoveredDevices.length}');
    });

    _statusSub = _bleService.statusStream.listen((status) {
      state = state.copyWith(
        provisioningStatus: status,
        errorMessage: status.isError ? status.displayMessage : null,
      );
    });

    _responseSub = _bleService.responseStream.listen((response) {
      final type = response['type'] as String?;

      if (type == 'wifi_scan') {
        // Handle Wi-Fi scan results
        final networks = (response['networks'] as List?)
                ?.map((n) => WifiNetwork.fromJson(n as Map<String, dynamic>))
                .toList() ??
            [];
        state = state.copyWith(wifiNetworks: networks);
      } else if (type == 'error') {
        // Handle error responses (BLE Protocol v1.2.0)
        final code = response['code'] as String? ?? 'UNKNOWN';
        final errorCode = BleErrorCode.fromCode(code);
        debugPrint('[BLE Provider] Received error response: $code -> ${errorCode.userMessage}');
        state = state.copyWith(
          errorCode: errorCode,
          errorMessage: errorCode.userMessage,
        );
      }
    });
  }

  /// Check if BLE is available and enabled.
  Future<bool> checkBleAvailability() async {
    debugPrint('[BLE Provider] Checking BLE availability...');
    final available = await _bleService.isAvailable;
    debugPrint('[BLE Provider] BLE available: $available');
    if (!available) {
      debugPrint('[BLE Provider] ERROR: BLE not supported');
      state = state.copyWith(
        errorMessage: 'Bluetooth is not supported on this device',
      );
      return false;
    }

    final isOn = await _bleService.isOn;
    debugPrint('[BLE Provider] BLE is on: $isOn');
    if (!isOn) {
      debugPrint('[BLE Provider] ERROR: BLE not enabled');
      state = state.copyWith(
        errorMessage: 'Please turn on Bluetooth to continue',
      );
      return false;
    }

    debugPrint('[BLE Provider] BLE is available and enabled');
    return true;
  }

  /// Start scanning for Saturday devices.
  Future<void> startScan() async {
    debugPrint('[BLE Provider] startScan called');
    state = state.copyWith(
      isScanning: true,
      hasScanCompleted: false,
      discoveredDevices: [],
      errorMessage: null,
    );

    try {
      debugPrint('[BLE Provider] Calling _bleService.startScan()');
      await _bleService.startScan();
      debugPrint('[BLE Provider] Scan completed');
    } catch (e, stack) {
      debugPrint('[BLE Provider] ERROR during scan: $e');
      debugPrint('[BLE Provider] Stack trace: $stack');
      state = state.copyWith(
        errorMessage: 'Failed to scan: $e',
      );
    } finally {
      debugPrint('[BLE Provider] Setting isScanning to false, hasScanCompleted to true');
      state = state.copyWith(
        isScanning: false,
        hasScanCompleted: true,
      );
    }
  }

  /// Stop scanning.
  Future<void> stopScan() async {
    await _bleService.stopScan();
    state = state.copyWith(isScanning: false);
  }

  /// Select and connect to a discovered device.
  Future<void> selectDevice(DiscoveredDevice device) async {
    // Stop scanning when user selects a device
    await _bleService.stopScan();

    state = state.copyWith(
      selectedDevice: device,
      isScanning: false,
      errorMessage: null,
    );

    try {
      await _bleService.connect(device);
      state = state.copyWith(
        deviceInfo: _bleService.deviceInfo,
      );
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to connect: $e',
        selectedDevice: null,
      );
    }
  }

  /// Provision with Wi-Fi credentials.
  Future<void> provisionWifi({
    required String ssid,
    required String password,
  }) async {
    // Store the SSID in state for later use in provision_data
    state = state.copyWith(errorMessage: null, wifiSsid: ssid);

    try {
      await _bleService.provisionWifi(ssid: ssid, password: password);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to provision: $e',
      );
    }
  }

  /// Provision with Thread credentials.
  Future<void> provisionThread({
    required String threadDataset,
    String? hubId,
  }) async {
    // Store the Thread dataset and hub ID in state for later use in provision_data
    state = state.copyWith(
      errorMessage: null,
      threadDataset: threadDataset,
      selectedHubId: hubId,
    );

    try {
      await _bleService.provisionThread(threadDataset: threadDataset);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to provision: $e',
      );
    }
  }

  /// Write user token for account linking.
  Future<void> writeUserToken(String token) async {
    try {
      await _bleService.writeUserToken(token);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to link account: $e',
      );
    }
  }

  /// Request Wi-Fi scan from the device.
  Future<void> requestWifiScan() async {
    try {
      await _bleService.requestWifiScan();
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to scan Wi-Fi: $e',
      );
    }
  }

  /// Retry the current operation.
  ///
  /// Smart retry behavior based on error type:
  /// - AUTH_FAILED: Keep SSID, clear password (user needs to re-enter)
  /// - NETWORK_NOT_FOUND: Keep all fields (user may want to edit SSID)
  /// - Other errors: Keep all fields intact for retry
  Future<void> retry() async {
    final previousErrorCode = state.errorCode;
    debugPrint('[BLE Provider] Retry: starting (error was: $previousErrorCode)');

    // Clear error state but preserve provisioning config for retry
    // Also reset provisioningStatus to ready (hasError checks this)
    state = state.copyWith(
      errorMessage: null,
      clearErrorCode: true,
      provisioningStatus: BleProvisioningStatus.ready,
      // Keep wifiSsid for all retry scenarios
      // Password is in the UI controller, not state, so it persists
    );

    // If we're connected and have device info, send RESET command to device
    // to reset its state machine back to READY, then return to configure step
    if (state.deviceInfo != null && state.selectedDevice != null) {
      debugPrint('[BLE Provider] Retry: sending RESET command to device');
      try {
        await _bleService.resetCredentials();
        debugPrint('[BLE Provider] Retry: RESET sent, returning to configure step');
      } catch (e) {
        debugPrint('[BLE Provider] Retry: RESET failed ($e), reconnecting...');
        // If RESET fails, try reconnecting
        await selectDevice(state.selectedDevice!);
      }
      return;
    }

    // Otherwise, reconnect to the device
    if (state.selectedDevice != null) {
      debugPrint('[BLE Provider] Retry: reconnecting to device');
      await selectDevice(state.selectedDevice!);
    } else {
      debugPrint('[BLE Provider] Retry: starting scan');
      await startScan();
    }
  }

  /// Check if the last error was an authentication error (wrong password).
  bool get wasAuthError => state.errorCode?.isAuthError ?? false;

  /// Reset the setup flow.
  Future<void> reset() async {
    await _bleService.stopScan();
    await _bleService.disconnect();
    state = const DeviceSetupState();
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  /// Set a custom name for the device.
  void setCustomDeviceName(String name) {
    state = state.copyWith(customDeviceName: name);
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _devicesSub?.cancel();
    _statusSub?.cancel();
    _responseSub?.cancel();
    _bleService.disconnect();
    super.dispose();
  }
}

/// Provider for device setup state.
final deviceSetupProvider =
    StateNotifierProvider.autoDispose<DeviceSetupNotifier, DeviceSetupState>(
  (ref) {
    final bleService = ref.watch(bleServiceProvider);
    return DeviceSetupNotifier(bleService);
  },
);

/// Provider for checking BLE availability.
final bleAvailableProvider = FutureProvider<bool>((ref) async {
  final bleService = ref.watch(bleServiceProvider);
  final available = await bleService.isAvailable;
  if (!available) return false;
  return await bleService.isOn;
});
