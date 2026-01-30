import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/connected_device.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/services/device_communication_service.dart';

/// Connection phase for device communication
///
/// This is a simplified state machine compared to the legacy ServiceModePhase,
/// since devices now use an always-listening architecture.
enum DeviceCommunicationPhase {
  /// No device connected
  disconnected,

  /// Connecting to serial port
  connecting,

  /// Connected and ready for commands
  connected,

  /// Executing a command
  executing,

  /// Error state
  error,
}

extension DeviceCommunicationPhaseExtension on DeviceCommunicationPhase {
  bool get isDisconnected => this == DeviceCommunicationPhase.disconnected;
  bool get isConnecting => this == DeviceCommunicationPhase.connecting;
  bool get isConnected => this == DeviceCommunicationPhase.connected;
  bool get isExecuting => this == DeviceCommunicationPhase.executing;
  bool get isError => this == DeviceCommunicationPhase.error;

  /// Whether we can send commands (connected or executing)
  bool get canSendCommands =>
      this == DeviceCommunicationPhase.connected ||
      this == DeviceCommunicationPhase.executing;

  String get displayName {
    switch (this) {
      case DeviceCommunicationPhase.disconnected:
        return 'Disconnected';
      case DeviceCommunicationPhase.connecting:
        return 'Connecting...';
      case DeviceCommunicationPhase.connected:
        return 'Connected';
      case DeviceCommunicationPhase.executing:
        return 'Executing...';
      case DeviceCommunicationPhase.error:
        return 'Error';
    }
  }
}

/// Test result for capability tests
class TestResult {
  final String capability;
  final String testName;
  final bool passed;
  final String? message;
  final Map<String, dynamic> data;
  final Duration duration;
  final DateTime timestamp;

  TestResult({
    required this.capability,
    required this.testName,
    required this.passed,
    this.message,
    this.data = const {},
    required this.duration,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory TestResult.fromResponse(
    String capability,
    String testName,
    CommandResponse response,
    Duration duration,
  ) {
    return TestResult(
      capability: capability,
      testName: testName,
      passed: response.isSuccess,
      message: response.message,
      data: response.data,
      duration: duration,
    );
  }

  String get displayKey => '$capability:$testName';
}

/// State for device communication session
class DeviceCommunicationState extends Equatable {
  /// Current connection phase
  final DeviceCommunicationPhase phase;

  /// Serial port name
  final String? portName;

  /// Connected device info (from get_status)
  final ConnectedDevice? connectedDevice;

  /// Associated unit (looked up from device serial number)
  final Unit? associatedUnit;

  /// Current command being executed
  final String? currentCommand;

  /// Test results keyed by "capability:testName"
  final Map<String, TestResult> testResults;

  /// Log lines from communication
  final List<String> logLines;

  /// Error message if in error state
  final String? errorMessage;

  /// Last successful get_status timestamp
  final DateTime? lastStatusAt;

  const DeviceCommunicationState({
    this.phase = DeviceCommunicationPhase.disconnected,
    this.portName,
    this.connectedDevice,
    this.associatedUnit,
    this.currentCommand,
    this.testResults = const {},
    this.logLines = const [],
    this.errorMessage,
    this.lastStatusAt,
  });

  /// Whether currently connected to a device
  bool get isConnected => phase.canSendCommands;

  /// Whether the device is unprovisioned (no serial number)
  bool get isUnprovisioned =>
      connectedDevice != null && !connectedDevice!.isProvisioned;

  /// Whether we can provision this device
  bool get canProvision => isConnected && isUnprovisioned;

  /// Whether we have a unit context (for provisioned devices)
  bool get hasUnitContext => associatedUnit != null;

  /// Get display name for the connected device
  String? get deviceDisplayName => connectedDevice?.displayName;

  /// Copy with updated fields
  DeviceCommunicationState copyWith({
    DeviceCommunicationPhase? phase,
    String? portName,
    ConnectedDevice? connectedDevice,
    Unit? associatedUnit,
    String? currentCommand,
    Map<String, TestResult>? testResults,
    List<String>? logLines,
    String? errorMessage,
    DateTime? lastStatusAt,
    bool clearPortName = false,
    bool clearConnectedDevice = false,
    bool clearAssociatedUnit = false,
    bool clearCurrentCommand = false,
    bool clearErrorMessage = false,
  }) {
    return DeviceCommunicationState(
      phase: phase ?? this.phase,
      portName: clearPortName ? null : (portName ?? this.portName),
      connectedDevice: clearConnectedDevice
          ? null
          : (connectedDevice ?? this.connectedDevice),
      associatedUnit:
          clearAssociatedUnit ? null : (associatedUnit ?? this.associatedUnit),
      currentCommand:
          clearCurrentCommand ? null : (currentCommand ?? this.currentCommand),
      testResults: testResults ?? this.testResults,
      logLines: logLines ?? this.logLines,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      lastStatusAt: lastStatusAt ?? this.lastStatusAt,
    );
  }

  /// Add a log line
  DeviceCommunicationState addLog(String line) {
    return copyWith(logLines: [...logLines, line]);
  }

  /// Clear logs
  DeviceCommunicationState clearLogs() {
    return copyWith(logLines: []);
  }

  /// Add a test result
  DeviceCommunicationState addTestResult(TestResult result) {
    return copyWith(
      testResults: {...testResults, result.displayKey: result},
    );
  }

  @override
  List<Object?> get props => [
        phase,
        portName,
        connectedDevice,
        associatedUnit,
        currentCommand,
        testResults,
        logLines,
        errorMessage,
        lastStatusAt,
      ];

  @override
  String toString() =>
      'DeviceCommunicationState(phase: $phase, port: $portName, device: ${connectedDevice?.macAddress})';
}
