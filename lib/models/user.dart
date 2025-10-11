import 'package:equatable/equatable.dart';

/// User model representing an employee user in the system
class User extends Equatable {
  final String id; // UUID
  final String googleId;
  final String email;
  final String? fullName;
  final bool isAdmin;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLogin;

  const User({
    required this.id,
    required this.googleId,
    required this.email,
    this.fullName,
    required this.isAdmin,
    required this.isActive,
    required this.createdAt,
    this.lastLogin,
  });

  /// Create User from JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      googleId: json['google_id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      isAdmin: json['is_admin'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastLogin: json['last_login'] != null
          ? DateTime.parse(json['last_login'] as String)
          : null,
    );
  }

  /// Convert User to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'google_id': googleId,
      'email': email,
      'full_name': fullName,
      'is_admin': isAdmin,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'last_login': lastLogin?.toIso8601String(),
    };
  }

  /// Create a copy of User with updated fields
  User copyWith({
    String? id,
    String? googleId,
    String? email,
    String? fullName,
    bool? isAdmin,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastLogin,
  }) {
    return User(
      id: id ?? this.id,
      googleId: googleId ?? this.googleId,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      isAdmin: isAdmin ?? this.isAdmin,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastLogin: lastLogin ?? this.lastLogin,
    );
  }

  @override
  List<Object?> get props => [
        id,
        googleId,
        email,
        fullName,
        isAdmin,
        isActive,
        createdAt,
        lastLogin,
      ];

  @override
  String toString() {
    return 'User(id: $id, email: $email, isAdmin: $isAdmin, isActive: $isActive)';
  }
}
