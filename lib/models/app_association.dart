import 'package:equatable/equatable.dart';

/// Model representing an association between a file type and an application
///
/// Used to store user preferences for which application should open which file type.
/// For example: .gcode files should open in gSender
class AppAssociation extends Equatable {
  /// File extension (e.g., ".gcode", ".nc", ".svg")
  final String fileType;

  /// Full path to the application executable
  final String appPath;

  /// Human-readable name of the application
  final String appName;

  const AppAssociation({
    required this.fileType,
    required this.appPath,
    required this.appName,
  });

  /// Create an AppAssociation from JSON
  factory AppAssociation.fromJson(Map<String, dynamic> json) {
    return AppAssociation(
      fileType: json['fileType'] as String,
      appPath: json['appPath'] as String,
      appName: json['appName'] as String,
    );
  }

  /// Convert this AppAssociation to JSON
  Map<String, dynamic> toJson() {
    return {
      'fileType': fileType,
      'appPath': appPath,
      'appName': appName,
    };
  }

  /// Create a copy with modified fields
  AppAssociation copyWith({
    String? fileType,
    String? appPath,
    String? appName,
  }) {
    return AppAssociation(
      fileType: fileType ?? this.fileType,
      appPath: appPath ?? this.appPath,
      appName: appName ?? this.appName,
    );
  }

  @override
  List<Object?> get props => [fileType, appPath, appName];

  @override
  String toString() =>
      'AppAssociation(fileType: $fileType, appPath: $appPath, appName: $appName)';
}
