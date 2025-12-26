import 'package:equatable/equatable.dart';
import 'package:saturday_app/config/rfid_config.dart';

/// Settings for the RFID module connection and configuration
class RfidSettings extends Equatable {
  /// Serial port name (e.g., '/dev/tty.usbserial-0001', 'COM3')
  final String? port;

  /// Baud rate for serial communication
  final int baudRate;

  /// RF power level in dBm (0-30)
  final int rfPower;

  /// Access password for tag operations (hex string, 8 characters = 4 bytes)
  /// Stored separately in secure storage, this is just for in-memory use
  final String? accessPassword;

  const RfidSettings({
    this.port,
    this.baudRate = RfidConfig.defaultBaudRate,
    this.rfPower = RfidConfig.defaultRfPower,
    this.accessPassword,
  });

  /// Create settings with default values
  factory RfidSettings.defaults() {
    return const RfidSettings(
      port: null,
      baudRate: RfidConfig.defaultBaudRate,
      rfPower: RfidConfig.defaultRfPower,
      accessPassword: null,
    );
  }

  /// Check if a port is configured
  bool get hasPort => port != null && port!.isNotEmpty;

  /// Check if an access password is set
  bool get hasAccessPassword =>
      accessPassword != null && accessPassword!.isNotEmpty;

  /// Get access password as bytes (4 bytes)
  ///
  /// Returns null if no password set or invalid format
  List<int>? get accessPasswordBytes {
    if (accessPassword == null || accessPassword!.length != 8) {
      return null;
    }

    try {
      final bytes = <int>[];
      for (var i = 0; i < 8; i += 2) {
        bytes.add(int.parse(accessPassword!.substring(i, i + 2), radix: 16));
      }
      return bytes;
    } catch (e) {
      return null;
    }
  }

  /// Validate the access password format
  ///
  /// Must be exactly 8 hex characters (representing 4 bytes / 32 bits)
  static bool isValidAccessPassword(String? password) {
    if (password == null || password.isEmpty) {
      return true; // Empty/null is valid (means no password)
    }
    if (password.length != 8) {
      return false;
    }
    // Check if all characters are valid hex
    return RegExp(r'^[0-9A-Fa-f]{8}$').hasMatch(password);
  }

  /// Create a copy with updated values
  RfidSettings copyWith({
    String? port,
    int? baudRate,
    int? rfPower,
    String? accessPassword,
    bool clearPort = false,
    bool clearAccessPassword = false,
  }) {
    return RfidSettings(
      port: clearPort ? null : (port ?? this.port),
      baudRate: baudRate ?? this.baudRate,
      rfPower: rfPower ?? this.rfPower,
      accessPassword: clearAccessPassword
          ? null
          : (accessPassword ?? this.accessPassword),
    );
  }

  @override
  List<Object?> get props => [port, baudRate, rfPower, accessPassword];

  @override
  String toString() {
    return 'RfidSettings(port: $port, baudRate: $baudRate, rfPower: $rfPower, hasPassword: $hasAccessPassword)';
  }
}
