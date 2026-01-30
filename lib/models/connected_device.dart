import 'package:equatable/equatable.dart';

/// Represents a Saturday device detected via USB serial connection.
///
/// This model captures device information from the `get_status` probe
/// when a device is connected. Unlike [Device] (which is a database record),
/// this represents a live USB connection with real-time device state.
class ConnectedDevice extends Equatable {
  /// Serial port name (e.g., /dev/cu.usbserial-1234)
  final String portName;

  /// Primary MAC address from the device
  final String macAddress;

  /// Device serial number (unit_id from provisioning)
  /// Null if device is not yet provisioned
  final String? serialNumber;

  /// Human-friendly product name (e.g., "Crate", "Hub")
  /// Null if device is not yet provisioned
  final String? name;

  /// Device type slug (e.g., "hub", "crate")
  final String deviceType;

  /// Current firmware version
  final String firmwareVersion;

  /// When this device was detected/connected
  final DateTime connectedAt;

  /// Additional status data from get_status response
  final Map<String, dynamic> statusData;

  const ConnectedDevice({
    required this.portName,
    required this.macAddress,
    this.serialNumber,
    this.name,
    required this.deviceType,
    required this.firmwareVersion,
    required this.connectedAt,
    this.statusData = const {},
  });

  /// Whether the device has been factory provisioned
  bool get isProvisioned => serialNumber != null;

  /// Get formatted MAC address (uppercase with colons)
  String get formattedMacAddress => macAddress.toUpperCase();

  /// Get display name: name + last 4 of serial, or just device type if unprovisioned
  String get displayName {
    if (name != null && serialNumber != null) {
      final last4 = serialNumber!.length > 4
          ? serialNumber!.substring(serialNumber!.length - 4)
          : serialNumber!;
      return '$name ($last4)';
    }
    return deviceType;
  }

  /// Get WiFi RSSI if available in status data
  int? get wifiRssi => statusData['wifi_rssi'] as int?;

  /// Get free heap if available in status data
  int? get freeHeap => statusData['free_heap'] as int?;

  /// Get uptime in seconds if available in status data
  int? get uptimeSec => statusData['uptime_sec'] as int?;

  /// Create from get_status response data
  factory ConnectedDevice.fromStatusResponse({
    required String portName,
    required Map<String, dynamic> data,
  }) {
    // Support both 'serial_number' (new protocol) and 'unit_id' (legacy/heartbeat format)
    final serialNumber = data['serial_number'] as String? ?? data['unit_id'] as String?;

    return ConnectedDevice(
      portName: portName,
      macAddress: data['mac_address'] as String? ?? 'unknown',
      serialNumber: serialNumber,
      name: data['name'] as String?,
      deviceType: data['device_type'] as String? ?? 'unknown',
      firmwareVersion: data['firmware_version'] as String? ?? 'unknown',
      connectedAt: DateTime.now(),
      statusData: data,
    );
  }

  /// Copy with updated status data
  ConnectedDevice copyWithStatus(Map<String, dynamic> newStatusData) {
    // Support both 'serial_number' (new protocol) and 'unit_id' (legacy/heartbeat format)
    final newSerialNumber = newStatusData['serial_number'] as String? ??
        newStatusData['unit_id'] as String? ??
        serialNumber;

    return ConnectedDevice(
      portName: portName,
      macAddress: macAddress,
      serialNumber: newSerialNumber,
      name: newStatusData['name'] as String? ?? name,
      deviceType: newStatusData['device_type'] as String? ?? deviceType,
      firmwareVersion:
          newStatusData['firmware_version'] as String? ?? firmwareVersion,
      connectedAt: connectedAt,
      statusData: newStatusData,
    );
  }

  @override
  List<Object?> get props => [
        portName,
        macAddress,
        serialNumber,
        name,
        deviceType,
        firmwareVersion,
        connectedAt,
        statusData,
      ];

  @override
  String toString() =>
      'ConnectedDevice(port: $portName, mac: $macAddress, serial: $serialNumber, type: $deviceType)';
}

/// Event types for USB device monitoring
enum USBDeviceEventType {
  /// A new serial port was detected
  portAdded,

  /// A serial port was removed
  portRemoved,

  /// A Saturday device was identified on a port
  deviceIdentified,

  /// A device was disconnected
  deviceDisconnected,

  /// Failed to identify device on port
  identificationFailed,
}

/// Event emitted by USBMonitorService
class USBDeviceEvent {
  final USBDeviceEventType type;
  final String portName;
  final ConnectedDevice? device;
  final String? error;
  final DateTime timestamp;

  USBDeviceEvent({
    required this.type,
    required this.portName,
    this.device,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'USBDeviceEvent($type, port: $portName, device: ${device?.macAddress})';
}
