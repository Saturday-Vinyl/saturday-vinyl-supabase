import 'package:equatable/equatable.dart';

/// Permission model representing a user permission in the system
class Permission extends Equatable {
  final String id; // UUID
  final String name;
  final String? description;
  final DateTime createdAt;

  const Permission({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
  });

  // Predefined permission constants
  static const String manageProducts = 'manage_products';
  static const String manageFirmware = 'manage_firmware';
  static const String manageProduction = 'manage_production';

  /// Create Permission from JSON
  factory Permission.fromJson(Map<String, dynamic> json) {
    return Permission(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert Permission to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Create a copy of Permission with updated fields
  Permission copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
  }) {
    return Permission(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, name, description, createdAt];

  @override
  String toString() {
    return 'Permission(id: $id, name: $name)';
  }
}
