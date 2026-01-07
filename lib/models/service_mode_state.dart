import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/models/service_mode_manifest.dart';

/// Phases of service mode operation
enum ServiceModePhase {
  /// Not connected to any device
  disconnected,

  /// Connecting to serial port
  connecting,

  /// Connected, waiting for device response
  waitingForDevice,

  /// Sending enter_service_mode command during boot window
  enteringServiceMode,

  /// Device is in service mode, ready for commands
  inServiceMode,

  /// Connected in monitor-only mode (watching logs, not in service mode)
  monitoring,

  /// Executing a command (provisioning, testing, reset, etc.)
  executingCommand,

  /// An error occurred
  error;

  String get displayName {
    switch (this) {
      case ServiceModePhase.disconnected:
        return 'Disconnected';
      case ServiceModePhase.connecting:
        return 'Connecting...';
      case ServiceModePhase.waitingForDevice:
        return 'Waiting for Device';
      case ServiceModePhase.enteringServiceMode:
        return 'Entering Service Mode';
      case ServiceModePhase.inServiceMode:
        return 'Service Mode Active';
      case ServiceModePhase.monitoring:
        return 'Monitoring';
      case ServiceModePhase.executingCommand:
        return 'Executing Command';
      case ServiceModePhase.error:
        return 'Error';
    }
  }

  bool get isConnected =>
      this != ServiceModePhase.disconnected &&
      this != ServiceModePhase.connecting;

  bool get isActive => this == ServiceModePhase.inServiceMode;

  bool get isMonitoring => this == ServiceModePhase.monitoring;

  bool get isBusy =>
      this == ServiceModePhase.connecting ||
      this == ServiceModePhase.waitingForDevice ||
      this == ServiceModePhase.enteringServiceMode ||
      this == ServiceModePhase.executingCommand;
}

/// Device information from beacon or get_status response
class DeviceInfo extends Equatable {
  final String deviceType;
  final String? firmwareId; // UUID linking to firmware_versions table
  final String firmwareVersion;
  final String macAddress;
  final String? unitId;
  final bool cloudConfigured;
  final String? cloudUrl;
  final bool wifiConfigured;
  final bool wifiConnected;
  final String? wifiSsid;
  final int? wifiRssi;
  final String? ipAddress;
  final bool? bluetoothEnabled;
  final bool? threadConfigured;
  final bool? threadConnected;
  final int? freeHeap;
  final int? uptimeMs;
  final int? batteryLevel;
  final bool? batteryCharging;
  final Map<String, bool>? lastTests;

  const DeviceInfo({
    required this.deviceType,
    this.firmwareId,
    required this.firmwareVersion,
    required this.macAddress,
    this.unitId,
    this.cloudConfigured = false,
    this.cloudUrl,
    this.wifiConfigured = false,
    this.wifiConnected = false,
    this.wifiSsid,
    this.wifiRssi,
    this.ipAddress,
    this.bluetoothEnabled,
    this.threadConfigured,
    this.threadConnected,
    this.freeHeap,
    this.uptimeMs,
    this.batteryLevel,
    this.batteryCharging,
    this.lastTests,
  });

  /// Whether device has been provisioned (has unit_id)
  bool get isProvisioned => unitId != null && unitId!.isNotEmpty;

  /// Create from device beacon or get_status response
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    // Parse last_tests map
    Map<String, bool>? lastTests;
    if (json['last_tests'] is Map<String, dynamic>) {
      final testsJson = json['last_tests'] as Map<String, dynamic>;
      lastTests = {};
      for (final entry in testsJson.entries) {
        if (entry.value is bool) {
          lastTests[entry.key] = entry.value as bool;
        }
      }
    }

    return DeviceInfo(
      deviceType: json['device_type'] as String? ?? 'unknown',
      firmwareId: json['firmware_id'] as String?,
      firmwareVersion: json['firmware_version'] as String? ?? '0.0.0',
      macAddress: json['mac_address'] as String? ?? '',
      unitId: json['unit_id'] as String?,
      cloudConfigured: json['cloud_configured'] as bool? ?? false,
      cloudUrl: json['cloud_url'] as String?,
      wifiConfigured: json['wifi_configured'] as bool? ?? false,
      wifiConnected: json['wifi_connected'] as bool? ?? false,
      wifiSsid: json['wifi_ssid'] as String?,
      wifiRssi: json['wifi_rssi'] as int?,
      ipAddress: json['ip_address'] as String?,
      bluetoothEnabled: json['bluetooth_enabled'] as bool?,
      threadConfigured: json['thread_configured'] as bool?,
      threadConnected: json['thread_connected'] as bool?,
      freeHeap: json['free_heap'] as int?,
      uptimeMs: json['uptime_ms'] as int?,
      batteryLevel: json['battery_level'] as int?,
      batteryCharging: json['battery_charging'] as bool?,
      lastTests: lastTests,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_type': deviceType,
      if (firmwareId != null) 'firmware_id': firmwareId,
      'firmware_version': firmwareVersion,
      'mac_address': macAddress,
      if (unitId != null) 'unit_id': unitId,
      'cloud_configured': cloudConfigured,
      if (cloudUrl != null) 'cloud_url': cloudUrl,
      'wifi_configured': wifiConfigured,
      'wifi_connected': wifiConnected,
      if (wifiSsid != null) 'wifi_ssid': wifiSsid,
      if (wifiRssi != null) 'wifi_rssi': wifiRssi,
      if (ipAddress != null) 'ip_address': ipAddress,
      if (bluetoothEnabled != null) 'bluetooth_enabled': bluetoothEnabled,
      if (threadConfigured != null) 'thread_configured': threadConfigured,
      if (threadConnected != null) 'thread_connected': threadConnected,
      if (freeHeap != null) 'free_heap': freeHeap,
      if (uptimeMs != null) 'uptime_ms': uptimeMs,
      if (batteryLevel != null) 'battery_level': batteryLevel,
      if (batteryCharging != null) 'battery_charging': batteryCharging,
      if (lastTests != null) 'last_tests': lastTests,
    };
  }

  /// Format uptime as human-readable string
  String get formattedUptime {
    if (uptimeMs == null) return 'Unknown';
    final seconds = uptimeMs! ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '${minutes}m ${seconds % 60}s';
    final hours = minutes ~/ 60;
    return '${hours}h ${minutes % 60}m';
  }

  /// Format free heap as human-readable string
  String get formattedFreeHeap {
    if (freeHeap == null) return 'Unknown';
    if (freeHeap! > 1024 * 1024) {
      return '${(freeHeap! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (freeHeap! > 1024) {
      return '${(freeHeap! / 1024).toStringAsFixed(1)} KB';
    }
    return '$freeHeap bytes';
  }

  @override
  List<Object?> get props => [
        deviceType,
        firmwareId,
        firmwareVersion,
        macAddress,
        unitId,
        cloudConfigured,
        cloudUrl,
        wifiConfigured,
        wifiConnected,
        wifiSsid,
        wifiRssi,
        ipAddress,
        bluetoothEnabled,
        threadConfigured,
        threadConnected,
        freeHeap,
        uptimeMs,
        batteryLevel,
        batteryCharging,
        lastTests,
      ];

  @override
  String toString() =>
      'DeviceInfo(deviceType: $deviceType, macAddress: $macAddress, unitId: $unitId)';
}

/// Status of an individual test
enum TestStatus {
  pending,
  running,
  passed,
  failed,
  skipped;

  bool get isComplete =>
      this == TestStatus.passed ||
      this == TestStatus.failed ||
      this == TestStatus.skipped;

  bool get isSuccess => this == TestStatus.passed;
}

/// Result of a test operation
class TestResult extends Equatable {
  final String testId;
  final TestStatus status;
  final String? message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  final Duration? duration;

  const TestResult({
    required this.testId,
    required this.status,
    this.message,
    this.data,
    required this.timestamp,
    this.duration,
  });

  bool get isSuccess => status == TestStatus.passed;
  bool get isFailed => status == TestStatus.failed;

  @override
  List<Object?> get props => [testId, status, message, data, timestamp, duration];
}

/// Main state for Service Mode screen
class ServiceModeState extends Equatable {
  final ServiceModePhase phase;
  final String? selectedPort;
  final DeviceInfo? deviceInfo;
  final ServiceModeManifest? manifest;
  final ProductionUnit? associatedUnit;
  final String? currentCommand;
  final Map<String, TestResult> testResults;
  final List<String> logLines;
  final String? errorMessage;
  final DateTime? lastBeaconAt;

  const ServiceModeState({
    this.phase = ServiceModePhase.disconnected,
    this.selectedPort,
    this.deviceInfo,
    this.manifest,
    this.associatedUnit,
    this.currentCommand,
    this.testResults = const {},
    this.logLines = const [],
    this.errorMessage,
    this.lastBeaconAt,
  });

  /// Whether currently connected to a device
  bool get isConnected => phase.isConnected;

  /// Whether device is in service mode
  bool get isInServiceMode => phase.isActive;

  /// Whether currently executing an operation
  bool get isBusy => phase.isBusy;

  /// Whether device is fresh (not provisioned)
  bool get isFreshDevice => deviceInfo != null && !deviceInfo!.isProvisioned;

  /// Whether device is provisioned
  bool get isProvisionedDevice =>
      deviceInfo != null && deviceInfo!.isProvisioned;

  /// Whether we have a production unit associated
  bool get hasAssociatedUnit => associatedUnit != null;

  /// Whether provisioning is possible (fresh device with unit selected)
  bool get canProvision =>
      isInServiceMode && isFreshDevice && hasAssociatedUnit;

  /// Check if a test passed
  bool testPassed(String testId) =>
      testResults[testId]?.status == TestStatus.passed;

  /// Check if a test failed
  bool testFailed(String testId) =>
      testResults[testId]?.status == TestStatus.failed;

  /// Get count of passed tests
  int get passedTestCount =>
      testResults.values.where((r) => r.isSuccess).length;

  /// Get count of failed tests
  int get failedTestCount =>
      testResults.values.where((r) => r.isFailed).length;

  /// Initial state
  factory ServiceModeState.initial() {
    return const ServiceModeState();
  }

  ServiceModeState copyWith({
    ServiceModePhase? phase,
    String? selectedPort,
    DeviceInfo? deviceInfo,
    ServiceModeManifest? manifest,
    ProductionUnit? associatedUnit,
    String? currentCommand,
    Map<String, TestResult>? testResults,
    List<String>? logLines,
    String? errorMessage,
    DateTime? lastBeaconAt,
    bool clearDeviceInfo = false,
    bool clearManifest = false,
    bool clearAssociatedUnit = false,
    bool clearCurrentCommand = false,
    bool clearErrorMessage = false,
  }) {
    return ServiceModeState(
      phase: phase ?? this.phase,
      selectedPort: selectedPort ?? this.selectedPort,
      deviceInfo: clearDeviceInfo ? null : (deviceInfo ?? this.deviceInfo),
      manifest: clearManifest ? null : (manifest ?? this.manifest),
      associatedUnit:
          clearAssociatedUnit ? null : (associatedUnit ?? this.associatedUnit),
      currentCommand:
          clearCurrentCommand ? null : (currentCommand ?? this.currentCommand),
      testResults: testResults ?? this.testResults,
      logLines: logLines ?? this.logLines,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      lastBeaconAt: lastBeaconAt ?? this.lastBeaconAt,
    );
  }

  /// Add a log line
  ServiceModeState addLog(String line) {
    return copyWith(
      logLines: [...logLines, line],
    );
  }

  /// Clear all logs
  ServiceModeState clearLogs() {
    return copyWith(logLines: []);
  }

  /// Update test result
  ServiceModeState updateTestResult(TestResult result) {
    final newResults = Map<String, TestResult>.from(testResults);
    newResults[result.testId] = result;
    return copyWith(testResults: newResults);
  }

  /// Reset for new connection
  ServiceModeState reset() {
    return ServiceModeState(
      selectedPort: selectedPort,
      logLines: logLines,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        selectedPort,
        deviceInfo,
        manifest,
        associatedUnit,
        currentCommand,
        testResults,
        logLines,
        errorMessage,
        lastBeaconAt,
      ];
}
