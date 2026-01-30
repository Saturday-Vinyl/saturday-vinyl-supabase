import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/connected_device.dart';

/// State for global USB device monitoring
class USBMonitorState extends Equatable {
  /// Whether the monitor is actively scanning for devices
  final bool isMonitoring;

  /// Map of port name to connected Saturday device
  final Map<String, ConnectedDevice> connectedDevices;

  /// Last error message (if any)
  final String? error;

  /// When the last scan occurred
  final DateTime? lastScanAt;

  const USBMonitorState({
    this.isMonitoring = false,
    this.connectedDevices = const {},
    this.error,
    this.lastScanAt,
  });

  /// Number of connected devices
  int get deviceCount => connectedDevices.length;

  /// Whether any devices are connected
  bool get hasDevices => connectedDevices.isNotEmpty;

  /// List of all connected devices
  List<ConnectedDevice> get devices => connectedDevices.values.toList();

  /// Get provisioned devices only
  List<ConnectedDevice> get provisionedDevices =>
      devices.where((d) => d.isProvisioned).toList();

  /// Get unprovisioned devices only
  List<ConnectedDevice> get unprovisionedDevices =>
      devices.where((d) => !d.isProvisioned).toList();

  /// Find device by MAC address
  ConnectedDevice? findByMac(String macAddress) {
    final normalizedMac = macAddress.toUpperCase();
    for (final device in connectedDevices.values) {
      if (device.macAddress.toUpperCase() == normalizedMac) {
        return device;
      }
    }
    return null;
  }

  /// Find device by serial number
  ConnectedDevice? findBySerialNumber(String serialNumber) {
    for (final device in connectedDevices.values) {
      if (device.serialNumber == serialNumber) {
        return device;
      }
    }
    return null;
  }

  /// Copy with updated fields
  USBMonitorState copyWith({
    bool? isMonitoring,
    Map<String, ConnectedDevice>? connectedDevices,
    String? error,
    DateTime? lastScanAt,
    bool clearError = false,
  }) {
    return USBMonitorState(
      isMonitoring: isMonitoring ?? this.isMonitoring,
      connectedDevices: connectedDevices ?? this.connectedDevices,
      error: clearError ? null : (error ?? this.error),
      lastScanAt: lastScanAt ?? this.lastScanAt,
    );
  }

  /// Add or update a connected device
  USBMonitorState withDevice(ConnectedDevice device) {
    return copyWith(
      connectedDevices: {
        ...connectedDevices,
        device.portName: device,
      },
    );
  }

  /// Remove a device by port name
  USBMonitorState withoutDevice(String portName) {
    final updated = Map<String, ConnectedDevice>.from(connectedDevices);
    updated.remove(portName);
    return copyWith(connectedDevices: updated);
  }

  @override
  List<Object?> get props => [
        isMonitoring,
        connectedDevices,
        error,
        lastScanAt,
      ];

  @override
  String toString() =>
      'USBMonitorState(monitoring: $isMonitoring, devices: $deviceCount)';
}
