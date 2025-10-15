import 'package:equatable/equatable.dart';

/// GCodeFile model representing a gCode file from the GitHub repository
class GCodeFile extends Equatable {
  final String id; // UUID
  final String githubPath; // Full path in GitHub repo (e.g., cnc/drill-holes.gcode)
  final String fileName; // Display name
  final String? description; // H1 heading from README
  final String machineType; // 'cnc' or 'laser'
  final DateTime createdAt;
  final DateTime updatedAt;

  const GCodeFile({
    required this.id,
    required this.githubPath,
    required this.fileName,
    this.description,
    required this.machineType,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Validate that the gCode file is valid
  bool isValid() {
    if (githubPath.isEmpty) return false;
    if (fileName.isEmpty) return false;
    if (machineType != 'cnc' && machineType != 'laser') return false;
    return true;
  }

  /// Get the folder path (excluding filename)
  String get folderPath {
    final lastSlash = githubPath.lastIndexOf('/');
    if (lastSlash == -1) return '';
    return githubPath.substring(0, lastSlash);
  }

  /// Get just the filename (excluding path)
  String get fileNameOnly {
    final lastSlash = githubPath.lastIndexOf('/');
    if (lastSlash == -1) return githubPath;
    return githubPath.substring(lastSlash + 1);
  }

  /// Create GCodeFile from JSON
  factory GCodeFile.fromJson(Map<String, dynamic> json) {
    return GCodeFile(
      id: json['id'] as String,
      githubPath: json['github_path'] as String,
      fileName: json['file_name'] as String,
      description: json['description'] as String?,
      machineType: json['machine_type'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert GCodeFile to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'github_path': githubPath,
      'file_name': fileName,
      'description': description,
      'machine_type': machineType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of GCodeFile with updated fields
  GCodeFile copyWith({
    String? id,
    String? githubPath,
    String? fileName,
    String? description,
    String? machineType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GCodeFile(
      id: id ?? this.id,
      githubPath: githubPath ?? this.githubPath,
      fileName: fileName ?? this.fileName,
      description: description ?? this.description,
      machineType: machineType ?? this.machineType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        githubPath,
        fileName,
        description,
        machineType,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'GCodeFile(id: $id, fileName: $fileName, machineType: $machineType)';
  }
}
