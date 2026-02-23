import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/providers/ble_provider.dart';
import 'package:saturday_consumer_app/services/ble_service.dart';

/// Arguments for the WiFi re-provisioning provider.
class WifiReprovisionArgs {
  final String unitId;
  final String serialNumber;
  final String? knownSsid;

  const WifiReprovisionArgs({
    required this.unitId,
    required this.serialNumber,
    this.knownSsid,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WifiReprovisionArgs &&
          runtimeType == other.runtimeType &&
          unitId == other.unitId &&
          serialNumber == other.serialNumber &&
          knownSsid == other.knownSsid;

  @override
  int get hashCode => Object.hash(unitId, serialNumber, knownSsid);
}

/// Steps in the WiFi re-provisioning flow.
enum ReprovisionStep {
  instructions,
  scanning,
  connecting,
  configure,
  complete,
}

/// State for the WiFi re-provisioning flow.
class WifiReprovisionState {
  final ReprovisionStep currentStep;
  final BleConnectionState connectionState;
  final BleDeviceInfo? deviceInfo;
  final BleProvisioningStatus? provisioningStatus;
  final List<WifiNetwork> wifiNetworks;
  final String? errorMessage;
  final BleErrorCode? errorCode;
  final bool isScanning;
  final String? wifiSsid;
  final Map<String, dynamic>? consumerOutput;
  final DiscoveredDevice? connectedDevice;

  const WifiReprovisionState({
    this.currentStep = ReprovisionStep.instructions,
    this.connectionState = BleConnectionState.disconnected,
    this.deviceInfo,
    this.provisioningStatus,
    this.wifiNetworks = const [],
    this.errorMessage,
    this.errorCode,
    this.isScanning = false,
    this.wifiSsid,
    this.consumerOutput,
    this.connectedDevice,
  });

  WifiReprovisionState copyWith({
    ReprovisionStep? currentStep,
    BleConnectionState? connectionState,
    BleDeviceInfo? deviceInfo,
    BleProvisioningStatus? provisioningStatus,
    List<WifiNetwork>? wifiNetworks,
    String? errorMessage,
    BleErrorCode? errorCode,
    bool? isScanning,
    String? wifiSsid,
    Map<String, dynamic>? consumerOutput,
    DiscoveredDevice? connectedDevice,
    bool clearErrorCode = false,
  }) {
    return WifiReprovisionState(
      currentStep: currentStep ?? this.currentStep,
      connectionState: connectionState ?? this.connectionState,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      provisioningStatus: provisioningStatus ?? this.provisioningStatus,
      wifiNetworks: wifiNetworks ?? this.wifiNetworks,
      errorMessage: errorMessage,
      isScanning: isScanning ?? this.isScanning,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
      consumerOutput: consumerOutput ?? this.consumerOutput,
      connectedDevice: connectedDevice ?? this.connectedDevice,
    );
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
}

/// Notifier for managing WiFi re-provisioning state.
class WifiReprovisionNotifier extends StateNotifier<WifiReprovisionState> {
  final BleService _bleService;
  final String _targetSerialNumber;

  StreamSubscription<BleConnectionState>? _connectionSub;
  StreamSubscription<List<DiscoveredDevice>>? _devicesSub;
  StreamSubscription<BleProvisioningStatus>? _statusSub;
  StreamSubscription<Map<String, dynamic>>? _responseSub;

  WifiReprovisionNotifier({
    required BleService bleService,
    required String targetSerialNumber,
    String? knownSsid,
  })  : _bleService = bleService,
        _targetSerialNumber = targetSerialNumber,
        super(WifiReprovisionState(
          wifiSsid: knownSsid,
        )) {
    _setupSubscriptions();
  }

  void _setupSubscriptions() {
    _connectionSub = _bleService.connectionStateStream.listen((connectionState) {
      debugPrint('[WiFi Reprovision] Connection state: $connectionState');
      state = state.copyWith(connectionState: connectionState);
    });

    _devicesSub = _bleService.discoveredDevicesStream.listen((devices) {
      debugPrint('[WiFi Reprovision] Discovered ${devices.length} devices');
      // Auto-select the matching device
      for (final device in devices) {
        if (_matchesTarget(device)) {
          debugPrint('[WiFi Reprovision] Found target device: ${device.name}');
          _autoConnect(device);
          return;
        }
      }
    });

    _statusSub = _bleService.statusStream.listen((status) {
      debugPrint('[WiFi Reprovision] Status: $status');

      ReprovisionStep? step;
      if (status == BleProvisioningStatus.success) {
        step = ReprovisionStep.complete;
      }

      state = state.copyWith(
        provisioningStatus: status,
        errorMessage: status.isError ? status.displayMessage : null,
        currentStep: step,
      );
    });

    _responseSub = _bleService.responseStream.listen((response) {
      final type = response['type'] as String?;

      if (type == 'wifi_scan') {
        final networks = (response['networks'] as List?)
                ?.map((n) => WifiNetwork.fromJson(n as Map<String, dynamic>))
                .toList() ??
            [];
        state = state.copyWith(wifiNetworks: networks);
      } else if (type == 'error') {
        final code = response['code'] as String? ?? 'UNKNOWN';
        final errorCode = BleErrorCode.fromCode(code);
        debugPrint('[WiFi Reprovision] Error: $code -> ${errorCode.userMessage}');
        state = state.copyWith(
          errorCode: errorCode,
          errorMessage: errorCode.userMessage,
        );
      } else if (type == 'provision_result') {
        final data = response['data'] as Map<String, dynamic>?;
        if (data != null && data.isNotEmpty) {
          debugPrint('[WiFi Reprovision] Consumer output: $data');
          state = state.copyWith(consumerOutput: data);
        }
      }
    });
  }

  /// Check whether a discovered device matches the target serial number.
  ///
  /// BLE advertising name format: "Saturday Hub XXXX"
  /// where XXXX is the last 4 chars of unit_id or MAC.
  /// Serial number format: "SV-HUB-000001"
  ///
  /// We match the identifier from the advertising name against the last
  /// segment of the serial number. If the identifier is shorter (4 chars),
  /// we check if the serial ends with that suffix.
  bool _matchesTarget(DiscoveredDevice device) {
    if (device.identifier == null) return false;
    final identifier = device.identifier!.toUpperCase();
    final serial = _targetSerialNumber.toUpperCase();

    // Direct match on last segment (e.g., "000001")
    final parts = serial.split('-');
    final lastSegment = parts.isNotEmpty ? parts.last : serial;

    // The BLE identifier may be a suffix of the serial's last segment
    return lastSegment == identifier || lastSegment.endsWith(identifier);
  }

  Future<void> _autoConnect(DiscoveredDevice device) async {
    await _bleService.stopScan();

    state = state.copyWith(
      currentStep: ReprovisionStep.connecting,
      connectedDevice: device,
      isScanning: false,
      errorMessage: null,
    );

    try {
      await _bleService.connect(device);
      state = state.copyWith(
        currentStep: ReprovisionStep.configure,
        deviceInfo: _bleService.deviceInfo,
      );
    } catch (e) {
      state = state.copyWith(
        currentStep: ReprovisionStep.instructions,
        errorMessage: 'Failed to connect: $e',
        connectedDevice: null,
      );
    }
  }

  /// Check if BLE is available and enabled.
  Future<bool> checkBleAvailability() async {
    final available = await _bleService.isAvailable;
    if (!available) {
      state = state.copyWith(
        errorMessage: 'Bluetooth is not supported on this device',
      );
      return false;
    }

    final isOn = await _bleService.isOn;
    if (!isOn) {
      state = state.copyWith(
        errorMessage: 'Please turn on Bluetooth to continue',
      );
      return false;
    }

    return true;
  }

  /// Start scanning for the target device.
  Future<void> startScan() async {
    state = state.copyWith(
      currentStep: ReprovisionStep.scanning,
      isScanning: true,
      errorMessage: null,
    );

    try {
      await _bleService.startScan();
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to scan: $e',
      );
    } finally {
      // If we're still scanning (didn't auto-connect), show not-found
      if (state.currentStep == ReprovisionStep.scanning) {
        state = state.copyWith(
          currentStep: ReprovisionStep.instructions,
          isScanning: false,
          errorMessage: 'Could not find your device. Make sure you '
              'long-pressed the button and the light is flashing blue.',
        );
      }
    }
  }

  /// Provision with new WiFi credentials.
  Future<void> provisionWifi({
    required String ssid,
    required String password,
  }) async {
    state = state.copyWith(errorMessage: null, wifiSsid: ssid);

    try {
      await _bleService.provisionWifi(ssid: ssid, password: password);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to provision: $e',
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

  /// Retry after an error.
  Future<void> retry() async {
    debugPrint('[WiFi Reprovision] Retry (error was: ${state.errorCode})');

    state = state.copyWith(
      errorMessage: null,
      clearErrorCode: true,
      provisioningStatus: BleProvisioningStatus.ready,
    );

    // If we're connected, send RESET and return to configure
    if (state.deviceInfo != null && state.connectedDevice != null) {
      debugPrint('[WiFi Reprovision] Sending RESET command');
      try {
        await _bleService.resetCredentials();
        state = state.copyWith(currentStep: ReprovisionStep.configure);
      } catch (e) {
        debugPrint('[WiFi Reprovision] RESET failed ($e), reconnecting');
        await _autoConnect(state.connectedDevice!);
      }
      return;
    }

    // Otherwise, go back to instructions
    state = state.copyWith(currentStep: ReprovisionStep.instructions);
  }

  /// Reset the flow completely.
  Future<void> reset() async {
    await _bleService.stopScan();
    await _bleService.disconnect();
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

/// Provider for WiFi re-provisioning state.
final wifiReprovisionProvider = StateNotifierProvider.autoDispose
    .family<WifiReprovisionNotifier, WifiReprovisionState, WifiReprovisionArgs>(
  (ref, args) {
    final bleService = ref.watch(bleServiceProvider);
    return WifiReprovisionNotifier(
      bleService: bleService,
      targetSerialNumber: args.serialNumber,
      knownSsid: args.knownSsid,
    );
  },
);

