import 'package:equatable/equatable.dart';

/// Role a user has in a library.
enum LibraryRole {
  owner,
  editor,
  viewer;

  static LibraryRole fromString(String value) {
    return LibraryRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => LibraryRole.viewer,
    );
  }
}

/// Represents a user's membership in a library.
///
/// Library members have different roles that determine their permissions:
/// - Owner: Full control including delete and member management
/// - Editor: Can add, edit, and remove albums
/// - Viewer: Read-only access
class LibraryMember extends Equatable {
  final String id;
  final String libraryId;
  final String userId;
  final LibraryRole role;
  final DateTime joinedAt;
  final String? invitedBy;

  const LibraryMember({
    required this.id,
    required this.libraryId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.invitedBy,
  });

  factory LibraryMember.fromJson(Map<String, dynamic> json) {
    return LibraryMember(
      id: json['id'] as String,
      libraryId: json['library_id'] as String,
      userId: json['user_id'] as String,
      role: LibraryRole.fromString(json['role'] as String),
      joinedAt: DateTime.parse(json['joined_at'] as String),
      invitedBy: json['invited_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'library_id': libraryId,
      'user_id': userId,
      'role': role.name,
      'joined_at': joinedAt.toIso8601String(),
      'invited_by': invitedBy,
    };
  }

  LibraryMember copyWith({
    String? id,
    String? libraryId,
    String? userId,
    LibraryRole? role,
    DateTime? joinedAt,
    String? invitedBy,
  }) {
    return LibraryMember(
      id: id ?? this.id,
      libraryId: libraryId ?? this.libraryId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      invitedBy: invitedBy ?? this.invitedBy,
    );
  }

  /// Whether this member can add albums to the library.
  bool get canAddAlbums => role == LibraryRole.owner || role == LibraryRole.editor;

  /// Whether this member can edit albums in the library.
  bool get canEditAlbums => role == LibraryRole.owner || role == LibraryRole.editor;

  /// Whether this member can remove albums from the library.
  bool get canRemoveAlbums => role == LibraryRole.owner || role == LibraryRole.editor;

  /// Whether this member can manage other members.
  bool get canManageMembers => role == LibraryRole.owner;

  /// Whether this member can delete the library.
  bool get canDeleteLibrary => role == LibraryRole.owner;

  @override
  List<Object?> get props => [
        id,
        libraryId,
        userId,
        role,
        joinedAt,
        invitedBy,
      ];
}
