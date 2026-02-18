import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/unit.dart';

/// Lightweight model for unit list display in the dashboard
///
/// Combines unit data with primary device engineering telemetry for list rendering.
/// Queries `units` table directly with a `devices` join.
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

  // Consumer-facing telemetry (typed columns on units table, synced by trigger)
  final bool isOnline;
  final DateTime? lastSeenAt;
  final int? batteryLevel;
  final bool? isCharging;
  final int? wifiRssi;
  final double? temperatureC;
  final double? humidityPct;
  final String? firmwareVersion;

  // Primary device data (from devices join)
  final String? primaryDeviceId;
  final String? primaryDeviceMac;
  final String? deviceTypeSlug;

  // Engineering telemetry from primary device (devices.latest_telemetry JSONB)
  final Map<String, dynamic> deviceTelemetry;

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
    this.isOnline = false,
    this.lastSeenAt,
    this.batteryLevel,
    this.isCharging,
    this.wifiRssi,
    this.temperatureC,
    this.humidityPct,
    this.firmwareVersion,
    this.primaryDeviceId,
    this.primaryDeviceMac,
    this.deviceTypeSlug,
    this.deviceTelemetry = const {},
  });

  /// Get display name (device name or serial number or fallback)
  String get displayName =>
      deviceName ?? serialNumber ?? 'Unprovisioned Unit';

  /// Check if unit has a primary device
  bool get hasDevice => primaryDeviceId != null;

  /// Check if unit is claimed by a consumer
  bool get isClaimed => userId != null;

  /// Whether any consumer telemetry data is available
  bool get hasTelemetry =>
      batteryLevel != null || wifiRssi != null || isOnline;

  /// Get the best available signal strength (WiFi preferred, then Thread)
  int? get signalStrength => wifiRssi ?? threadRssi;

  // ─────────────────────────────────────────────────────────────────────────
  // Engineering Telemetry Accessors (from devices.latest_telemetry JSONB)
  // ─────────────────────────────────────────────────────────────────────────

  /// Thread RSSI signal strength (typically -30 to -90 dBm)
  int? get threadRssi {
    final value = deviceTelemetry['thread_rssi'];
    if (value is int) return value;
    if (value is double) return value.round();
    return null;
  }

  /// Device uptime in seconds since boot
  int? get uptimeSec {
    final value = deviceTelemetry['uptime_sec'];
    if (value is int) return value;
    if (value is double) return value.round();
    return null;
  }

  /// Current free heap memory in bytes
  int? get freeHeap {
    final value = deviceTelemetry['free_heap'];
    if (value is int) return value;
    if (value is double) return value.round();
    return null;
  }

  /// Minimum free heap since boot (detects memory leaks)
  int? get minFreeHeap {
    final value = deviceTelemetry['min_free_heap'];
    if (value is int) return value;
    if (value is double) return value.round();
    return null;
  }

  /// Largest contiguous free block (detects heap fragmentation)
  int? get largestFreeBlock {
    final value = deviceTelemetry['largest_free_block'];
    if (value is int) return value;
    if (value is double) return value.round();
    return null;
  }

  /// Device type slug from telemetry
  String? get telemetryDeviceType => deviceTelemetry['device_type'] as String?;

  /// Check if any engineering telemetry data is available
  bool get hasDeviceTelemetry => deviceTelemetry.isNotEmpty;

  // ─────────────────────────────────────────────────────────────────────────
  // JSON Serialization
  // ─────────────────────────────────────────────────────────────────────────

  /// Create from JSON (units table with devices join)
  factory UnitListItem.fromJson(Map<String, dynamic> json) {
    // Parse primary device from joined devices array
    Map<String, dynamic>? primaryDevice;
    if (json['devices'] is List && (json['devices'] as List).isNotEmpty) {
      primaryDevice =
          (json['devices'] as List).first as Map<String, dynamic>;
    }

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
      // Consumer telemetry from typed unit columns
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
      // Primary device data from join
      primaryDeviceId: primaryDevice?['id'] as String?,
      primaryDeviceMac: primaryDevice?['mac_address'] as String?,
      deviceTypeSlug: primaryDevice?['device_type_slug'] as String?,
      // Engineering telemetry from device
      deviceTelemetry: primaryDevice?['latest_telemetry'] != null
          ? Map<String, dynamic>.from(
              primaryDevice!['latest_telemetry'] as Map)
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
      'is_online': isOnline,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'battery_level': batteryLevel,
      'is_charging': isCharging,
      'wifi_rssi': wifiRssi,
      'temperature_c': temperatureC,
      'humidity_pct': humidityPct,
      'firmware_version': firmwareVersion,
      'primary_device_id': primaryDeviceId,
      'primary_device_mac': primaryDeviceMac,
      'device_type_slug': deviceTypeSlug,
      'device_telemetry': deviceTelemetry,
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
    bool? isOnline,
    DateTime? lastSeenAt,
    int? batteryLevel,
    bool? isCharging,
    int? wifiRssi,
    double? temperatureC,
    double? humidityPct,
    String? firmwareVersion,
    String? primaryDeviceId,
    String? primaryDeviceMac,
    String? deviceTypeSlug,
    Map<String, dynamic>? deviceTelemetry,
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
      isOnline: isOnline ?? this.isOnline,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      wifiRssi: wifiRssi ?? this.wifiRssi,
      temperatureC: temperatureC ?? this.temperatureC,
      humidityPct: humidityPct ?? this.humidityPct,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      primaryDeviceId: primaryDeviceId ?? this.primaryDeviceId,
      primaryDeviceMac: primaryDeviceMac ?? this.primaryDeviceMac,
      deviceTypeSlug: deviceTypeSlug ?? this.deviceTypeSlug,
      deviceTelemetry: deviceTelemetry ?? this.deviceTelemetry,
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
        isOnline,
        lastSeenAt,
        batteryLevel,
        isCharging,
        wifiRssi,
        temperatureC,
        humidityPct,
        firmwareVersion,
        primaryDeviceId,
        primaryDeviceMac,
        deviceTypeSlug,
        deviceTelemetry,
      ];

  @override
  String toString() =>
      'UnitListItem(id: $id, serialNumber: $serialNumber, isOnline: $isOnline)';
}
