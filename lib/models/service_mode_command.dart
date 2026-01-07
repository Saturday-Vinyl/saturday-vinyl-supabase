import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/service_mode_manifest.dart';
import 'package:saturday_app/models/service_mode_state.dart';

/// Status codes from device responses
enum ServiceModeStatus {
  /// Command succeeded
  ok,

  /// Error occurred
  error,

  /// Device is in service mode (periodic beacon)
  serviceMode,

  /// Provisioning completed successfully
  provisioned,

  /// Test(s) failed
  failed,

  /// Unknown status
  unknown;

  static ServiceModeStatus fromString(String? value) {
    switch (value) {
      case 'ok':
        return ServiceModeStatus.ok;
      case 'error':
        return ServiceModeStatus.error;
      case 'service_mode':
        return ServiceModeStatus.serviceMode;
      case 'provisioned':
        return ServiceModeStatus.provisioned;
      case 'failed':
        return ServiceModeStatus.failed;
      default:
        return ServiceModeStatus.unknown;
    }
  }

  String get value {
    switch (this) {
      case ServiceModeStatus.ok:
        return 'ok';
      case ServiceModeStatus.error:
        return 'error';
      case ServiceModeStatus.serviceMode:
        return 'service_mode';
      case ServiceModeStatus.provisioned:
        return 'provisioned';
      case ServiceModeStatus.failed:
        return 'failed';
      case ServiceModeStatus.unknown:
        return 'unknown';
    }
  }

  bool get isSuccess =>
      this == ServiceModeStatus.ok || this == ServiceModeStatus.provisioned;

  bool get isError =>
      this == ServiceModeStatus.error || this == ServiceModeStatus.failed;

  bool get isBeacon => this == ServiceModeStatus.serviceMode;
}

/// Message received from device
class ServiceModeMessage extends Equatable {
  final ServiceModeStatus status;
  final String? message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  const ServiceModeMessage({
    required this.status,
    this.message,
    this.data,
    required this.timestamp,
  });

  /// Parse a JSON line from device
  /// Returns null if the line is not valid JSON
  static ServiceModeMessage? fromJsonLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('{')) {
      return null;
    }

    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      return ServiceModeMessage(
        status: ServiceModeStatus.fromString(json['status'] as String?),
        message: json['message'] as String?,
        data: json['data'] as Map<String, dynamic>?,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Whether this is a beacon message
  bool get isBeacon => status.isBeacon;

  /// Whether this indicates success
  bool get isSuccess => status.isSuccess;

  /// Whether this indicates an error
  bool get isError => status.isError;

  /// Get error code if present
  String? get errorCode => data?['error_code'] as String?;

  /// Get device info from beacon message
  DeviceInfo? get beaconInfo {
    if (!isBeacon || data == null) return null;
    return DeviceInfo.fromJson(data!);
  }

  /// Get manifest from get_manifest response
  ServiceModeManifest? get manifestData {
    if (data == null) return null;
    return ServiceModeManifest.fromDeviceJson(data!);
  }

  /// Get device info from get_status response
  DeviceInfo? get statusInfo {
    if (data == null) return null;
    return DeviceInfo.fromJson(data!);
  }

  @override
  List<Object?> get props => [status, message, data, timestamp];

  @override
  String toString() =>
      'ServiceModeMessage(status: ${status.value}, message: $message)';
}

/// Command to send to device
class ServiceModeCommand extends Equatable {
  final String cmd;
  final Map<String, dynamic>? data;

  const ServiceModeCommand({
    required this.cmd,
    this.data,
  });

  /// Convert to JSON string for sending
  String toJsonString() {
    final map = <String, dynamic>{'cmd': cmd};
    if (data != null && data!.isNotEmpty) {
      map['data'] = data;
    }
    return '${jsonEncode(map)}\n';
  }

  // ============================================
  // Mode Control Commands
  // ============================================

  /// Enter service mode (only valid during boot window)
  static const enterServiceMode = ServiceModeCommand(cmd: 'enter_service_mode');

  /// Exit service mode and continue to standard operation
  static const exitServiceMode = ServiceModeCommand(cmd: 'exit_service_mode');

  /// Reboot the device
  static const reboot = ServiceModeCommand(cmd: 'reboot');

  // ============================================
  // Status & Diagnostics Commands
  // ============================================

  /// Get device status
  static const getStatus = ServiceModeCommand(cmd: 'get_status');

  /// Get device manifest
  static const getManifest = ServiceModeCommand(cmd: 'get_manifest');

  // ============================================
  // Provisioning Commands
  // ============================================

  /// Provision device with unit credentials
  static ServiceModeCommand provision({
    required String unitId,
    String? cloudUrl,
    String? cloudAnonKey,
    String? cloudDeviceSecret,
    Map<String, dynamic>? additionalData,
  }) {
    final data = <String, dynamic>{
      'unit_id': unitId,
    };
    if (cloudUrl != null) data['cloud_url'] = cloudUrl;
    if (cloudAnonKey != null) data['cloud_anon_key'] = cloudAnonKey;
    if (cloudDeviceSecret != null) {
      data['cloud_device_secret'] = cloudDeviceSecret;
    }
    if (additionalData != null) data.addAll(additionalData);

    return ServiceModeCommand(cmd: 'provision', data: data);
  }

  // ============================================
  // Test Commands
  // ============================================

  /// Test Wi-Fi connectivity
  static ServiceModeCommand testWifi({String? ssid, String? password}) {
    if (ssid == null && password == null) {
      return const ServiceModeCommand(cmd: 'test_wifi');
    }
    return ServiceModeCommand(
      cmd: 'test_wifi',
      data: {
        if (ssid != null) 'ssid': ssid,
        if (password != null) 'password': password,
      },
    );
  }

  /// Test Bluetooth functionality
  static const testBluetooth = ServiceModeCommand(cmd: 'test_bluetooth');

  /// Test Thread connectivity
  static const testThread = ServiceModeCommand(cmd: 'test_thread');

  /// Test cloud API connectivity
  static const testCloud = ServiceModeCommand(cmd: 'test_cloud');

  /// Test RFID tag scanning
  static const testRfid = ServiceModeCommand(cmd: 'test_rfid');

  /// Test audio output
  static const testAudio = ServiceModeCommand(cmd: 'test_audio');

  /// Test display output
  static const testDisplay = ServiceModeCommand(cmd: 'test_display');

  /// Test button input
  static const testButton = ServiceModeCommand(cmd: 'test_button');

  /// Run all supported tests
  static ServiceModeCommand testAll({String? wifiSsid, String? wifiPassword}) {
    if (wifiSsid == null && wifiPassword == null) {
      return const ServiceModeCommand(cmd: 'test_all');
    }
    return ServiceModeCommand(
      cmd: 'test_all',
      data: {
        if (wifiSsid != null) 'wifi_ssid': wifiSsid,
        if (wifiPassword != null) 'wifi_password': wifiPassword,
      },
    );
  }

  /// Generic test command by name
  static ServiceModeCommand test(String testName,
      [Map<String, dynamic>? testData]) {
    return ServiceModeCommand(
      cmd: 'test_$testName',
      data: testData,
    );
  }

  // ============================================
  // Reset Commands
  // ============================================

  /// Customer reset (clear user data, preserve provisioning)
  static const customerReset = ServiceModeCommand(cmd: 'customer_reset');

  /// Factory reset (full wipe including unit_id)
  static const factoryReset = ServiceModeCommand(cmd: 'factory_reset');

  // ============================================
  // Custom Commands
  // ============================================

  /// Create a custom command
  static ServiceModeCommand custom(String name,
      [Map<String, dynamic>? commandData]) {
    return ServiceModeCommand(cmd: name, data: commandData);
  }

  @override
  List<Object?> get props => [cmd, data];

  @override
  String toString() => 'ServiceModeCommand(cmd: $cmd)';
}

/// Timeout recommendations from protocol spec
class ServiceModeTimeouts {
  /// Service mode entry window (device listens for 10 seconds after boot)
  static const Duration entryWindow = Duration(seconds: 10);

  /// Interval for enter_service_mode retries (send frequently to catch window)
  static const Duration entryRetryInterval = Duration(milliseconds: 200);

  /// Standard command timeout
  static const Duration standardCommand = Duration(seconds: 10);

  /// Status beacon poll timeout
  static const Duration beaconPoll = Duration(seconds: 5);

  /// Wi-Fi test timeout (device may need 15s DHCP timeout + retry)
  static const Duration wifiTest = Duration(seconds: 45);

  /// Cloud test timeout
  static const Duration cloudTest = Duration(seconds: 15);

  /// RFID test timeout
  static const Duration rfidTest = Duration(seconds: 10);

  /// Button test timeout
  static const Duration buttonTest = Duration(seconds: 30);

  /// Test all timeout
  static const Duration testAll = Duration(seconds: 90);

  /// Get timeout for a specific test
  static Duration getTestTimeout(String testName) {
    switch (testName) {
      case 'wifi':
        return wifiTest;
      case 'cloud':
        return cloudTest;
      case 'rfid':
        return rfidTest;
      case 'button':
        return buttonTest;
      default:
        return standardCommand;
    }
  }
}

/// Error codes from protocol
class ServiceModeErrorCodes {
  static const String parseError = 'parse_error';
  static const String invalidCommand = 'invalid_command';
  static const String unknownCommand = 'unknown_command';
  static const String unsupportedCommand = 'unsupported_command';
  static const String missingData = 'missing_data';
  static const String missingFields = 'missing_fields';
  static const String storageError = 'storage_error';
  static const String wifiInitFailed = 'wifi_init_failed';
  static const String wifiConnectFailed = 'wifi_connect_failed';
  static const String wifiTimeout = 'wifi_timeout';
  static const String noWifiConfig = 'no_wifi_config';
  static const String noNetwork = 'no_network';
  static const String notConfigured = 'not_configured';
  static const String notProvisioned = 'not_provisioned';
  static const String requestFailed = 'request_failed';
  static const String windowExpired = 'window_expired';
  static const String notInServiceMode = 'not_in_service_mode';
  static const String rfidCommFailed = 'rfid_comm_failed';
  static const String audioFailed = 'audio_failed';
  static const String buttonTimeout = 'button_timeout';

  /// Get human-readable message for error code
  static String getMessage(String? errorCode) {
    switch (errorCode) {
      case parseError:
        return 'Invalid JSON received';
      case invalidCommand:
        return 'Missing command field';
      case unknownCommand:
        return 'Unrecognized command';
      case unsupportedCommand:
        return 'Command not supported by this device';
      case missingData:
        return 'Command requires data field';
      case missingFields:
        return 'Required fields missing';
      case storageError:
        return 'Failed to store data';
      case wifiInitFailed:
        return 'Wi-Fi initialization failed';
      case wifiConnectFailed:
        return 'Failed to connect to Wi-Fi';
      case wifiTimeout:
        return 'Wi-Fi connection timed out';
      case noWifiConfig:
        return 'No Wi-Fi credentials configured';
      case noNetwork:
        return 'No network connection';
      case notConfigured:
        return 'Cloud credentials not configured';
      case notProvisioned:
        return 'Device not provisioned';
      case requestFailed:
        return 'Network request failed';
      case windowExpired:
        return 'Service mode entry window expired';
      case notInServiceMode:
        return 'Command only valid in service mode';
      case rfidCommFailed:
        return 'RFID module communication failed';
      case audioFailed:
        return 'Audio test failed';
      case buttonTimeout:
        return 'Button press not detected';
      default:
        return errorCode ?? 'Unknown error';
    }
  }
}
