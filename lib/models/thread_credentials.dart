import 'package:equatable/equatable.dart';

/// Thread Border Router credentials captured during Hub provisioning.
///
/// These credentials are used by the mobile app to provision crates (ESP32-H2
/// devices) to join the hub's Thread network.
class ThreadCredentials extends Equatable {
  final String? id;
  final String unitId;

  /// Thread network name (max 16 characters)
  final String networkName;

  /// PAN ID (Personal Area Network identifier, 16-bit value 0-65534)
  final int panId;

  /// Thread radio channel (11-26 for 2.4GHz band)
  final int channel;

  /// Thread Network Key - 128-bit AES key stored as 32 hex characters
  final String networkKey;

  /// Extended PAN ID - 64-bit identifier stored as 16 hex characters
  final String extendedPanId;

  /// Mesh-Local Prefix - 64-bit ULA prefix stored as 16 hex characters
  final String meshLocalPrefix;

  /// Pre-Shared Key for Commissioner - 128-bit key stored as 32 hex characters
  final String pskc;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ThreadCredentials({
    this.id,
    required this.unitId,
    required this.networkName,
    required this.panId,
    required this.channel,
    required this.networkKey,
    required this.extendedPanId,
    required this.meshLocalPrefix,
    required this.pskc,
    this.createdAt,
    this.updatedAt,
  });

  /// Create from the thread object in device get_status response
  ///
  /// Expected format:
  /// ```json
  /// {
  ///   "network_name": "SaturdayVinyl",
  ///   "pan_id": 21334,
  ///   "channel": 15,
  ///   "network_key": "a1b2c3d4e5f6789012345678abcdef12",
  ///   "extended_pan_id": "0123456789abcdef",
  ///   "mesh_local_prefix": "fd00000000000000",
  ///   "pskc": "fedcba9876543210fedcba9876543210"
  /// }
  /// ```
  factory ThreadCredentials.fromDeviceJson(
    Map<String, dynamic> json,
    String unitId,
  ) {
    return ThreadCredentials(
      unitId: unitId,
      networkName: json['network_name'] as String,
      panId: json['pan_id'] as int,
      channel: json['channel'] as int,
      networkKey: json['network_key'] as String,
      extendedPanId: json['extended_pan_id'] as String,
      meshLocalPrefix: json['mesh_local_prefix'] as String,
      pskc: json['pskc'] as String,
    );
  }

  /// Create from database JSON
  factory ThreadCredentials.fromJson(Map<String, dynamic> json) {
    return ThreadCredentials(
      id: json['id'] as String,
      unitId: json['unit_id'] as String,
      networkName: json['network_name'] as String,
      panId: json['pan_id'] as int,
      channel: json['channel'] as int,
      networkKey: json['network_key'] as String,
      extendedPanId: json['extended_pan_id'] as String,
      meshLocalPrefix: json['mesh_local_prefix'] as String,
      pskc: json['pskc'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Convert to JSON for database insertion
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'unit_id': unitId,
      'network_name': networkName,
      'pan_id': panId,
      'channel': channel,
      'network_key': networkKey,
      'extended_pan_id': extendedPanId,
      'mesh_local_prefix': meshLocalPrefix,
      'pskc': pskc,
    };
  }

  /// Convert to JSON for database insertion (without id)
  Map<String, dynamic> toInsertJson() {
    return {
      'unit_id': unitId,
      'network_name': networkName,
      'pan_id': panId,
      'channel': channel,
      'network_key': networkKey,
      'extended_pan_id': extendedPanId,
      'mesh_local_prefix': meshLocalPrefix,
      'pskc': pskc,
    };
  }

  /// Validate the credentials
  ///
  /// Returns null if valid, or an error message if invalid
  String? validate() {
    if (networkName.isEmpty || networkName.length > 16) {
      return 'Network name must be 1-16 characters';
    }
    if (panId < 0 || panId > 65534) {
      return 'PAN ID must be 0-65534';
    }
    if (channel < 11 || channel > 26) {
      return 'Channel must be 11-26';
    }
    if (!_isValidHex(networkKey, 32)) {
      return 'Network key must be 32 hex characters';
    }
    if (!_isValidHex(extendedPanId, 16)) {
      return 'Extended PAN ID must be 16 hex characters';
    }
    if (!_isValidHex(meshLocalPrefix, 16)) {
      return 'Mesh local prefix must be 16 hex characters';
    }
    if (!_isValidHex(pskc, 32)) {
      return 'PSKC must be 32 hex characters';
    }
    return null;
  }

  bool _isValidHex(String value, int expectedLength) {
    if (value.length != expectedLength) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  /// Check if these credentials are valid
  bool get isValid => validate() == null;

  @override
  List<Object?> get props => [
        id,
        unitId,
        networkName,
        panId,
        channel,
        networkKey,
        extendedPanId,
        meshLocalPrefix,
        pskc,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() =>
      'ThreadCredentials(unitId: $unitId, networkName: $networkName, channel: $channel)';
}

/// Thread credentials paired with the Hub's serial number for display
///
/// Used when listing available Thread networks for testing non-BR devices.
class ThreadCredentialsWithUnit {
  final ThreadCredentials credentials;
  final String hubSerialNumber;

  const ThreadCredentialsWithUnit({
    required this.credentials,
    required this.hubSerialNumber,
  });

  /// Display label for UI (e.g., "SaturdayVinyl (SV-HUB-00001)")
  String get displayLabel =>
      '${credentials.networkName} ($hubSerialNumber)';
}
