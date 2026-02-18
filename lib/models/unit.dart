import 'package:equatable/equatable.dart';

/// Unit status enum representing lifecycle stages
enum UnitStatus {
  unprovisioned,
  factoryProvisioned,
  userProvisioned,
}

/// Extension to convert UnitStatus to/from database string
extension UnitStatusExtension on UnitStatus {
  String get databaseValue {
    switch (this) {
      case UnitStatus.unprovisioned:
        return 'unprovisioned';
      case UnitStatus.factoryProvisioned:
        return 'factory_provisioned';
      case UnitStatus.userProvisioned:
        return 'user_provisioned';
    }
  }

  static UnitStatus fromString(String? value) {
    switch (value) {
      case 'factory_provisioned':
        return UnitStatus.factoryProvisioned;
      case 'user_provisioned':
        return UnitStatus.userProvisioned;
      default:
        return UnitStatus.unprovisioned;
    }
  }
}

/// Represents a manufactured product unit (e.g., a Saturday Hub, a Saturday Crate)
///
/// This is the unified model that replaces both production_units and consumer_devices.
/// A unit contains one or more devices (hardware instances identified by MAC address).
class Unit extends Equatable {
  final String id;

  /// Serial number is the primary identifier
  /// Format: SV-{PRODUCT_CODE}-{NUMBER} e.g., SV-HUB-000001
  /// Null for unprovisioned units
  final String? serialNumber;

  /// Product association (from Shopify sync)
  final String? productId;
  final String? variantId;

  /// Order association (for build-to-order units)
  final String? orderId;

  /// Factory provisioning
  final DateTime? factoryProvisionedAt;
  final String? factoryProvisionedBy;

  /// Consumer provisioning (set by consumer app)
  final String? userId;
  final DateTime? consumerProvisionedAt;
  final String? deviceName;
  final Map<String, dynamic> consumerAttributes;

  /// Status tracks the unit lifecycle
  final UnitStatus status;

  /// Telemetry (synced from primary device by heartbeat trigger)
  final bool isOnline;
  final DateTime? lastSeenAt;
  final int? batteryLevel;
  final bool? isCharging;
  final int? wifiRssi;
  final double? temperatureC;
  final double? humidityPct;
  final String? firmwareVersion;

  /// Production workflow (backwards compatibility)
  final DateTime? productionStartedAt;
  final DateTime? productionCompletedAt;
  final bool isCompleted;
  final String? qrCodeUrl;

  /// Timestamps
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  const Unit({
    required this.id,
    this.serialNumber,
    this.productId,
    this.variantId,
    this.orderId,
    this.factoryProvisionedAt,
    this.factoryProvisionedBy,
    this.userId,
    this.consumerProvisionedAt,
    this.deviceName,
    this.consumerAttributes = const {},
    this.status = UnitStatus.unprovisioned,
    this.isOnline = false,
    this.lastSeenAt,
    this.batteryLevel,
    this.isCharging,
    this.wifiRssi,
    this.temperatureC,
    this.humidityPct,
    this.firmwareVersion,
    this.productionStartedAt,
    this.productionCompletedAt,
    this.isCompleted = false,
    this.qrCodeUrl,
    required this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  /// Check if unit is in production (started but not completed)
  bool get isInProduction =>
      productionStartedAt != null && productionCompletedAt == null;

  /// Check if unit is claimed by a consumer
  bool get isClaimed => userId != null;

  /// Check if unit is factory provisioned
  bool get isFactoryProvisioned =>
      status == UnitStatus.factoryProvisioned ||
      status == UnitStatus.userProvisioned;

  /// Get formatted display name (device name or serial number)
  String get displayName => deviceName ?? serialNumber ?? 'Unprovisioned Unit';

  /// Validate serial number format (SV-{CODE}-{NUMBER})
  static bool validateSerialNumberFormat(String serialNumber) {
    final pattern = RegExp(r'^SV-[A-Z0-9]+-\d{5,}$');
    return pattern.hasMatch(serialNumber);
  }

  /// Create from JSON
  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      id: json['id'] as String,
      serialNumber: json['serial_number'] as String?,
      productId: json['product_id'] as String?,
      variantId: json['variant_id'] as String?,
      orderId: json['order_id'] as String?,
      factoryProvisionedAt: json['factory_provisioned_at'] != null
          ? DateTime.parse(json['factory_provisioned_at'] as String)
          : null,
      factoryProvisionedBy: json['factory_provisioned_by'] as String?,
      userId: json['user_id'] as String?,
      consumerProvisionedAt: json['consumer_provisioned_at'] != null
          ? DateTime.parse(json['consumer_provisioned_at'] as String)
          : null,
      deviceName: json['device_name'] as String?,
      consumerAttributes: json['consumer_attributes'] != null
          ? Map<String, dynamic>.from(json['consumer_attributes'] as Map)
          : {},
      status: UnitStatusExtension.fromString(json['status'] as String?),
      isOnline: json['is_online'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      batteryLevel: json['battery_level'] as int?,
      isCharging: json['is_charging'] as bool?,
      wifiRssi: json['wifi_rssi'] as int?,
      temperatureC: (json['temperature_c'] as num?)?.toDouble(),
      humidityPct: (json['humidity_pct'] as num?)?.toDouble(),
      firmwareVersion: json['firmware_version'] as String?,
      productionStartedAt: json['production_started_at'] != null
          ? DateTime.parse(json['production_started_at'] as String)
          : null,
      productionCompletedAt: json['production_completed_at'] != null
          ? DateTime.parse(json['production_completed_at'] as String)
          : null,
      isCompleted: json['is_completed'] as bool? ?? false,
      qrCodeUrl: json['qr_code_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      createdBy: json['created_by'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serial_number': serialNumber,
      'product_id': productId,
      'variant_id': variantId,
      'order_id': orderId,
      'factory_provisioned_at': factoryProvisionedAt?.toIso8601String(),
      'factory_provisioned_by': factoryProvisionedBy,
      'user_id': userId,
      'consumer_provisioned_at': consumerProvisionedAt?.toIso8601String(),
      'device_name': deviceName,
      'consumer_attributes': consumerAttributes,
      'status': status.databaseValue,
      'is_online': isOnline,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'battery_level': batteryLevel,
      'is_charging': isCharging,
      'wifi_rssi': wifiRssi,
      'temperature_c': temperatureC,
      'humidity_pct': humidityPct,
      'firmware_version': firmwareVersion,
      'production_started_at': productionStartedAt?.toIso8601String(),
      'production_completed_at': productionCompletedAt?.toIso8601String(),
      'is_completed': isCompleted,
      'qr_code_url': qrCodeUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'created_by': createdBy,
    };
  }

  /// Convert to JSON for insertion (without id, timestamps)
  Map<String, dynamic> toInsertJson() {
    return {
      'serial_number': serialNumber,
      'product_id': productId,
      'variant_id': variantId,
      'order_id': orderId,
      'status': status.databaseValue,
      'production_started_at': productionStartedAt?.toIso8601String(),
      'qr_code_url': qrCodeUrl,
      'created_by': createdBy,
    };
  }

  /// Copy with method for immutability
  Unit copyWith({
    String? id,
    String? serialNumber,
    String? productId,
    String? variantId,
    String? orderId,
    DateTime? factoryProvisionedAt,
    String? factoryProvisionedBy,
    String? userId,
    DateTime? consumerProvisionedAt,
    String? deviceName,
    Map<String, dynamic>? consumerAttributes,
    UnitStatus? status,
    bool? isOnline,
    DateTime? lastSeenAt,
    int? batteryLevel,
    bool? isCharging,
    int? wifiRssi,
    double? temperatureC,
    double? humidityPct,
    String? firmwareVersion,
    DateTime? productionStartedAt,
    DateTime? productionCompletedAt,
    bool? isCompleted,
    String? qrCodeUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return Unit(
      id: id ?? this.id,
      serialNumber: serialNumber ?? this.serialNumber,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      orderId: orderId ?? this.orderId,
      factoryProvisionedAt: factoryProvisionedAt ?? this.factoryProvisionedAt,
      factoryProvisionedBy: factoryProvisionedBy ?? this.factoryProvisionedBy,
      userId: userId ?? this.userId,
      consumerProvisionedAt:
          consumerProvisionedAt ?? this.consumerProvisionedAt,
      deviceName: deviceName ?? this.deviceName,
      consumerAttributes: consumerAttributes ?? this.consumerAttributes,
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      wifiRssi: wifiRssi ?? this.wifiRssi,
      temperatureC: temperatureC ?? this.temperatureC,
      humidityPct: humidityPct ?? this.humidityPct,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      productionStartedAt: productionStartedAt ?? this.productionStartedAt,
      productionCompletedAt:
          productionCompletedAt ?? this.productionCompletedAt,
      isCompleted: isCompleted ?? this.isCompleted,
      qrCodeUrl: qrCodeUrl ?? this.qrCodeUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        serialNumber,
        productId,
        variantId,
        orderId,
        factoryProvisionedAt,
        factoryProvisionedBy,
        userId,
        consumerProvisionedAt,
        deviceName,
        consumerAttributes,
        status,
        isOnline,
        lastSeenAt,
        batteryLevel,
        isCharging,
        wifiRssi,
        temperatureC,
        humidityPct,
        firmwareVersion,
        productionStartedAt,
        productionCompletedAt,
        isCompleted,
        qrCodeUrl,
        createdAt,
        updatedAt,
        createdBy,
      ];

  @override
  String toString() =>
      'Unit(id: $id, serialNumber: $serialNumber, status: $status)';
}
