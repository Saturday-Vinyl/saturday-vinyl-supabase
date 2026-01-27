import 'package:equatable/equatable.dart';

/// Device status enum
enum DeviceStatus {
  unprovisioned,
  provisioned,
  online,
  offline,
}

/// Extension to convert DeviceStatus to/from database string
extension DeviceStatusExtension on DeviceStatus {
  String get databaseValue {
    switch (this) {
      case DeviceStatus.unprovisioned:
        return 'unprovisioned';
      case DeviceStatus.provisioned:
        return 'provisioned';
      case DeviceStatus.online:
        return 'online';
      case DeviceStatus.offline:
        return 'offline';
    }
  }

  static DeviceStatus fromString(String? value) {
    switch (value) {
      case 'provisioned':
        return DeviceStatus.provisioned;
      case 'online':
        return DeviceStatus.online;
      case 'offline':
        return DeviceStatus.offline;
      default:
        return DeviceStatus.unprovisioned;
    }
  }
}

/// Represents a physical hardware device (PCB) identified by MAC address
///
/// A device is a piece of hardware that belongs to a unit (product).
/// A unit can have multiple devices (e.g., a board with multiple SoCs).
/// Devices are the target for commands and heartbeats.
class Device extends Equatable {
  final String id;

  /// Primary identifier: MAC address of the master SoC
  final String macAddress;

  /// Device type (template defining capabilities)
  final String? deviceTypeId;

  /// Link to the unit this device belongs to
  final String? unitId;

  /// Firmware tracking
  final String? firmwareVersion;
  final String? firmwareId;

  /// Factory provisioning data
  final DateTime? factoryProvisionedAt;
  final String? factoryProvisionedBy;
  final Map<String, dynamic> factoryAttributes;

  /// Status
  final DeviceStatus status;

  /// Connectivity tracking
  final DateTime? lastSeenAt;

  /// Latest telemetry data from heartbeats (capability-scoped)
  /// Example: {"power": {"battery_level": 85}, "wifi": {"rssi": -45}}
  final Map<String, dynamic> latestTelemetry;

  /// Timestamps
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Device({
    required this.id,
    required this.macAddress,
    this.deviceTypeId,
    this.unitId,
    this.firmwareVersion,
    this.firmwareId,
    this.factoryProvisionedAt,
    this.factoryProvisionedBy,
    this.factoryAttributes = const {},
    this.status = DeviceStatus.unprovisioned,
    this.lastSeenAt,
    this.latestTelemetry = const {},
    required this.createdAt,
    this.updatedAt,
  });

  /// Check if device is online (last seen within 60 seconds)
  bool get isOnline {
    if (lastSeenAt == null) return false;
    final now = DateTime.now();
    return now.difference(lastSeenAt!).inSeconds < 60;
  }

  /// Get online status as string
  String get onlineStatus {
    if (lastSeenAt == null) return 'unknown';
    return isOnline ? 'online' : 'offline';
  }

  /// Check if device is provisioned
  bool get isProvisioned =>
      status == DeviceStatus.provisioned ||
      status == DeviceStatus.online ||
      status == DeviceStatus.offline;

  /// Get formatted MAC address (with colons)
  String get formattedMacAddress => macAddress.toUpperCase();

  /// Get MAC address formatted for channel name (with dashes)
  String get channelMacAddress => macAddress.replaceAll(':', '-').toUpperCase();

  /// Validate MAC address format
  static bool validateMacAddress(String mac) {
    final pattern = RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$');
    return pattern.hasMatch(mac);
  }

  /// Create from JSON
  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      macAddress: json['mac_address'] as String,
      deviceTypeId: json['device_type_id'] as String?,
      unitId: json['unit_id'] as String?,
      firmwareVersion: json['firmware_version'] as String?,
      firmwareId: json['firmware_id'] as String?,
      factoryProvisionedAt: json['factory_provisioned_at'] != null
          ? DateTime.parse(json['factory_provisioned_at'] as String)
          : null,
      factoryProvisionedBy: json['factory_provisioned_by'] as String?,
      factoryAttributes: json['factory_attributes'] != null
          ? Map<String, dynamic>.from(json['factory_attributes'] as Map)
          : {},
      status: DeviceStatusExtension.fromString(json['status'] as String?),
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      latestTelemetry: json['latest_telemetry'] != null
          ? Map<String, dynamic>.from(json['latest_telemetry'] as Map)
          : {},
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mac_address': macAddress,
      'device_type_id': deviceTypeId,
      'unit_id': unitId,
      'firmware_version': firmwareVersion,
      'firmware_id': firmwareId,
      'factory_provisioned_at': factoryProvisionedAt?.toIso8601String(),
      'factory_provisioned_by': factoryProvisionedBy,
      'factory_attributes': factoryAttributes,
      'status': status.databaseValue,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'latest_telemetry': latestTelemetry,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// Convert to JSON for insertion (without id, timestamps)
  Map<String, dynamic> toInsertJson() {
    return {
      'mac_address': macAddress,
      'device_type_id': deviceTypeId,
      'unit_id': unitId,
      'firmware_version': firmwareVersion,
      'firmware_id': firmwareId,
      'factory_attributes': factoryAttributes,
      'status': status.databaseValue,
    };
  }

  /// Copy with method for immutability
  Device copyWith({
    String? id,
    String? macAddress,
    String? deviceTypeId,
    String? unitId,
    String? firmwareVersion,
    String? firmwareId,
    DateTime? factoryProvisionedAt,
    String? factoryProvisionedBy,
    Map<String, dynamic>? factoryAttributes,
    DeviceStatus? status,
    DateTime? lastSeenAt,
    Map<String, dynamic>? latestTelemetry,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Device(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      deviceTypeId: deviceTypeId ?? this.deviceTypeId,
      unitId: unitId ?? this.unitId,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      firmwareId: firmwareId ?? this.firmwareId,
      factoryProvisionedAt: factoryProvisionedAt ?? this.factoryProvisionedAt,
      factoryProvisionedBy: factoryProvisionedBy ?? this.factoryProvisionedBy,
      factoryAttributes: factoryAttributes ?? this.factoryAttributes,
      status: status ?? this.status,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      latestTelemetry: latestTelemetry ?? this.latestTelemetry,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        macAddress,
        deviceTypeId,
        unitId,
        firmwareVersion,
        firmwareId,
        factoryProvisionedAt,
        factoryProvisionedBy,
        factoryAttributes,
        status,
        lastSeenAt,
        latestTelemetry,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'Device(id: $id, macAddress: $macAddress, status: $status, isOnline: $isOnline)';
}
