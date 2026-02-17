import 'package:equatable/equatable.dart';

/// Status of a hardware device.
enum HardwareDeviceStatus {
  /// Device has not been provisioned.
  unprovisioned,

  /// Device has been factory provisioned.
  provisioned,

  /// Device is currently online (recent heartbeat).
  online,

  /// Device is offline (no recent heartbeat).
  offline;

  static HardwareDeviceStatus fromString(String? value) {
    switch (value) {
      case 'unprovisioned':
        return HardwareDeviceStatus.unprovisioned;
      case 'provisioned':
        return HardwareDeviceStatus.provisioned;
      case 'online':
        return HardwareDeviceStatus.online;
      case 'offline':
        return HardwareDeviceStatus.offline;
      default:
        return HardwareDeviceStatus.unprovisioned;
    }
  }

  String toJsonString() {
    switch (this) {
      case HardwareDeviceStatus.unprovisioned:
        return 'unprovisioned';
      case HardwareDeviceStatus.provisioned:
        return 'provisioned';
      case HardwareDeviceStatus.online:
        return 'online';
      case HardwareDeviceStatus.offline:
        return 'offline';
    }
  }
}

/// Flattened telemetry data from device heartbeats.
///
/// This represents the latest telemetry received from a device.
/// The format is flattened (not capability-scoped).
///
/// Consumer apps should read telemetry from the typed columns on the `units`
/// table instead. This class is retained for `HardwareDevice` parsing.
@Deprecated('Consumer apps should read telemetry from units table columns')
class DeviceTelemetry extends Equatable {
  /// Unit identifier reported by the device.
  final String? unitId;

  /// Device type reported by the device (e.g., "hub-prototype").
  final String? deviceType;

  /// Battery level (0-100), null for powered devices.
  final int? batteryLevel;

  /// Whether the device is currently charging.
  final bool? batteryCharging;

  /// WiFi signal strength in dBm.
  final int? wifiRssi;

  /// Thread signal strength in dBm.
  final int? threadRssi;

  /// Device uptime in seconds.
  final int? uptimeSec;

  /// Current free heap memory in bytes.
  final int? freeHeap;

  /// Minimum free heap seen since boot in bytes.
  final int? minFreeHeap;

  /// Largest contiguous free block in bytes.
  final int? largestFreeBlock;

  const DeviceTelemetry({
    this.unitId,
    this.deviceType,
    this.batteryLevel,
    this.batteryCharging,
    this.wifiRssi,
    this.threadRssi,
    this.uptimeSec,
    this.freeHeap,
    this.minFreeHeap,
    this.largestFreeBlock,
  });

  /// Whether the device has a low battery (below 20%).
  bool get isLowBattery => batteryLevel != null && batteryLevel! < 20;

  /// Whether the device is battery powered (has battery telemetry).
  bool get isBatteryPowered => batteryLevel != null;

  /// WiFi signal strength as bars (0-4).
  int get wifiSignalBars {
    if (wifiRssi == null) return 0;
    if (wifiRssi! >= -50) return 4;
    if (wifiRssi! >= -60) return 3;
    if (wifiRssi! >= -70) return 2;
    if (wifiRssi! >= -80) return 1;
    return 0;
  }

  factory DeviceTelemetry.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DeviceTelemetry();
    return DeviceTelemetry(
      unitId: json['unit_id'] as String?,
      deviceType: json['device_type'] as String?,
      batteryLevel: json['battery_level'] as int?,
      batteryCharging: json['battery_charging'] as bool?,
      wifiRssi: json['wifi_rssi'] as int?,
      threadRssi: json['thread_rssi'] as int?,
      uptimeSec: json['uptime_sec'] as int?,
      freeHeap: json['free_heap'] as int?,
      minFreeHeap: json['min_free_heap'] as int?,
      largestFreeBlock: json['largest_free_block'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'unit_id': unitId,
      'device_type': deviceType,
      'battery_level': batteryLevel,
      'battery_charging': batteryCharging,
      'wifi_rssi': wifiRssi,
      'thread_rssi': threadRssi,
      'uptime_sec': uptimeSec,
      'free_heap': freeHeap,
      'min_free_heap': minFreeHeap,
      'largest_free_block': largestFreeBlock,
    };
  }

  @override
  List<Object?> get props => [
        unitId,
        deviceType,
        batteryLevel,
        batteryCharging,
        wifiRssi,
        threadRssi,
        uptimeSec,
        freeHeap,
        minFreeHeap,
        largestFreeBlock,
      ];
}

/// Represents a physical hardware device (PCB) identified by MAC address.
///
/// A device is a piece of hardware that belongs to a unit (product).
/// A unit can have multiple devices (e.g., a board with multiple SoCs).
/// Devices are the target for commands and heartbeats.
class HardwareDevice extends Equatable {
  /// Database ID.
  final String id;

  /// Primary identifier: MAC address of the device.
  final String macAddress;

  /// Link to the unit this device belongs to.
  final String? unitId;

  /// Device type ID (template defining capabilities).
  final String? deviceTypeId;

  /// Current firmware version.
  final String? firmwareVersion;

  /// Device status.
  final HardwareDeviceStatus status;

  /// When the device was last seen (heartbeat received).
  final DateTime? lastSeenAt;

  /// Latest telemetry data from heartbeats.
  final DeviceTelemetry? telemetry;

  /// When the device record was created.
  final DateTime createdAt;

  const HardwareDevice({
    required this.id,
    required this.macAddress,
    this.unitId,
    this.deviceTypeId,
    this.firmwareVersion,
    this.status = HardwareDeviceStatus.unprovisioned,
    this.lastSeenAt,
    this.telemetry,
    required this.createdAt,
  });

  /// Battery level from telemetry (convenience accessor).
  int? get batteryLevel => telemetry?.batteryLevel;

  /// Whether the device has a low battery.
  bool get isLowBattery => telemetry?.isLowBattery ?? false;

  /// Formatted MAC address (with colons, uppercase).
  String get formattedMacAddress => macAddress.toUpperCase();

  factory HardwareDevice.fromJson(Map<String, dynamic> json) {
    return HardwareDevice(
      id: json['id'] as String,
      macAddress: json['mac_address'] as String,
      unitId: json['unit_id'] as String?,
      deviceTypeId: json['device_type_id'] as String?,
      firmwareVersion: json['firmware_version'] as String?,
      status: HardwareDeviceStatus.fromString(json['status'] as String?),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      telemetry: json['latest_telemetry'] != null
          ? DeviceTelemetry.fromJson(
              json['latest_telemetry'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mac_address': macAddress,
      'unit_id': unitId,
      'device_type_id': deviceTypeId,
      'firmware_version': firmwareVersion,
      'status': status.toJsonString(),
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'latest_telemetry': telemetry?.toJson(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  HardwareDevice copyWith({
    String? id,
    String? macAddress,
    String? unitId,
    String? deviceTypeId,
    String? firmwareVersion,
    HardwareDeviceStatus? status,
    DateTime? lastSeenAt,
    DeviceTelemetry? telemetry,
    DateTime? createdAt,
  }) {
    return HardwareDevice(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      unitId: unitId ?? this.unitId,
      deviceTypeId: deviceTypeId ?? this.deviceTypeId,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      status: status ?? this.status,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      telemetry: telemetry ?? this.telemetry,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        macAddress,
        unitId,
        deviceTypeId,
        firmwareVersion,
        status,
        lastSeenAt,
        telemetry,
        createdAt,
      ];
}
