import 'package:equatable/equatable.dart';

/// Status of the serial port connection
enum SerialConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

/// Represents the current state of a serial port connection
class SerialConnectionState extends Equatable {
  final SerialConnectionStatus status;
  final String? portName;
  final int? baudRate;
  final String? errorMessage;
  final bool isModuleEnabled;

  const SerialConnectionState({
    required this.status,
    this.portName,
    this.baudRate,
    this.errorMessage,
    this.isModuleEnabled = false,
  });

  /// Initial disconnected state
  static const SerialConnectionState initial = SerialConnectionState(
    status: SerialConnectionStatus.disconnected,
  );

  /// Check if currently connected
  bool get isConnected => status == SerialConnectionStatus.connected;

  /// Check if currently connecting
  bool get isConnecting => status == SerialConnectionStatus.connecting;

  /// Check if in error state
  bool get hasError => status == SerialConnectionStatus.error;

  /// Check if disconnected (not connected, not connecting, no error)
  bool get isDisconnected => status == SerialConnectionStatus.disconnected;

  SerialConnectionState copyWith({
    SerialConnectionStatus? status,
    String? portName,
    int? baudRate,
    String? errorMessage,
    bool? isModuleEnabled,
    bool clearError = false,
    bool clearPort = false,
  }) {
    return SerialConnectionState(
      status: status ?? this.status,
      portName: clearPort ? null : (portName ?? this.portName),
      baudRate: clearPort ? null : (baudRate ?? this.baudRate),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isModuleEnabled: isModuleEnabled ?? this.isModuleEnabled,
    );
  }

  @override
  List<Object?> get props => [
        status,
        portName,
        baudRate,
        errorMessage,
        isModuleEnabled,
      ];

  @override
  String toString() {
    return 'SerialConnectionState(status: $status, port: $portName, baud: $baudRate, moduleEnabled: $isModuleEnabled${errorMessage != null ? ', error: $errorMessage' : ''})';
  }
}
