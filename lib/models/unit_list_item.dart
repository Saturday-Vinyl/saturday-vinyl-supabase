import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/unit.dart';

/// Lightweight model for unit list display in the dashboard
///
/// Combines unit data with primary device telemetry for efficient list rendering.
/// This model maps to the `units_dashboard` database view.
class UnitListItem extends Equatable {
  final String id;
  final String? serialNumber;
  final String? deviceName;
  final UnitStatus status;
  final String? productId;
  final String? variantId;
  final String? orderId;
  final String? userId;
  final DateTime? factoryProvisionedAt;
  final DateTime? consumerProvisionedAt;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // Primary device data
  final String? primaryDeviceId;
  final String? primaryDeviceMac;
  final String? deviceTypeId;
  final DateTime? lastSeenAt;
  final String? firmwareVersion;
  final Map<String, dynamic> latestTelemetry;

  /// Connected threshold in minutes
  static const int connectedThresholdMinutes = 5;

  const UnitListItem({
    required this.id,
    this.serialNumber,
    this.deviceName,
    required this.status,
    this.productId,
    this.variantId,
    this.orderId,
    this.userId,
    this.factoryProvisionedAt,
    this.consumerProvisionedAt,
    this.isCompleted = false,
    required this.createdAt,
    this.updatedAt,
    this.primaryDeviceId,
    this.primaryDeviceMac,
    this.deviceTypeId,
    this.lastSeenAt,
    this.firmwareVersion,
    this.latestTelemetry = const {},
  });

  /// Check if the unit's primary device is connected (seen within threshold)
  bool get isConnected {
    if (lastSeenAt == null) return false;
    return DateTime.now().difference(lastSeenAt!).inMinutes <
        connectedThresholdMinutes;
  }

  /// Get display name (device name or serial number or fallback)
  String get displayName =>
      deviceName ?? serialNumber ?? 'Unprovisioned Unit';

  /// Check if unit has a primary device
  bool get hasDevice => primaryDeviceId != null;

  /// Check if unit is claimed by a consumer
  bool get isClaimed => userId != null;

  // ─────────────────────────────────────────────────────────────────────────
  // Telemetry Accessors (capability-scoped)
  // ─────────────────────────────────────────────────────────────────────────

  /// Get a telemetry value from a specific capability
  dynamic _getTelemetryValue(String capability, String field) {
    final cap = latestTelemetry[capability];
    if (cap is Map) return cap[field];
    return null;
  }

  /// Battery level percentage (0-100) from 'power' capability
  int? get batteryLevel {
    final value = _getTelemetryValue('power', 'battery_level');
    if (value is int) return value;
    if (value is double) return value.round();
    return null;
  }

  /// WiFi RSSI signal strength (typically -30 to -90 dBm) from 'wifi' capability
  int? get rssi {
    final value = _getTelemetryValue('wifi', 'rssi');
    if (value is int) return value;
    if (value is double) return value.round();
    return null;
  }

  /// Temperature in Celsius from 'environment' capability
  double? get temperature {
    final value = _getTelemetryValue('environment', 'temperature');
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return null;
  }

  /// Humidity percentage (0-100) from 'environment' capability
  double? get humidity {
    final value = _getTelemetryValue('environment', 'humidity');
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return null;
  }

  /// Check if any telemetry data is available
  bool get hasTelemetry => latestTelemetry.isNotEmpty;

  // ─────────────────────────────────────────────────────────────────────────
  // JSON Serialization
  // ─────────────────────────────────────────────────────────────────────────

  /// Create from JSON (maps to units_dashboard view)
  factory UnitListItem.fromJson(Map<String, dynamic> json) {
    return UnitListItem(
      id: json['id'] as String,
      serialNumber: json['serial_number'] as String?,
      deviceName: json['device_name'] as String?,
      status: UnitStatusExtension.fromString(json['status'] as String?),
      productId: json['product_id'] as String?,
      variantId: json['variant_id'] as String?,
      orderId: json['order_id'] as String?,
      userId: json['user_id'] as String?,
      factoryProvisionedAt: json['factory_provisioned_at'] != null
          ? DateTime.parse(json['factory_provisioned_at'] as String)
          : null,
      consumerProvisionedAt: json['consumer_provisioned_at'] != null
          ? DateTime.parse(json['consumer_provisioned_at'] as String)
          : null,
      isCompleted: json['is_completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      primaryDeviceId: json['primary_device_id'] as String?,
      primaryDeviceMac: json['primary_device_mac'] as String?,
      deviceTypeId: json['device_type_id'] as String?,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      firmwareVersion: json['firmware_version'] as String?,
      latestTelemetry: json['latest_telemetry'] != null
          ? Map<String, dynamic>.from(json['latest_telemetry'] as Map)
          : {},
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serial_number': serialNumber,
      'device_name': deviceName,
      'status': status.databaseValue,
      'product_id': productId,
      'variant_id': variantId,
      'order_id': orderId,
      'user_id': userId,
      'factory_provisioned_at': factoryProvisionedAt?.toIso8601String(),
      'consumer_provisioned_at': consumerProvisionedAt?.toIso8601String(),
      'is_completed': isCompleted,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'primary_device_id': primaryDeviceId,
      'primary_device_mac': primaryDeviceMac,
      'device_type_id': deviceTypeId,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'firmware_version': firmwareVersion,
      'latest_telemetry': latestTelemetry,
    };
  }

  /// Create a copy with updated fields
  UnitListItem copyWith({
    String? id,
    String? serialNumber,
    String? deviceName,
    UnitStatus? status,
    String? productId,
    String? variantId,
    String? orderId,
    String? userId,
    DateTime? factoryProvisionedAt,
    DateTime? consumerProvisionedAt,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? primaryDeviceId,
    String? primaryDeviceMac,
    String? deviceTypeId,
    DateTime? lastSeenAt,
    String? firmwareVersion,
    Map<String, dynamic>? latestTelemetry,
  }) {
    return UnitListItem(
      id: id ?? this.id,
      serialNumber: serialNumber ?? this.serialNumber,
      deviceName: deviceName ?? this.deviceName,
      status: status ?? this.status,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      orderId: orderId ?? this.orderId,
      userId: userId ?? this.userId,
      factoryProvisionedAt: factoryProvisionedAt ?? this.factoryProvisionedAt,
      consumerProvisionedAt:
          consumerProvisionedAt ?? this.consumerProvisionedAt,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      primaryDeviceId: primaryDeviceId ?? this.primaryDeviceId,
      primaryDeviceMac: primaryDeviceMac ?? this.primaryDeviceMac,
      deviceTypeId: deviceTypeId ?? this.deviceTypeId,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      latestTelemetry: latestTelemetry ?? this.latestTelemetry,
    );
  }

  @override
  List<Object?> get props => [
        id,
        serialNumber,
        deviceName,
        status,
        productId,
        variantId,
        orderId,
        userId,
        factoryProvisionedAt,
        consumerProvisionedAt,
        isCompleted,
        createdAt,
        updatedAt,
        primaryDeviceId,
        primaryDeviceMac,
        deviceTypeId,
        lastSeenAt,
        firmwareVersion,
        latestTelemetry,
      ];

  @override
  String toString() =>
      'UnitListItem(id: $id, serialNumber: $serialNumber, isConnected: $isConnected)';
}
