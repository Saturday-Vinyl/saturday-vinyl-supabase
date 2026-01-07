import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Saturday BLE Provisioning Service UUIDs.
///
/// Based on Saturday Vinyl BLE Provisioning Protocol v1.0.0
class SaturdayBleUuids {
  SaturdayBleUuids._();

  /// Base UUID pattern: 5356XXXX-0001-1000-8000-00805f9b34fb
  /// "SV" in hex (0x53 = 'S', 0x56 = 'V')

  /// Primary provisioning service UUID
  static const String service = '53560000-0001-1000-8000-00805f9b34fb';

  /// Device Info characteristic - Read
  static const String deviceInfo = '53560001-0001-1000-8000-00805f9b34fb';

  /// Status characteristic - Read, Notify
  static const String status = '53560002-0001-1000-8000-00805f9b34fb';

  /// Command characteristic - Write
  static const String command = '53560003-0001-1000-8000-00805f9b34fb';

  /// Response characteristic - Read, Notify
  static const String response = '53560004-0001-1000-8000-00805f9b34fb';

  /// Wi-Fi SSID characteristic - Write
  static const String wifiSsid = '53560010-0001-1000-8000-00805f9b34fb';

  /// Wi-Fi Password characteristic - Write
  static const String wifiPassword = '53560011-0001-1000-8000-00805f9b34fb';

  /// Thread Dataset characteristic - Write
  static const String threadDataset = '53560020-0001-1000-8000-00805f9b34fb';

  /// User Token characteristic - Write
  static const String userToken = '53560030-0001-1000-8000-00805f9b34fb';

  /// Short service UUID for scanning (16-bit)
  static const int serviceShort = 0x5356;
}

/// Status codes from the device.
enum BleProvisioningStatus {
  idle(0x00),
  ready(0x01),
  credentialsReceived(0x02),
  connecting(0x03),
  verifying(0x04),
  success(0x05),
  errorInvalidSsid(0x10),
  errorInvalidPassword(0x11),
  errorWifiFailed(0x12),
  errorWifiTimeout(0x13),
  errorThreadFailed(0x14),
  errorCloudFailed(0x15),
  errorBusy(0x1E),
  errorUnknown(0x1F);

  final int code;
  const BleProvisioningStatus(this.code);

  static BleProvisioningStatus fromCode(int code) {
    return BleProvisioningStatus.values.firstWhere(
      (s) => s.code == code,
      orElse: () => BleProvisioningStatus.errorUnknown,
    );
  }

  bool get isError => code >= 0x10;

  String get displayMessage {
    switch (this) {
      case BleProvisioningStatus.idle:
        return 'Device is idle';
      case BleProvisioningStatus.ready:
        return 'Ready for credentials';
      case BleProvisioningStatus.credentialsReceived:
        return 'Credentials received';
      case BleProvisioningStatus.connecting:
        return 'Connecting to network...';
      case BleProvisioningStatus.verifying:
        return 'Verifying cloud connection...';
      case BleProvisioningStatus.success:
        return 'Setup complete!';
      case BleProvisioningStatus.errorInvalidSsid:
        return 'Invalid network name';
      case BleProvisioningStatus.errorInvalidPassword:
        return 'Invalid password';
      case BleProvisioningStatus.errorWifiFailed:
        return 'Could not connect to Wi-Fi. Check password and try again.';
      case BleProvisioningStatus.errorWifiTimeout:
        return 'Connection timed out. Make sure you\'re near the router.';
      case BleProvisioningStatus.errorThreadFailed:
        return 'Could not join Thread network';
      case BleProvisioningStatus.errorCloudFailed:
        return 'Could not connect to Saturday cloud';
      case BleProvisioningStatus.errorBusy:
        return 'Device is busy. Please try again.';
      case BleProvisioningStatus.errorUnknown:
        return 'An unexpected error occurred';
    }
  }
}

/// Commands that can be sent to the device.
enum BleCommand {
  connect(0x01),
  reset(0x02),
  getStatus(0x03),
  scanWifi(0x04),
  abort(0x05),
  factoryReset(0xFF);

  final int code;
  const BleCommand(this.code);
}

/// Device information from the Device Info characteristic.
class BleDeviceInfo {
  final String deviceType;
  final String unitId;
  final String firmwareVersion;
  final String protocolVersion;
  final List<String> capabilities;
  final bool needsProvisioning;
  final bool hasWifi;
  final bool hasThread;

  const BleDeviceInfo({
    required this.deviceType,
    required this.unitId,
    required this.firmwareVersion,
    required this.protocolVersion,
    required this.capabilities,
    required this.needsProvisioning,
    required this.hasWifi,
    required this.hasThread,
  });

  factory BleDeviceInfo.fromJson(Map<String, dynamic> json) {
    return BleDeviceInfo(
      deviceType: json['device_type'] as String? ?? 'unknown',
      unitId: json['unit_id'] as String? ?? '',
      firmwareVersion: json['firmware_version'] as String? ?? '0.0.0',
      protocolVersion: json['protocol_version'] as String? ?? '1.0',
      capabilities: (json['capabilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      needsProvisioning: json['needs_provisioning'] as bool? ?? true,
      hasWifi: json['has_wifi'] as bool? ?? false,
      hasThread: json['has_thread'] as bool? ?? false,
    );
  }

  bool get isHub => deviceType == 'hub';
  bool get isCrate => deviceType == 'crate';
  bool get supportsWifi => capabilities.contains('wifi');
  bool get supportsThread => capabilities.contains('thread');
  bool get isThreadBorderRouter => capabilities.contains('thread_br');
}

/// A scanned Wi-Fi network.
class WifiNetwork {
  final String ssid;
  final int rssi;
  final bool secure;

  const WifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.secure,
  });

  factory WifiNetwork.fromJson(Map<String, dynamic> json) {
    return WifiNetwork(
      ssid: json['ssid'] as String? ?? '',
      rssi: json['rssi'] as int? ?? -100,
      secure: json['secure'] as bool? ?? true,
    );
  }

  /// Signal strength indicator (0-4 bars)
  int get signalStrength {
    if (rssi >= -50) return 4;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }
}

/// A discovered Saturday device via BLE.
class DiscoveredDevice {
  final BluetoothDevice device;
  final String name;
  final int rssi;
  final String? deviceType;
  final String? identifier;

  const DiscoveredDevice({
    required this.device,
    required this.name,
    required this.rssi,
    this.deviceType,
    this.identifier,
  });

  /// Parse device info from advertising name.
  /// Format: `Saturday DeviceType Identifier`
  factory DiscoveredDevice.fromScanResult(ScanResult result) {
    final name = result.device.advName;
    String? deviceType;
    String? identifier;

    if (name.startsWith('Saturday ')) {
      final parts = name.split(' ');
      if (parts.length >= 2) {
        deviceType = parts[1].toLowerCase();
      }
      if (parts.length >= 3) {
        identifier = parts[2];
      }
    }

    return DiscoveredDevice(
      device: result.device,
      name: name,
      rssi: result.rssi,
      deviceType: deviceType,
      identifier: identifier,
    );
  }

  bool get isHub => deviceType == 'hub';
  bool get isCrate => deviceType == 'crate';
}

/// State of the BLE connection.
enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  discovering,
  ready,
  provisioning,
  error,
}

/// Service for BLE communication with Saturday devices.
///
/// Implements the Saturday BLE Provisioning Protocol v1.0.0
class BleService {
  BleService._();
  static final BleService _instance = BleService._();
  static BleService get instance => _instance;

  BluetoothDevice? _connectedDevice;
  BleDeviceInfo? _deviceInfo;
  final Map<String, BluetoothCharacteristic> _characteristics = {};

  StreamSubscription<List<int>>? _statusSubscription;
  StreamSubscription<List<int>>? _responseSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final _statusController = StreamController<BleProvisioningStatus>.broadcast();
  final _responseController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStateController = StreamController<BleConnectionState>.broadcast();
  final _discoveredDevicesController = StreamController<List<DiscoveredDevice>>.broadcast();

  /// Stream of provisioning status updates.
  Stream<BleProvisioningStatus> get statusStream => _statusController.stream;

  /// Stream of response messages from the device.
  Stream<Map<String, dynamic>> get responseStream => _responseController.stream;

  /// Stream of connection state changes.
  Stream<BleConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Stream of discovered devices during scanning.
  Stream<List<DiscoveredDevice>> get discoveredDevicesStream =>
      _discoveredDevicesController.stream;

  /// The currently connected device info.
  BleDeviceInfo? get deviceInfo => _deviceInfo;

  /// Whether BLE is available on this device.
  Future<bool> get isAvailable async {
    return await FlutterBluePlus.isSupported;
  }

  /// Whether Bluetooth is turned on.
  /// Waits for a definitive state (not unknown) with a timeout.
  Future<bool> get isOn async {
    try {
      // Wait for adapter state, filtering out 'unknown' states
      // with a timeout to avoid hanging indefinitely
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(
            const Duration(seconds: 3),
            onTimeout: () => BluetoothAdapterState.unknown,
          );
      debugPrint('[BLE] Adapter state check result: $state');
      return state == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('[BLE] Error checking adapter state: $e');
      return false;
    }
  }

  /// Start scanning for Saturday devices.
  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    debugPrint('[BLE] Starting scan for Saturday devices...');
    _connectionStateController.add(BleConnectionState.scanning);

    final List<DiscoveredDevice> devices = [];

    // Check adapter state first
    final adapterState = await FlutterBluePlus.adapterState.first;
    debugPrint('[BLE] Adapter state: $adapterState');

    if (adapterState != BluetoothAdapterState.on) {
      debugPrint('[BLE] ERROR: Bluetooth adapter is not on');
      _connectionStateController.add(BleConnectionState.error);
      return;
    }

    // Subscribe to scan results
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      debugPrint('[BLE] Scan results received: ${results.length} devices');
      devices.clear();
      for (final result in results) {
        final name = result.device.advName;
        final platformName = result.device.platformName;
        debugPrint('[BLE]   Device: name="$name", platformName="$platformName", rssi=${result.rssi}');

        // Filter for Saturday devices by name prefix
        // Note: We filter by name rather than service UUID because many devices
        // don't advertise their full service UUID in the advertisement packet
        if (name.isNotEmpty && name.startsWith('Saturday ')) {
          debugPrint('[BLE]   -> MATCHED Saturday device!');
          devices.add(DiscoveredDevice.fromScanResult(result));
        }
      }
      debugPrint('[BLE] Saturday devices found: ${devices.length}');
      _discoveredDevicesController.add(List.from(devices));
    });

    // Start scanning without service UUID filter
    // We filter by name prefix in the results listener above
    // This is more reliable as not all devices advertise service UUIDs
    debugPrint('[BLE] Calling FlutterBluePlus.startScan with timeout: $timeout');
    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );
      debugPrint('[BLE] Scan started successfully');
    } catch (e) {
      debugPrint('[BLE] ERROR starting scan: $e');
      rethrow;
    }

    // Wait for scan to complete
    debugPrint('[BLE] Waiting for scan timeout...');
    await Future.delayed(timeout);
    debugPrint('[BLE] Scan timeout reached, cleaning up');
    await subscription.cancel();

    if (_connectedDevice == null) {
      _connectionStateController.add(BleConnectionState.disconnected);
    }
    debugPrint('[BLE] Scan complete. Found ${devices.length} Saturday devices');
  }

  /// Stop scanning for devices.
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    if (_connectedDevice == null) {
      _connectionStateController.add(BleConnectionState.disconnected);
    }
  }

  /// Connect to a discovered device.
  Future<void> connect(DiscoveredDevice discovered) async {
    try {
      _connectionStateController.add(BleConnectionState.connecting);

      // Connect to the device
      await discovered.device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = discovered.device;

      // Listen for disconnection
      _connectionSubscription = discovered.device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      _connectionStateController.add(BleConnectionState.discovering);

      // Discover services
      final services = await discovered.device.discoverServices();

      // Find Saturday provisioning service
      final provService = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == SaturdayBleUuids.service.toLowerCase(),
        orElse: () => throw Exception('Saturday service not found'),
      );

      // Store characteristic references
      for (final char in provService.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        _characteristics[uuid] = char;
      }

      // Read device info
      await _readDeviceInfo();

      // Subscribe to status notifications
      await _subscribeToStatus();

      // Subscribe to response notifications
      await _subscribeToResponse();

      _connectionStateController.add(BleConnectionState.ready);
    } catch (e) {
      _connectionStateController.add(BleConnectionState.error);
      await disconnect();
      rethrow;
    }
  }

  /// Disconnect from the current device.
  Future<void> disconnect() async {
    await _statusSubscription?.cancel();
    await _responseSubscription?.cancel();
    await _connectionSubscription?.cancel();

    _statusSubscription = null;
    _responseSubscription = null;
    _connectionSubscription = null;

    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }

    _connectedDevice = null;
    _deviceInfo = null;
    _characteristics.clear();

    _connectionStateController.add(BleConnectionState.disconnected);
  }

  /// Provision the device with Wi-Fi credentials (for Hub).
  Future<void> provisionWifi({
    required String ssid,
    required String password,
  }) async {
    _connectionStateController.add(BleConnectionState.provisioning);

    try {
      // Write SSID
      final ssidChar = _characteristics[SaturdayBleUuids.wifiSsid.toLowerCase()];
      if (ssidChar == null) throw Exception('SSID characteristic not found');
      await ssidChar.write(utf8.encode(ssid), withoutResponse: false);

      // Write password
      final passChar = _characteristics[SaturdayBleUuids.wifiPassword.toLowerCase()];
      if (passChar == null) throw Exception('Password characteristic not found');
      await passChar.write(utf8.encode(password), withoutResponse: false);

      // Send CONNECT command
      await _sendCommand(BleCommand.connect);
    } catch (e) {
      _connectionStateController.add(BleConnectionState.error);
      rethrow;
    }
  }

  /// Provision the device with Thread credentials (for Crate).
  Future<void> provisionThread({
    required String threadDataset,
  }) async {
    _connectionStateController.add(BleConnectionState.provisioning);

    try {
      // Write Thread dataset
      final threadChar = _characteristics[SaturdayBleUuids.threadDataset.toLowerCase()];
      if (threadChar == null) throw Exception('Thread characteristic not found');
      await threadChar.write(utf8.encode(threadDataset), withoutResponse: false);

      // Send CONNECT command
      await _sendCommand(BleCommand.connect);
    } catch (e) {
      _connectionStateController.add(BleConnectionState.error);
      rethrow;
    }
  }

  /// Write user authentication token for account linking.
  Future<void> writeUserToken(String token) async {
    final tokenChar = _characteristics[SaturdayBleUuids.userToken.toLowerCase()];
    if (tokenChar == null) throw Exception('User token characteristic not found');
    await tokenChar.write(utf8.encode(token), withoutResponse: false);
  }

  /// Request Wi-Fi network scan from the device.
  Future<void> requestWifiScan() async {
    await _sendCommand(BleCommand.scanWifi);
  }

  /// Reset stored credentials on the device.
  Future<void> resetCredentials() async {
    await _sendCommand(BleCommand.reset);
  }

  /// Abort the current operation.
  Future<void> abort() async {
    await _sendCommand(BleCommand.abort);
  }

  /// Request current status from the device.
  Future<void> requestStatus() async {
    await _sendCommand(BleCommand.getStatus);
  }

  Future<void> _readDeviceInfo() async {
    final infoChar = _characteristics[SaturdayBleUuids.deviceInfo.toLowerCase()];
    if (infoChar == null) throw Exception('Device info characteristic not found');

    final value = await infoChar.read();
    final jsonStr = utf8.decode(value);
    final json = jsonDecode(jsonStr) as Map<String, dynamic>;
    _deviceInfo = BleDeviceInfo.fromJson(json);
  }

  Future<void> _subscribeToStatus() async {
    final statusChar = _characteristics[SaturdayBleUuids.status.toLowerCase()];
    if (statusChar == null) return;

    await statusChar.setNotifyValue(true);
    _statusSubscription = statusChar.onValueReceived.listen((value) {
      if (value.isNotEmpty) {
        final status = BleProvisioningStatus.fromCode(value[0]);
        _statusController.add(status);

        // Update connection state based on status
        if (status == BleProvisioningStatus.success) {
          _connectionStateController.add(BleConnectionState.ready);
        } else if (status.isError) {
          _connectionStateController.add(BleConnectionState.error);
        }
      }
    });
  }

  Future<void> _subscribeToResponse() async {
    final responseChar = _characteristics[SaturdayBleUuids.response.toLowerCase()];
    if (responseChar == null) return;

    await responseChar.setNotifyValue(true);
    _responseSubscription = responseChar.onValueReceived.listen((value) {
      try {
        final jsonStr = utf8.decode(value);
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        _responseController.add(json);
      } catch (e) {
        // Ignore parse errors
      }
    });
  }

  Future<void> _sendCommand(BleCommand command, [List<int>? parameters]) async {
    final cmdChar = _characteristics[SaturdayBleUuids.command.toLowerCase()];
    if (cmdChar == null) throw Exception('Command characteristic not found');

    final data = [command.code, ...?parameters];
    await cmdChar.write(data, withoutResponse: false);
  }

  void _handleDisconnection() {
    _connectedDevice = null;
    _deviceInfo = null;
    _characteristics.clear();
    _connectionStateController.add(BleConnectionState.disconnected);
  }

  /// Dispose of all resources.
  void dispose() {
    disconnect();
    _statusController.close();
    _responseController.close();
    _connectionStateController.close();
    _discoveredDevicesController.close();
  }
}
