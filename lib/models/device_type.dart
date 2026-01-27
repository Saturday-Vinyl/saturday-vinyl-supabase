import 'package:equatable/equatable.dart';

/// DeviceType model representing a PCB template with one or more SoCs
///
/// A device type defines the hardware configuration for a class of devices.
/// Multi-SoC boards (e.g., ESP32-S3 + ESP32-H2) have multiple entries in socTypes.
class DeviceType extends Equatable {
  final String id; // UUID
  final String name;
  final String slug; // URL-safe identifier (e.g., "hub-prototype")
  final String? description;
  final List<String> capabilities; // e.g., ["BLE", "WiFi", "Thread", "RFID"]
  final String? specUrl; // URL to datasheet or specifications
  final String? currentFirmwareVersion;

  /// Legacy single-chip field (for backwards compatibility)
  final String? chipType;

  /// SoC types on this PCB (e.g., ['esp32s3', 'esp32h2'] for Crate)
  final List<String> socTypes;

  /// Which SoC has network connectivity (WiFi/Thread) for OTA
  final String? masterSoc;

  /// Reference to production firmware version
  final String? productionFirmwareId;

  /// Reference to development firmware version
  final String? devFirmwareId;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DeviceType({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    required this.capabilities,
    this.specUrl,
    this.currentFirmwareVersion,
    this.chipType,
    this.socTypes = const [],
    this.masterSoc,
    this.productionFirmwareId,
    this.devFirmwareId,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Check if device has a specific capability
  bool hasCapability(String capability) {
    return capabilities.contains(capability);
  }

  /// Check if this is a multi-SoC device type
  bool get isMultiSoc => socTypes.length > 1;

  /// Get effective SoC types (fallback to chipType for legacy)
  List<String> get effectiveSocTypes {
    if (socTypes.isNotEmpty) return socTypes;
    if (chipType != null) return [chipType!];
    return [];
  }

  /// Get effective master SoC (fallback to first SoC or chipType)
  String? get effectiveMasterSoc {
    if (masterSoc != null) return masterSoc;
    if (socTypes.isNotEmpty) return socTypes.first;
    return chipType;
  }

  /// Create DeviceType from JSON
  factory DeviceType.fromJson(Map<String, dynamic> json) {
    return DeviceType(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      description: json['description'] as String?,
      capabilities: json['capabilities'] != null
          ? List<String>.from(json['capabilities'] as List)
          : [],
      specUrl: json['spec_url'] as String?,
      currentFirmwareVersion: json['current_firmware_version'] as String?,
      chipType: json['chip_type'] as String?,
      socTypes: json['soc_types'] != null
          ? List<String>.from(json['soc_types'] as List)
          : [],
      masterSoc: json['master_soc'] as String?,
      productionFirmwareId: json['production_firmware_id'] as String?,
      devFirmwareId: json['dev_firmware_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert DeviceType to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'slug': slug,
      'description': description,
      'capabilities': capabilities,
      'spec_url': specUrl,
      'current_firmware_version': currentFirmwareVersion,
      'chip_type': chipType,
      'soc_types': socTypes,
      'master_soc': masterSoc,
      'production_firmware_id': productionFirmwareId,
      'dev_firmware_id': devFirmwareId,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Convert to JSON for insertion (without id, timestamps)
  Map<String, dynamic> toInsertJson() {
    return {
      'name': name,
      'slug': slug,
      'description': description,
      'capabilities': capabilities,
      'spec_url': specUrl,
      'chip_type': chipType,
      'soc_types': socTypes,
      'master_soc': masterSoc,
      'production_firmware_id': productionFirmwareId,
      'dev_firmware_id': devFirmwareId,
      'is_active': isActive,
    };
  }

  /// Create a copy of DeviceType with updated fields
  DeviceType copyWith({
    String? id,
    String? name,
    String? slug,
    String? description,
    List<String>? capabilities,
    String? specUrl,
    String? currentFirmwareVersion,
    String? chipType,
    List<String>? socTypes,
    String? masterSoc,
    String? productionFirmwareId,
    String? devFirmwareId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DeviceType(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      capabilities: capabilities ?? this.capabilities,
      specUrl: specUrl ?? this.specUrl,
      currentFirmwareVersion:
          currentFirmwareVersion ?? this.currentFirmwareVersion,
      chipType: chipType ?? this.chipType,
      socTypes: socTypes ?? this.socTypes,
      masterSoc: masterSoc ?? this.masterSoc,
      productionFirmwareId: productionFirmwareId ?? this.productionFirmwareId,
      devFirmwareId: devFirmwareId ?? this.devFirmwareId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Get a human-readable status
  String get status => isActive ? 'Active' : 'Inactive';

  @override
  List<Object?> get props => [
        id,
        name,
        slug,
        description,
        capabilities,
        specUrl,
        currentFirmwareVersion,
        chipType,
        socTypes,
        masterSoc,
        productionFirmwareId,
        devFirmwareId,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'DeviceType(id: $id, name: $name, capabilities: $capabilities)';
  }
}

/// Common device capabilities
class DeviceCapabilities {
  static const String bluetooth = 'bluetooth';
  static const String wifi = 'wifi';
  static const String thread = 'thread';
  static const String nfc = 'nfc';
  static const String camera = 'camera';
  static const String barcode = 'barcode_scanner';
  static const String rfid = 'rfid';
  static const String display = 'display';
  static const String printer = 'printer';
  static const String audio = 'audio';
  static const String vibration = 'vibration';

  /// Get all available capabilities
  static List<String> get all => [
        bluetooth,
        wifi,
        thread,
        nfc,
        camera,
        barcode,
        rfid,
        display,
        printer,
        audio,
        vibration,
      ];

  /// Get display name for capability
  static String getDisplayName(String capability) {
    switch (capability) {
      case bluetooth:
        return 'Bluetooth';
      case wifi:
        return 'Wi-Fi';
      case thread:
        return 'Thread';
      case nfc:
        return 'NFC';
      case camera:
        return 'Camera';
      case barcode:
        return 'Barcode Scanner';
      case rfid:
        return 'RFID';
      case display:
        return 'Display';
      case printer:
        return 'Printer';
      case audio:
        return 'Audio';
      case vibration:
        return 'Vibration';
      default:
        return capability;
    }
  }
}
