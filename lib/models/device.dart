import 'package:equatable/equatable.dart';

import 'hardware_device.dart';

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

/// Connectivity status derived from heartbeat staleness.
///
/// This represents the app's understanding of device connectivity based on
/// how recently a heartbeat was received, rather than the database status field.
enum ConnectivityStatus {
  /// Device has sent a heartbeat within the expected interval.
  online,

  /// Device hasn't sent a heartbeat recently but may still be connected.
  /// Shown after [Device.maybeOfflineThreshold] without a heartbeat.
  uncertain,

  /// Device is definitively offline.
  /// Either explicitly marked offline or no heartbeat for [Device.offlineThreshold].
  offline,

  /// Device requires initial setup.
  setupRequired,
}

/// Represents a Saturday device from the user's perspective.
///
/// This is a combined view that joins data from the `units` table (ownership,
/// naming, provisioning) with the `devices` table (hardware, firmware, telemetry).
///
/// For backwards compatibility, this class also supports parsing from the legacy
/// `consumer_devices` table format.
class Device extends Equatable {
  /// Duration after which a device is considered "maybe offline" if no heartbeat.
  static const Duration maybeOfflineThreshold = Duration(minutes: 5);

  /// Duration after which a device is definitively considered offline.
  static const Duration offlineThreshold = Duration(minutes: 10);

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

  // === Hardware info (from devices table) ===

  /// MAC address of the hardware device.
  final String? macAddress;

  /// Current firmware version.
  final String? firmwareVersion;

  /// Battery level (0-100), only applicable for battery-powered devices.
  final int? batteryLevel;

  /// When the device was last seen (heartbeat received).
  final DateTime? lastSeenAt;

  /// Full telemetry data from latest heartbeat.
  final DeviceTelemetry? telemetry;

  // === Metadata ===

  /// When the unit was created (factory provisioning time).
  final DateTime createdAt;

  /// Provision data (WiFi, Thread config) - stored for reference.
  /// Uses flattened structure: { wifi_ssid, thread_dataset, thread_network_name }
  final Map<String, dynamic>? provisionData;

  /// Legacy consumer attributes field (for backwards compatibility).
  @Deprecated('Use provisionData instead')
  final Map<String, dynamic>? consumerAttributes;

  /// Legacy settings field (for backwards compatibility).
  @Deprecated('Use provisionData instead')
  final Map<String, dynamic>? settings;

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
    this.lastSeenAt,
    this.telemetry,
    required this.createdAt,
    this.provisionData,
    this.consumerAttributes,
    this.settings,
  });

  /// Parse from legacy consumer_devices table format.
  ///
  /// This is used for backwards compatibility during migration.
  @Deprecated('Use Device.fromJoinedJson for new unified schema')
  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      deviceType: DeviceType.fromString(json['device_type'] as String?),
      name: json['name'] as String? ?? json['device_name'] as String? ?? '',
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

  /// Parse from joined units + devices query result.
  ///
  /// Expected query format:
  /// ```sql
  /// SELECT *, devices!left(*) FROM units WHERE user_id = ?
  /// ```
  factory Device.fromJoinedJson(Map<String, dynamic> json) {
    // Parse the nested devices array (from LEFT JOIN)
    final devicesList = json['devices'] as List<dynamic>?;
    Map<String, dynamic>? deviceData;
    if (devicesList != null && devicesList.isNotEmpty) {
      deviceData = devicesList.first as Map<String, dynamic>?;
    }

    // Extract telemetry from device data
    DeviceTelemetry? telemetry;
    int? batteryLevel;
    if (deviceData != null && deviceData['latest_telemetry'] != null) {
      telemetry = DeviceTelemetry.fromJson(
          deviceData['latest_telemetry'] as Map<String, dynamic>);
      batteryLevel = telemetry.batteryLevel;
    }

    // Parse serial number
    final serialNumber = json['serial_number'] as String;

    // Derive device type from serial number
    final deviceType = DeviceType.fromSerialNumber(serialNumber);

    // Determine status - prefer device status if provisioned, else unit status
    DeviceStatus status;
    final unitStatus = json['status'] as String?;
    final deviceStatus = deviceData?['status'] as String?;

    // New unit_status enum: 'in_production', 'inventory', 'assigned', 'claimed'
    // 'claimed' means the consumer has fully provisioned the device
    if (unitStatus == 'claimed' && deviceData != null) {
      // Unit is provisioned, check hardware device status
      if (deviceStatus == 'online') {
        status = DeviceStatus.online;
      } else if (deviceStatus == 'offline') {
        status = DeviceStatus.offline;
      } else {
        // Fallback to checking lastSeenAt
        final lastSeenStr = deviceData['last_seen_at'] as String?;
        if (lastSeenStr != null) {
          final lastSeen = DateTime.parse(lastSeenStr);
          final elapsed = DateTime.now().difference(lastSeen);
          status = elapsed < offlineThreshold
              ? DeviceStatus.online
              : DeviceStatus.offline;
        } else {
          status = DeviceStatus.offline;
        }
      }
    } else {
      // Unit not fully provisioned (in_production, inventory, or assigned)
      status = DeviceStatus.setupRequired;
    }

    // Extract provision_data from the device (not the unit)
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
      firmwareVersion: deviceData?['firmware_version'] as String?,
      status: status,
      batteryLevel: batteryLevel,
      lastSeenAt: deviceData?['last_seen_at'] != null
          ? DateTime.parse(deviceData!['last_seen_at'] as String)
          : null,
      telemetry: telemetry,
      createdAt: DateTime.parse(json['created_at'] as String),
      provisionData: provisionData,
      // Support legacy consumer_attributes for backwards compatibility
      consumerAttributes: json['consumer_attributes'] as Map<String, dynamic>?,
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
      'last_seen_at': lastSeenAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'provision_data': provisionData,
      'consumer_attributes': consumerAttributes,
      'settings': settings,
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
    DateTime? lastSeenAt,
    DeviceTelemetry? telemetry,
    DateTime? createdAt,
    Map<String, dynamic>? provisionData,
    Map<String, dynamic>? consumerAttributes,
    Map<String, dynamic>? settings,
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
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      telemetry: telemetry ?? this.telemetry,
      createdAt: createdAt ?? this.createdAt,
      provisionData: provisionData ?? this.provisionData,
      consumerAttributes: consumerAttributes ?? this.consumerAttributes,
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

  /// Time since the last heartbeat was received.
  Duration? get timeSinceLastSeen {
    if (lastSeenAt == null) return null;
    return DateTime.now().difference(lastSeenAt!);
  }

  /// Whether the device's heartbeat is stale (past the maybe-offline threshold).
  bool get isHeartbeatStale {
    final elapsed = timeSinceLastSeen;
    if (elapsed == null) return true; // Never seen = stale
    return elapsed >= maybeOfflineThreshold;
  }

  /// Whether the device's heartbeat is critically stale (past the offline threshold).
  bool get isHeartbeatCriticallyStale {
    final elapsed = timeSinceLastSeen;
    if (elapsed == null) return true; // Never seen = critically stale
    return elapsed >= offlineThreshold;
  }

  /// The derived connectivity status based on heartbeat staleness.
  ///
  /// This should be used for UI display instead of [status] directly, as it
  /// accounts for devices that may have disconnected without sending an
  /// explicit offline signal.
  ConnectivityStatus get connectivityStatus {
    // Setup required takes precedence
    if (status == DeviceStatus.setupRequired) {
      return ConnectivityStatus.setupRequired;
    }

    // If explicitly offline in DB, it's offline
    if (status == DeviceStatus.offline) {
      return ConnectivityStatus.offline;
    }

    // Device claims to be online - verify with heartbeat
    if (isHeartbeatCriticallyStale) {
      return ConnectivityStatus.offline;
    }

    if (isHeartbeatStale) {
      return ConnectivityStatus.uncertain;
    }

    return ConnectivityStatus.online;
  }

  /// Whether this device is effectively online based on heartbeat.
  ///
  /// Use this instead of [isOnline] when you need to account for
  /// devices that may have disconnected without sending an offline signal.
  bool get isEffectivelyOnline =>
      connectivityStatus == ConnectivityStatus.online;

  /// Whether this device's connectivity is uncertain (maybe offline).
  bool get isConnectivityUncertain =>
      connectivityStatus == ConnectivityStatus.uncertain;

  /// WiFi RSSI from telemetry (convenience accessor).
  int? get wifiRssi => telemetry?.wifiRssi;

  /// Thread RSSI from telemetry (convenience accessor).
  int? get threadRssi => telemetry?.threadRssi;

  /// Device uptime in seconds from telemetry.
  int? get uptimeSec => telemetry?.uptimeSec;

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
        lastSeenAt,
        telemetry,
        createdAt,
        provisionData,
        consumerAttributes,
        settings,
      ];
}
