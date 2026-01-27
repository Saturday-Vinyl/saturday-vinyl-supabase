import 'package:equatable/equatable.dart';

/// Represents a firmware binary file for a specific SoC
///
/// A firmware version can have multiple files for multi-SoC boards.
/// The master file is pushed via OTA, secondary files are pulled by device.
class FirmwareFile extends Equatable {
  final String id;
  final String firmwareId;

  /// SoC type: esp32, esp32s2, esp32s3, esp32c3, esp32c6, esp32h2
  final String socType;

  /// Master file is pushed via OTA, secondary files are pulled by device
  final bool isMaster;

  /// Storage URL
  final String fileUrl;

  /// SHA-256 hash for integrity verification
  final String? fileSha256;

  /// File size in bytes
  final int? fileSize;

  final DateTime createdAt;

  const FirmwareFile({
    required this.id,
    required this.firmwareId,
    required this.socType,
    this.isMaster = false,
    required this.fileUrl,
    this.fileSha256,
    this.fileSize,
    required this.createdAt,
  });

  /// Get the filename from URL
  String get filename {
    final uri = Uri.parse(fileUrl);
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'unknown.bin';
  }

  /// Get human-readable file size
  String get formattedSize {
    if (fileSize == null) return 'Unknown';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  factory FirmwareFile.fromJson(Map<String, dynamic> json) {
    return FirmwareFile(
      id: json['id'] as String,
      firmwareId: json['firmware_id'] as String,
      socType: json['soc_type'] as String,
      isMaster: json['is_master'] as bool? ?? false,
      fileUrl: json['file_url'] as String,
      fileSha256: json['file_sha256'] as String?,
      fileSize: json['file_size'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'firmware_id': firmwareId,
      'soc_type': socType,
      'is_master': isMaster,
      'file_url': fileUrl,
      'file_sha256': fileSha256,
      'file_size': fileSize,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'firmware_id': firmwareId,
      'soc_type': socType,
      'is_master': isMaster,
      'file_url': fileUrl,
      'file_sha256': fileSha256,
      'file_size': fileSize,
    };
  }

  @override
  List<Object?> get props => [
        id,
        firmwareId,
        socType,
        isMaster,
        fileUrl,
        fileSha256,
        fileSize,
        createdAt,
      ];

  @override
  String toString() =>
      'FirmwareFile(id: $id, socType: $socType, isMaster: $isMaster)';
}

/// Firmware version for a device type with multi-SoC support
///
/// Replaces the old FirmwareVersion model with:
/// - Multi-SoC file support via FirmwareFile
/// - is_critical flag for urgent updates
/// - released_at timestamp (replaces is_production_ready)
class Firmware extends Equatable {
  final String id;
  final String deviceTypeId;

  /// Semantic versioning: "1.2.3"
  final String version;

  final String? releaseNotes;

  /// Legacy single-file fields (for backwards compatibility)
  final String? binaryUrl;
  final String? binaryFilename;
  final int? binarySize;

  /// Critical updates should be installed immediately
  final bool isCritical;

  /// NULL = development, timestamp = released to production
  final DateTime? releasedAt;

  /// Legacy field, derived from releasedAt
  final bool isProductionReady;

  final DateTime createdAt;
  final String? createdBy;

  /// Multi-SoC firmware files
  final List<FirmwareFile> files;

  const Firmware({
    required this.id,
    required this.deviceTypeId,
    required this.version,
    this.releaseNotes,
    this.binaryUrl,
    this.binaryFilename,
    this.binarySize,
    this.isCritical = false,
    this.releasedAt,
    this.isProductionReady = false,
    required this.createdAt,
    this.createdBy,
    this.files = const [],
  });

  /// Check if firmware is released (has a release date)
  bool get isReleased => releasedAt != null;

  /// Get the master firmware file (for OTA push)
  FirmwareFile? get masterFile {
    try {
      return files.firstWhere((f) => f.isMaster);
    } catch (_) {
      return null;
    }
  }

  /// Get secondary firmware files (pulled by device after master update)
  List<FirmwareFile> get secondaryFiles {
    return files.where((f) => !f.isMaster).toList();
  }

  /// Get file for specific SoC type
  FirmwareFile? getFileForSoc(String socType) {
    try {
      return files.firstWhere((f) => f.socType == socType);
    } catch (_) {
      return null;
    }
  }

  /// Check if this is a multi-SoC firmware
  bool get isMultiSoc => files.length > 1;

  factory Firmware.fromJson(Map<String, dynamic> json) {
    final filesJson = json['firmware_files'];
    List<FirmwareFile> files = [];

    if (filesJson != null && filesJson is List) {
      files = filesJson
          .map((f) => FirmwareFile.fromJson(f as Map<String, dynamic>))
          .toList();
    }

    return Firmware(
      id: json['id'] as String,
      deviceTypeId: json['device_type_id'] as String,
      version: json['version'] as String,
      releaseNotes: json['release_notes'] as String?,
      binaryUrl: json['binary_url'] as String?,
      binaryFilename: json['binary_filename'] as String?,
      binarySize: json['binary_size'] as int?,
      isCritical: json['is_critical'] as bool? ?? false,
      releasedAt: json['released_at'] != null
          ? DateTime.parse(json['released_at'] as String)
          : null,
      isProductionReady: json['is_production_ready'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String?,
      files: files,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_type_id': deviceTypeId,
      'version': version,
      'release_notes': releaseNotes,
      'binary_url': binaryUrl,
      'binary_filename': binaryFilename,
      'binary_size': binarySize,
      'is_critical': isCritical,
      'released_at': releasedAt?.toIso8601String(),
      'is_production_ready': isProductionReady,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
      'firmware_files': files.map((f) => f.toJson()).toList(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'device_type_id': deviceTypeId,
      'version': version,
      'release_notes': releaseNotes,
      'binary_url': binaryUrl,
      'binary_filename': binaryFilename,
      'binary_size': binarySize,
      'is_critical': isCritical,
      'is_production_ready': isProductionReady,
      'created_by': createdBy,
    };
  }

  Firmware copyWith({
    String? id,
    String? deviceTypeId,
    String? version,
    String? releaseNotes,
    String? binaryUrl,
    String? binaryFilename,
    int? binarySize,
    bool? isCritical,
    DateTime? releasedAt,
    bool? isProductionReady,
    DateTime? createdAt,
    String? createdBy,
    List<FirmwareFile>? files,
  }) {
    return Firmware(
      id: id ?? this.id,
      deviceTypeId: deviceTypeId ?? this.deviceTypeId,
      version: version ?? this.version,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      binaryUrl: binaryUrl ?? this.binaryUrl,
      binaryFilename: binaryFilename ?? this.binaryFilename,
      binarySize: binarySize ?? this.binarySize,
      isCritical: isCritical ?? this.isCritical,
      releasedAt: releasedAt ?? this.releasedAt,
      isProductionReady: isProductionReady ?? this.isProductionReady,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      files: files ?? this.files,
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
        isCritical,
        releasedAt,
        isProductionReady,
        createdAt,
        createdBy,
        files,
      ];

  @override
  String toString() =>
      'Firmware(id: $id, version: $version, isReleased: $isReleased, isCritical: $isCritical)';
}
