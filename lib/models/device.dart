import 'package:equatable/equatable.dart';

/// Type of Saturday device.
enum DeviceType {
  hub,
  crate;

  static DeviceType fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'hub':
        return DeviceType.hub;
      case 'crate':
      case 'crt':
        return DeviceType.crate;
      default:
        return DeviceType.hub;
    }
  }

  /// Parse device type from serial number prefix.
  ///
  /// Format: SV-{TYPE}-{NUMBER}
  /// - SV-HUB-XXXXX -> hub
  /// - SV-CRT-XXXXX -> crate
  static DeviceType fromSerialNumber(String serialNumber) {
    final parts = serialNumber.split('-');
    if (parts.length >= 2) {
      switch (parts[1].toUpperCase()) {
        case 'HUB':
          return DeviceType.hub;
        case 'CRT':
        case 'CRATE':
          return DeviceType.crate;
      }
    }
    return DeviceType.hub;
  }
}

/// Status of a device as stored in the database.
enum DeviceStatus {
  online,
  offline,
  setupRequired;

  static DeviceStatus fromString(String? value) {
    switch (value) {
      case 'online':
        return DeviceStatus.online;
      case 'offline':
        return DeviceStatus.offline;
      case 'setup_required':
        return DeviceStatus.setupRequired;
      // Handle unit_status enum values
      case 'claimed':
        return DeviceStatus.online;
      case 'assigned':
        return DeviceStatus.setupRequired;
      case 'inventory':
        return DeviceStatus.setupRequired;
      case 'in_production':
        return DeviceStatus.setupRequired;
      // Legacy unit statuses (for backwards compatibility)
      case 'user_claimed':
        return DeviceStatus.setupRequired;
      case 'user_provisioned':
        return DeviceStatus.online;
      case 'factory_provisioned':
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

/// Connectivity status of a device.
///
/// Determined server-side: `is_online` is set true by the heartbeat trigger
/// and set false by a 1-minute cron job.
enum ConnectivityStatus {
  /// Device is online (recent heartbeat received).
  online,

  /// Device is offline.
  offline,

  /// Device requires initial setup.
  setupRequired,
}

/// Represents a Saturday device from the user's perspective.
///
/// This is a combined view that reads ownership/naming/provisioning and
/// telemetry data from the `units` table, with an optional join to `devices`
/// for hardware-level detail (MAC address, provision data).
class Device extends Equatable {
  // === Identification (from units table) ===

  /// Unit ID (primary identifier).
  final String id;

  /// User who owns this device.
  final String userId;

  /// Device serial number (e.g., SV-HUB-000001).
  final String serialNumber;

  /// User-friendly device name.
  final String name;

  /// Device type (hub or crate).
  final DeviceType deviceType;

  /// Device status.
  final DeviceStatus status;

  // === Hardware info (from devices join) ===

  /// MAC address of the hardware device.
  final String? macAddress;

  // === Telemetry (from units table columns) ===

  /// Current firmware version.
  final String? firmwareVersion;

  /// Battery level (0-100), only applicable for battery-powered devices.
  final int? batteryLevel;

  /// Whether the device is currently online (from `units.is_online`).
  final bool? isOnlineDb;

  /// Whether the device is currently charging.
  final bool? isCharging;

  /// WiFi signal strength in dBm.
  final int? wifiRssi;

  /// Temperature in Celsius.
  final double? temperatureC;

  /// Humidity percentage.
  final double? humidityPct;

  /// When the device was last seen (heartbeat received).
  final DateTime? lastSeenAt;

  // === Metadata ===

  /// When the unit was created (factory provisioning time).
  final DateTime createdAt;

  /// Provision data (WiFi, Thread config) - stored for reference.
  /// Uses flattened structure: { wifi_ssid, thread_dataset, thread_network_name }
  final Map<String, dynamic>? provisionData;

  const Device({
    required this.id,
    required this.userId,
    required this.deviceType,
    required this.name,
    required this.serialNumber,
    this.macAddress,
    this.firmwareVersion,
    this.status = DeviceStatus.offline,
    this.batteryLevel,
    this.isOnlineDb,
    this.isCharging,
    this.wifiRssi,
    this.temperatureC,
    this.humidityPct,
    this.lastSeenAt,
    required this.createdAt,
    this.provisionData,
  });

  /// Parse from legacy consumer_devices table or cache format.
  @Deprecated('Use Device.fromJoinedJson for new unified schema')
  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      deviceType: DeviceType.fromString(json['device_type'] as String?),
      name: json['name'] as String? ?? json['device_name'] as String? ?? '',
      serialNumber: json['serial_number'] as String? ?? '',
      firmwareVersion: json['firmware_version'] as String?,
      status: DeviceStatus.fromString(json['status'] as String? ?? 'offline'),
      batteryLevel: json['battery_level'] as int?,
      isOnlineDb: json['is_online'] as bool?,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.parse(json['last_seen_at'] as String)
          : null,
      createdAt: DateTime.parse(
          json['created_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  /// Parse from joined units + devices query result.
  ///
  /// Telemetry fields are read directly from the unit row columns.
  /// The `devices` join is only used for `mac_address` and `provision_data`.
  ///
  /// Expected query format:
  /// ```sql
  /// SELECT *, devices!left(mac_address, provision_data) FROM units WHERE consumer_user_id = ?
  /// ```
  factory Device.fromJoinedJson(Map<String, dynamic> json) {
    // Parse the nested devices array (from LEFT JOIN) — only for mac_address & provision_data
    final devicesList = json['devices'] as List<dynamic>?;
    Map<String, dynamic>? deviceData;
    if (devicesList != null && devicesList.isNotEmpty) {
      deviceData = devicesList.first as Map<String, dynamic>?;
    }

    final serialNumber = json['serial_number'] as String;
    final deviceType = DeviceType.fromSerialNumber(serialNumber);

    // Read telemetry directly from unit row columns
    final isOnlineDb = json['is_online'] as bool?;
    final batteryLevel = json['battery_level'] as int?;
    final isCharging = json['is_charging'] as bool?;
    final wifiRssi = json['wifi_rssi'] as int?;
    final temperatureC = (json['temperature_c'] as num?)?.toDouble();
    final humidityPct = (json['humidity_pct'] as num?)?.toDouble();
    final firmwareVersion = json['firmware_version'] as String?;
    final lastSeenAt = json['last_seen_at'] != null
        ? DateTime.parse(json['last_seen_at'] as String)
        : null;

    // Determine status from unit_status enum + is_online flag
    // unit_status: 'in_production', 'inventory', 'assigned', 'claimed'
    DeviceStatus status;
    final unitStatus = json['status'] as String?;
    if (unitStatus == 'claimed') {
      status = (isOnlineDb == true) ? DeviceStatus.online : DeviceStatus.offline;
    } else {
      status = DeviceStatus.setupRequired;
    }

    // Extract provision_data from the device join
    Map<String, dynamic>? provisionData;
    if (deviceData != null && deviceData['provision_data'] != null) {
      provisionData = deviceData['provision_data'] as Map<String, dynamic>?;
    }

    return Device(
      id: json['id'] as String,
      userId: json['consumer_user_id'] as String,
      deviceType: deviceType,
      name: json['consumer_name'] as String? ?? serialNumber,
      serialNumber: serialNumber,
      macAddress: deviceData?['mac_address'] as String?,
      firmwareVersion: firmwareVersion,
      status: status,
      batteryLevel: batteryLevel,
      isOnlineDb: isOnlineDb,
      isCharging: isCharging,
      wifiRssi: wifiRssi,
      temperatureC: temperatureC,
      humidityPct: humidityPct,
      lastSeenAt: lastSeenAt,
      createdAt: DateTime.parse(json['created_at'] as String),
      provisionData: provisionData,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'device_type': deviceType.name,
      'name': name,
      'serial_number': serialNumber,
      'mac_address': macAddress,
      'firmware_version': firmwareVersion,
      'status': status.toJsonString(),
      'battery_level': batteryLevel,
      'is_online': isOnlineDb,
      'is_charging': isCharging,
      'wifi_rssi': wifiRssi,
      'temperature_c': temperatureC,
      'humidity_pct': humidityPct,
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'provision_data': provisionData,
    };
  }

  Device copyWith({
    String? id,
    String? userId,
    DeviceType? deviceType,
    String? name,
    String? serialNumber,
    String? macAddress,
    String? firmwareVersion,
    DeviceStatus? status,
    int? batteryLevel,
    bool? isOnlineDb,
    bool? isCharging,
    int? wifiRssi,
    double? temperatureC,
    double? humidityPct,
    DateTime? lastSeenAt,
    DateTime? createdAt,
    Map<String, dynamic>? provisionData,
  }) {
    return Device(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      deviceType: deviceType ?? this.deviceType,
      name: name ?? this.name,
      serialNumber: serialNumber ?? this.serialNumber,
      macAddress: macAddress ?? this.macAddress,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      status: status ?? this.status,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isOnlineDb: isOnlineDb ?? this.isOnlineDb,
      isCharging: isCharging ?? this.isCharging,
      wifiRssi: wifiRssi ?? this.wifiRssi,
      temperatureC: temperatureC ?? this.temperatureC,
      humidityPct: humidityPct ?? this.humidityPct,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      createdAt: createdAt ?? this.createdAt,
      provisionData: provisionData ?? this.provisionData,
    );
  }

  /// Whether this device is a hub.
  bool get isHub => deviceType == DeviceType.hub;

  /// Whether this device is a crate.
  bool get isCrate => deviceType == DeviceType.crate;

  /// Whether this device is currently online (from backend `is_online` column).
  bool get isOnline => isOnlineDb == true;

  /// Whether this device requires setup.
  bool get needsSetup => status == DeviceStatus.setupRequired;

  /// Whether this device has a low battery (below 20%).
  bool get isLowBattery => batteryLevel != null && batteryLevel! < 20;

  /// The connectivity status, determined server-side.
  ConnectivityStatus get connectivityStatus {
    if (status == DeviceStatus.setupRequired) {
      return ConnectivityStatus.setupRequired;
    }
    if (isOnlineDb == true) {
      return ConnectivityStatus.online;
    }
    return ConnectivityStatus.offline;
  }

  /// Whether this device is effectively online.
  bool get isEffectivelyOnline => isOnlineDb == true;

  @override
  List<Object?> get props => [
        id,
        userId,
        deviceType,
        name,
        serialNumber,
        macAddress,
        firmwareVersion,
        status,
        batteryLevel,
        isOnlineDb,
        isCharging,
        wifiRssi,
        temperatureC,
        humidityPct,
        lastSeenAt,
        createdAt,
        provisionData,
      ];
}
