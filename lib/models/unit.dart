import 'package:equatable/equatable.dart';

/// Status of a unit in its lifecycle.
enum UnitStatus {
  /// Unit has been created but not yet provisioned at factory.
  unprovisioned,

  /// Unit has been provisioned at factory and is ready to be claimed by a consumer.
  factoryProvisioned,

  /// Unit has been claimed by a consumer (user_id set).
  userClaimed,

  /// Unit has been fully provisioned by a consumer (WiFi/Thread configured).
  userProvisioned;

  static UnitStatus fromString(String? value) {
    switch (value) {
      case 'unprovisioned':
        return UnitStatus.unprovisioned;
      case 'factory_provisioned':
        return UnitStatus.factoryProvisioned;
      case 'user_claimed':
        return UnitStatus.userClaimed;
      case 'user_provisioned':
        return UnitStatus.userProvisioned;
      default:
        return UnitStatus.unprovisioned;
    }
  }

  String toJsonString() {
    switch (this) {
      case UnitStatus.unprovisioned:
        return 'unprovisioned';
      case UnitStatus.factoryProvisioned:
        return 'factory_provisioned';
      case UnitStatus.userClaimed:
        return 'user_claimed';
      case UnitStatus.userProvisioned:
        return 'user_provisioned';
    }
  }
}

/// Represents a manufactured product unit (e.g., a Saturday Hub or Crate).
///
/// This is the unified model that replaces both production_units and consumer_devices.
/// A unit contains one or more devices (hardware instances identified by MAC address).
///
/// Units are created during factory provisioning and claimed by consumers when they
/// set up the device via BLE.
class Unit extends Equatable {
  /// Database ID.
  final String id;

  /// Serial number in format SV-{PRODUCT_CODE}-{NUMBER} e.g., SV-HUB-000001.
  final String serialNumber;

  /// Product association (from Shopify sync).
  final String? productId;

  /// ID of the user who owns this unit (null if unclaimed).
  final String? userId;

  /// User-friendly name for the device.
  final String? deviceName;

  /// Unit lifecycle status.
  final UnitStatus status;

  /// When the consumer provisioned this unit via BLE.
  final DateTime? consumerProvisionedAt;

  /// Consumer provisioning data (WiFi, Thread, etc.).
  /// Uses flattened structure: { wifi_ssid, thread_dataset, thread_network_name }
  final Map<String, dynamic>? provisionData;

  /// When the unit was created (factory provisioning time).
  final DateTime createdAt;

  /// When the unit was last updated.
  final DateTime? updatedAt;

  const Unit({
    required this.id,
    required this.serialNumber,
    this.productId,
    this.userId,
    this.deviceName,
    this.status = UnitStatus.unprovisioned,
    this.consumerProvisionedAt,
    this.provisionData,
    required this.createdAt,
    this.updatedAt,
  });

  /// Whether this unit has been claimed by a consumer.
  bool get isClaimed => userId != null;

  /// Whether this unit has been fully provisioned by a consumer.
  bool get isProvisioned => status == UnitStatus.userProvisioned;

  /// Display name (device name if set, otherwise serial number).
  String get displayName => deviceName ?? serialNumber;

  /// Device type derived from serial number prefix.
  ///
  /// Format: SV-{TYPE}-{NUMBER}
  /// - SV-HUB-XXXXX -> hub
  /// - SV-CRT-XXXXX -> crate
  String? get deviceTypeFromSerial {
    final parts = serialNumber.split('-');
    if (parts.length >= 2) {
      switch (parts[1].toUpperCase()) {
        case 'HUB':
          return 'hub';
        case 'CRT':
        case 'CRATE':
          return 'crate';
      }
    }
    return null;
  }

  /// Whether this is a hub based on serial number.
  bool get isHub => deviceTypeFromSerial == 'hub';

  /// Whether this is a crate based on serial number.
  bool get isCrate => deviceTypeFromSerial == 'crate';

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      id: json['id'] as String,
      serialNumber: json['serial_number'] as String,
      productId: json['product_id'] as String?,
      userId: json['user_id'] as String?,
      deviceName: json['device_name'] as String?,
      status: UnitStatus.fromString(json['status'] as String?),
      consumerProvisionedAt: json['consumer_provisioned_at'] != null
          ? DateTime.parse(json['consumer_provisioned_at'] as String)
          : null,
      provisionData: json['provision_data'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serial_number': serialNumber,
      'product_id': productId,
      'user_id': userId,
      'device_name': deviceName,
      'status': status.toJsonString(),
      'consumer_provisioned_at': consumerProvisionedAt?.toIso8601String(),
      'provision_data': provisionData,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Unit copyWith({
    String? id,
    String? serialNumber,
    String? productId,
    String? userId,
    String? deviceName,
    UnitStatus? status,
    DateTime? consumerProvisionedAt,
    Map<String, dynamic>? provisionData,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Unit(
      id: id ?? this.id,
      serialNumber: serialNumber ?? this.serialNumber,
      productId: productId ?? this.productId,
      userId: userId ?? this.userId,
      deviceName: deviceName ?? this.deviceName,
      status: status ?? this.status,
      consumerProvisionedAt:
          consumerProvisionedAt ?? this.consumerProvisionedAt,
      provisionData: provisionData ?? this.provisionData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        serialNumber,
        productId,
        userId,
        deviceName,
        status,
        consumerProvisionedAt,
        provisionData,
        createdAt,
        updatedAt,
      ];
}
