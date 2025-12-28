import 'package:equatable/equatable.dart';

/// Type of Saturday device.
enum DeviceType {
  hub,
  crate;

  static DeviceType fromString(String value) {
    return DeviceType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => DeviceType.hub,
    );
  }
}

/// Status of a device.
enum DeviceStatus {
  online,
  offline,
  setupRequired;

  static DeviceStatus fromString(String value) {
    switch (value) {
      case 'online':
        return DeviceStatus.online;
      case 'offline':
        return DeviceStatus.offline;
      case 'setup_required':
        return DeviceStatus.setupRequired;
      default:
        return DeviceStatus.offline;
    }
  }

  String toJsonString() {
    switch (this) {
      case DeviceStatus.online:
        return 'online';
      case DeviceStatus.offline:
        return 'offline';
      case DeviceStatus.setupRequired:
        return 'setup_required';
    }
  }
}

/// Represents a Saturday hardware device.
///
/// Devices can be either hubs (wall-powered, WiFi + Thread border router)
/// or crates (battery-powered, Thread sleepy end devices).
class Device extends Equatable {
  final String id;
  final String userId;
  final DeviceType deviceType;
  final String name;
  final String serialNumber;
  final String? firmwareVersion;
  final DeviceStatus status;

  /// Battery level (0-100), only applicable for battery-powered devices.
  final int? batteryLevel;

  final DateTime? lastSeenAt;
  final DateTime createdAt;
  final Map<String, dynamic>? settings;

  const Device({
    required this.id,
    required this.userId,
    required this.deviceType,
    required this.name,
    required this.serialNumber,
    this.firmwareVersion,
    this.status = DeviceStatus.offline,
    this.batteryLevel,
    this.lastSeenAt,
    required this.createdAt,
    this.settings,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      deviceType: DeviceType.fromString(json['device_type'] as String),
      name: json['name'] as String,
      serialNumber: json['serial_number'] as String,
      firmwareVersion: json['firmware_version'] as String?,
      status: DeviceStatus.fromString(json['status'] as String? ?? 'offline'),
      batteryLevel: json['battery_level'] as int?,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      settings: json['settings'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'device_type': deviceType.name,
      'name': name,
      'serial_number': serialNumber,
      'firmware_version': firmwareVersion,
      'status': status.toJsonString(),
      'battery_level': batteryLevel,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'settings': settings,
    };
  }

  Device copyWith({
    String? id,
    String? userId,
    DeviceType? deviceType,
    String? name,
    String? serialNumber,
    String? firmwareVersion,
    DeviceStatus? status,
    int? batteryLevel,
    DateTime? lastSeenAt,
    DateTime? createdAt,
    Map<String, dynamic>? settings,
  }) {
    return Device(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      deviceType: deviceType ?? this.deviceType,
      name: name ?? this.name,
      serialNumber: serialNumber ?? this.serialNumber,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      status: status ?? this.status,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
      settings: settings ?? this.settings,
    );
  }

  /// Whether this device is a hub.
  bool get isHub => deviceType == DeviceType.hub;

  /// Whether this device is a crate.
  bool get isCrate => deviceType == DeviceType.crate;

  /// Whether this device is currently online.
  bool get isOnline => status == DeviceStatus.online;

  /// Whether this device requires setup.
  bool get needsSetup => status == DeviceStatus.setupRequired;

  /// Whether this device has a low battery (below 20%).
  bool get isLowBattery => batteryLevel != null && batteryLevel! < 20;

  @override
  List<Object?> get props => [
        id,
        userId,
        deviceType,
        name,
        serialNumber,
        firmwareVersion,
        status,
        batteryLevel,
        lastSeenAt,
        createdAt,
        settings,
      ];
}
