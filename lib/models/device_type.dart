import 'package:equatable/equatable.dart';

/// DeviceType model representing an embedded hardware device that can be used in products
class DeviceType extends Equatable {
  final String id; // UUID
  final String name;
  final String? description;
  final List<String> capabilities; // e.g., ["BLE", "WiFi", "Thread", "RFID"]
  final String? specUrl; // URL to datasheet or specifications
  final String? currentFirmwareVersion;
  final String? chipType; // ESP32 chip type: esp32, esp32s2, esp32s3, esp32c3, esp32c6, esp32h2
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DeviceType({
    required this.id,
    required this.name,
    this.description,
    required this.capabilities,
    this.specUrl,
    this.currentFirmwareVersion,
    this.chipType,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Check if device has a specific capability
  bool hasCapability(String capability) {
    return capabilities.contains(capability);
  }

  /// Create DeviceType from JSON
  factory DeviceType.fromJson(Map<String, dynamic> json) {
    return DeviceType(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      capabilities: json['capabilities'] != null
          ? List<String>.from(json['capabilities'] as List)
          : [],
      specUrl: json['spec_url'] as String?,
      currentFirmwareVersion: json['current_firmware_version'] as String?,
      chipType: json['chip_type'] as String?,
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
      'description': description,
      'capabilities': capabilities,
      'spec_url': specUrl,
      'current_firmware_version': currentFirmwareVersion,
      'chip_type': chipType,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of DeviceType with updated fields
  DeviceType copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? capabilities,
    String? specUrl,
    String? currentFirmwareVersion,
    String? chipType,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DeviceType(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      capabilities: capabilities ?? this.capabilities,
      specUrl: specUrl ?? this.specUrl,
      currentFirmwareVersion:
          currentFirmwareVersion ?? this.currentFirmwareVersion,
      chipType: chipType ?? this.chipType,
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
        description,
        capabilities,
        specUrl,
        currentFirmwareVersion,
        chipType,
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
