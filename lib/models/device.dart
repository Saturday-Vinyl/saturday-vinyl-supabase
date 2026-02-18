import 'package:equatable/equatable.dart';

/// Device status enum - tracks provisioning lifecycle
enum DeviceStatus {
  unprovisioned,
  provisioned,
}

/// Extension to convert DeviceStatus to/from database string
extension DeviceStatusExtension on DeviceStatus {
  String get databaseValue {
    switch (this) {
      case DeviceStatus.unprovisioned:
        return 'unprovisioned';
      case DeviceStatus.provisioned:
        return 'provisioned';
    }
  }

  static DeviceStatus fromString(String? value) {
    switch (value) {
      case 'provisioned':
      case 'online': // legacy value, treat as provisioned
      case 'offline': // legacy value, treat as provisioned
        return DeviceStatus.provisioned;
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

  /// Device type slug (e.g., "hub", "crate") - references device_types.slug
  final String? deviceTypeSlug;

  /// Link to the unit this device belongs to
  final String? unitId;

  /// Firmware tracking
  final String? firmwareVersion;
  final String? firmwareId;

  /// Factory provisioning data
  final DateTime? factoryProvisionedAt;
  final String? factoryProvisionedBy;

  /// Consumer provisioning data
  final DateTime? consumerProvisionedAt;
  final String? consumerProvisionedBy;

  /// All provisioning data (factory + consumer merged flat)
  final Map<String, dynamic> provisionData;

  /// Status
  final DeviceStatus status;

  /// Connectivity tracking
  final DateTime? lastSeenAt;

  /// Latest telemetry data from heartbeats (flat structure)
  final Map<String, dynamic> latestTelemetry;

  /// Timestamps
  final DateTime createdAt;
  final DateTime? updatedAt;

  const Device({
    required this.id,
    required this.macAddress,
    this.deviceTypeSlug,
    this.unitId,
    this.firmwareVersion,
    this.firmwareId,
    this.factoryProvisionedAt,
    this.factoryProvisionedBy,
    this.consumerProvisionedAt,
    this.consumerProvisionedBy,
    this.provisionData = const {},
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
  bool get isProvisioned => status == DeviceStatus.provisioned;

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
      deviceTypeSlug: json['device_type_slug'] as String?,
      unitId: json['unit_id'] as String?,
      firmwareVersion: json['firmware_version'] as String?,
      firmwareId: json['firmware_id'] as String?,
      factoryProvisionedAt: json['factory_provisioned_at'] != null
          ? DateTime.parse(json['factory_provisioned_at'] as String)
          : null,
      factoryProvisionedBy: json['factory_provisioned_by'] as String?,
      consumerProvisionedAt: json['consumer_provisioned_at'] != null
          ? DateTime.parse(json['consumer_provisioned_at'] as String)
          : null,
      consumerProvisionedBy: json['consumer_provisioned_by'] as String?,
      provisionData: json['provision_data'] != null
          ? Map<String, dynamic>.from(json['provision_data'] as Map)
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
      'device_type_slug': deviceTypeSlug,
      'unit_id': unitId,
      'firmware_version': firmwareVersion,
      'firmware_id': firmwareId,
      'factory_provisioned_at': factoryProvisionedAt?.toIso8601String(),
      'factory_provisioned_by': factoryProvisionedBy,
      'consumer_provisioned_at': consumerProvisionedAt?.toIso8601String(),
      'consumer_provisioned_by': consumerProvisionedBy,
      'provision_data': provisionData,
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
      'device_type_slug': deviceTypeSlug,
      'unit_id': unitId,
      'firmware_version': firmwareVersion,
      'firmware_id': firmwareId,
      'provision_data': provisionData,
      'status': status.databaseValue,
    };
  }

  /// Copy with method for immutability
  Device copyWith({
    String? id,
    String? macAddress,
    String? deviceTypeSlug,
    String? unitId,
    String? firmwareVersion,
    String? firmwareId,
    DateTime? factoryProvisionedAt,
    String? factoryProvisionedBy,
    DateTime? consumerProvisionedAt,
    String? consumerProvisionedBy,
    Map<String, dynamic>? provisionData,
    DeviceStatus? status,
    DateTime? lastSeenAt,
    Map<String, dynamic>? latestTelemetry,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Device(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      deviceTypeSlug: deviceTypeSlug ?? this.deviceTypeSlug,
      unitId: unitId ?? this.unitId,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      firmwareId: firmwareId ?? this.firmwareId,
      factoryProvisionedAt: factoryProvisionedAt ?? this.factoryProvisionedAt,
      factoryProvisionedBy: factoryProvisionedBy ?? this.factoryProvisionedBy,
      consumerProvisionedAt: consumerProvisionedAt ?? this.consumerProvisionedAt,
      consumerProvisionedBy: consumerProvisionedBy ?? this.consumerProvisionedBy,
      provisionData: provisionData ?? this.provisionData,
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
        deviceTypeSlug,
        unitId,
        firmwareVersion,
        firmwareId,
        factoryProvisionedAt,
        factoryProvisionedBy,
        consumerProvisionedAt,
        consumerProvisionedBy,
        provisionData,
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
