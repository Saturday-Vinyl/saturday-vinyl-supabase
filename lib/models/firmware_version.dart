import 'package:equatable/equatable.dart';

/// Firmware version for a device type
class FirmwareVersion extends Equatable {
  final String id; // UUID
  final String deviceTypeId; // Foreign key
  final String version; // Semantic versioning: "1.2.3"
  final String? releaseNotes;
  final String binaryUrl; // Supabase storage URL
  final String binaryFilename;
  final int? binarySize; // Size in bytes
  final bool isProductionReady;
  final DateTime createdAt;
  final String? createdBy; // User ID who uploaded

  const FirmwareVersion({
    required this.id,
    required this.deviceTypeId,
    required this.version,
    this.releaseNotes,
    required this.binaryUrl,
    required this.binaryFilename,
    this.binarySize,
    required this.isProductionReady,
    required this.createdAt,
    this.createdBy,
  });

  /// Create FirmwareVersion from JSON
  factory FirmwareVersion.fromJson(Map<String, dynamic> json) {
    return FirmwareVersion(
      id: json['id'] as String,
      deviceTypeId: json['device_type_id'] as String,
      version: json['version'] as String,
      releaseNotes: json['release_notes'] as String?,
      binaryUrl: json['binary_url'] as String,
      binaryFilename: json['binary_filename'] as String,
      binarySize: json['binary_size'] as int?,
      isProductionReady: json['is_production_ready'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String?,
    );
  }

  /// Convert to JSON for insertion
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_type_id': deviceTypeId,
      'version': version,
      'release_notes': releaseNotes,
      'binary_url': binaryUrl,
      'binary_filename': binaryFilename,
      'binary_size': binarySize,
      'is_production_ready': isProductionReady,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
    };
  }

  /// Convert to JSON for insertion (without id, timestamps)
  Map<String, dynamic> toInsertJson() {
    return {
      'device_type_id': deviceTypeId,
      'version': version,
      'release_notes': releaseNotes,
      'binary_url': binaryUrl,
      'binary_filename': binaryFilename,
      'binary_size': binarySize,
      'is_production_ready': isProductionReady,
      'created_by': createdBy,
    };
  }

  /// Create a copy with modified fields
  FirmwareVersion copyWith({
    String? id,
    String? deviceTypeId,
    String? version,
    String? releaseNotes,
    String? binaryUrl,
    String? binaryFilename,
    int? binarySize,
    bool? isProductionReady,
    DateTime? createdAt,
    String? createdBy,
  }) {
    return FirmwareVersion(
      id: id ?? this.id,
      deviceTypeId: deviceTypeId ?? this.deviceTypeId,
      version: version ?? this.version,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      binaryUrl: binaryUrl ?? this.binaryUrl,
      binaryFilename: binaryFilename ?? this.binaryFilename,
      binarySize: binarySize ?? this.binarySize,
      isProductionReady: isProductionReady ?? this.isProductionReady,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        deviceTypeId,
        version,
        releaseNotes,
        binaryUrl,
        binaryFilename,
        binarySize,
        isProductionReady,
        createdAt,
        createdBy,
      ];

  @override
  String toString() =>
      'FirmwareVersion(id: $id, version: $version, deviceTypeId: $deviceTypeId, isProductionReady: $isProductionReady)';
}
