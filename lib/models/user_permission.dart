import 'package:equatable/equatable.dart';

/// Represents the user-permission join table
class UserPermission extends Equatable {
  final String id;
  final String userId;
  final String permissionId;
  final DateTime grantedAt;
  final String? grantedBy;

  const UserPermission({
    required this.id,
    required this.userId,
    required this.permissionId,
    required this.grantedAt,
    this.grantedBy,
  });

  /// Create UserPermission from JSON
  factory UserPermission.fromJson(Map<String, dynamic> json) {
    return UserPermission(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      permissionId: json['permission_id'] as String,
      grantedAt: DateTime.parse(json['granted_at'] as String),
      grantedBy: json['granted_by'] as String?,
    );
  }

  /// Convert UserPermission to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'permission_id': permissionId,
      'granted_at': grantedAt.toIso8601String(),
      'granted_by': grantedBy,
    };
  }

  /// Create a copy with optional field updates
  UserPermission copyWith({
    String? id,
    String? userId,
    String? permissionId,
    DateTime? grantedAt,
    String? grantedBy,
  }) {
    return UserPermission(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      permissionId: permissionId ?? this.permissionId,
      grantedAt: grantedAt ?? this.grantedAt,
      grantedBy: grantedBy ?? this.grantedBy,
    );
  }

  @override
  List<Object?> get props => [id, userId, permissionId, grantedAt, grantedBy];

  @override
  String toString() {
    return 'UserPermission(id: $id, userId: $userId, permissionId: $permissionId, '
        'grantedAt: $grantedAt, grantedBy: $grantedBy)';
  }
}
