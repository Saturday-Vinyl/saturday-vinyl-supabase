import 'package:equatable/equatable.dart';
import 'package:saturday_consumer_app/models/library_member.dart';

/// A user's membership in a cratelist. Roles use the same `library_role`
/// enum as libraries, so [LibraryRole] is reused.
class CratelistMember extends Equatable {
  final String id;
  final String cratelistId;
  final String userId;
  final LibraryRole role;
  final DateTime addedAt;
  final String? addedBy;

  const CratelistMember({
    required this.id,
    required this.cratelistId,
    required this.userId,
    required this.role,
    required this.addedAt,
    this.addedBy,
  });

  factory CratelistMember.fromJson(Map<String, dynamic> json) {
    return CratelistMember(
      id: json['id'] as String,
      cratelistId: json['cratelist_id'] as String,
      userId: json['user_id'] as String,
      role: LibraryRole.fromString(json['role'] as String),
      addedAt: DateTime.parse(json['added_at'] as String),
      addedBy: json['added_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cratelist_id': cratelistId,
      'user_id': userId,
      'role': role.name,
      'added_at': addedAt.toIso8601String(),
      'added_by': addedBy,
    };
  }

  CratelistMember copyWith({
    String? id,
    String? cratelistId,
    String? userId,
    LibraryRole? role,
    DateTime? addedAt,
    String? addedBy,
  }) {
    return CratelistMember(
      id: id ?? this.id,
      cratelistId: cratelistId ?? this.cratelistId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      addedAt: addedAt ?? this.addedAt,
      addedBy: addedBy ?? this.addedBy,
    );
  }

  bool get canEdit =>
      role == LibraryRole.owner || role == LibraryRole.editor;
  bool get canManageMembers => role == LibraryRole.owner;
  bool get canDelete => role == LibraryRole.owner;

  @override
  List<Object?> get props => [
        id,
        cratelistId,
        userId,
        role,
        addedAt,
        addedBy,
      ];
}
