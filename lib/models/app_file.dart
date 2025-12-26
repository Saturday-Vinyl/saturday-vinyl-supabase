import 'package:equatable/equatable.dart';

/// AppFile model representing a file in the unified file library
/// Named AppFile to avoid conflict with dart:io File
class AppFile extends Equatable {
  final String id; // UUID
  final String storagePath; // Path in Supabase Storage
  final String fileName; // User-visible name (unique)
  final String? description; // User-editable description
  final String mimeType; // MIME type
  final int fileSizeBytes; // File size in bytes
  final String uploadedByName; // Name of uploader
  final DateTime createdAt;
  final DateTime updatedAt;

  const AppFile({
    required this.id,
    required this.storagePath,
    required this.fileName,
    this.description,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.uploadedByName,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Get file size in human-readable format (KB, MB)
  String get fileSizeFormatted {
    if (fileSizeBytes < 1024) {
      return '$fileSizeBytes B';
    } else if (fileSizeBytes < 1024 * 1024) {
      final kb = (fileSizeBytes / 1024).toStringAsFixed(1);
      return '$kb KB';
    } else {
      final mb = (fileSizeBytes / (1024 * 1024)).toStringAsFixed(2);
      return '$mb MB';
    }
  }

  /// Get file extension from filename
  String get fileExtension {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) {
      return '';
    }
    return fileName.substring(lastDot).toLowerCase();
  }

  /// Check if this file is a gcode file (.gcode, .nc, or .gc extension)
  bool get isGCodeFile {
    final ext = fileExtension;
    return ext == '.gcode' || ext == '.nc' || ext == '.gc';
  }

  /// Validate that the file meets requirements
  bool isValid() {
    if (fileName.isEmpty) return false;
    if (storagePath.isEmpty) return false;
    if (mimeType.isEmpty) return false;
    if (fileSizeBytes <= 0 || fileSizeBytes > 52428800) return false; // 50MB max
    if (uploadedByName.isEmpty) return false;
    return true;
  }

  /// Create AppFile from JSON
  factory AppFile.fromJson(Map<String, dynamic> json) {
    return AppFile(
      id: json['id'] as String,
      storagePath: json['storage_path'] as String,
      fileName: json['file_name'] as String,
      description: json['description'] as String?,
      mimeType: json['mime_type'] as String,
      fileSizeBytes: json['file_size_bytes'] as int,
      uploadedByName: json['uploaded_by_name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert AppFile to JSON
  /// If [forInsert] is true, excludes id, created_at, and updated_at (let database generate them)
  Map<String, dynamic> toJson({bool forInsert = false}) {
    final json = {
      'storage_path': storagePath,
      'file_name': fileName,
      'description': description,
      'mime_type': mimeType,
      'file_size_bytes': fileSizeBytes,
      'uploaded_by_name': uploadedByName,
    };

    // Only include id and timestamps if not for insert, and id is not empty
    if (!forInsert && id.isNotEmpty) {
      json['id'] = id;
      json['created_at'] = createdAt.toIso8601String();
      json['updated_at'] = updatedAt.toIso8601String();
    }

    return json;
  }

  /// Create a copy of AppFile with updated fields
  AppFile copyWith({
    String? id,
    String? storagePath,
    String? fileName,
    String? description,
    String? mimeType,
    int? fileSizeBytes,
    String? uploadedByName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AppFile(
      id: id ?? this.id,
      storagePath: storagePath ?? this.storagePath,
      fileName: fileName ?? this.fileName,
      description: description ?? this.description,
      mimeType: mimeType ?? this.mimeType,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      uploadedByName: uploadedByName ?? this.uploadedByName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        storagePath,
        fileName,
        description,
        mimeType,
        fileSizeBytes,
        uploadedByName,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'AppFile(id: $id, fileName: $fileName, size: $fileSizeFormatted)';
  }
}
