import 'package:equatable/equatable.dart';

/// Supplier model representing a parts/materials vendor
class Supplier extends Equatable {
  final String id;
  final String name;
  final String? website;
  final String? notes;
  final bool isActive;
  final DateTime createdAt;

  const Supplier({
    required this.id,
    required this.name,
    this.website,
    this.notes,
    required this.isActive,
    required this.createdAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as String,
      name: json['name'] as String,
      website: json['website'] as String?,
      notes: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'website': website,
      'notes': notes,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Supplier copyWith({
    String? id,
    String? name,
    String? website,
    String? notes,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return Supplier(
      id: id ?? this.id,
      name: name ?? this.name,
      website: website ?? this.website,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [id, name, website, notes, isActive, createdAt];

  @override
  String toString() => 'Supplier(id: $id, name: $name)';
}
