import 'package:equatable/equatable.dart';
import 'package:saturday_consumer_app/models/library_member.dart';

/// A library member with associated user profile information.
///
/// This model is used when displaying member lists, as it includes
/// the user's name, email, and avatar for UI display purposes.
class LibraryMemberWithUser extends Equatable {
  final LibraryMember member;
  final String? fullName;
  final String email;
  final String? avatarUrl;

  const LibraryMemberWithUser({
    required this.member,
    this.fullName,
    required this.email,
    this.avatarUrl,
  });

  /// Creates from a joined query response that includes user data.
  ///
  /// Expected JSON structure:
  /// ```json
  /// {
  ///   "id": "...",
  ///   "library_id": "...",
  ///   "user_id": "...",
  ///   "role": "owner",
  ///   "joined_at": "...",
  ///   "invited_by": "...",
  ///   "user": {
  ///     "id": "...",
  ///     "email": "...",
  ///     "full_name": "...",
  ///     "avatar_url": "..."
  ///   }
  /// }
  /// ```
  factory LibraryMemberWithUser.fromJson(Map<String, dynamic> json) {
    final userData = json['user'] as Map<String, dynamic>?;

    return LibraryMemberWithUser(
      member: LibraryMember.fromJson(json),
      fullName: userData?['full_name'] as String?,
      email: userData?['email'] as String? ?? '',
      avatarUrl: userData?['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...member.toJson(),
      'user': {
        'id': member.userId,
        'email': email,
        'full_name': fullName,
        'avatar_url': avatarUrl,
      },
    };
  }

  /// Display name for the member (full name if available, otherwise email).
  String get displayName => fullName?.isNotEmpty == true ? fullName! : email;

  /// Initials for avatar placeholder.
  String get initials {
    if (fullName?.isNotEmpty == true) {
      final parts = fullName!.split(' ');
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      }
      return fullName![0].toUpperCase();
    }
    if (email.isNotEmpty) {
      return email[0].toUpperCase();
    }
    return '?';
  }

  /// Whether this member is the library owner.
  bool get isOwner => member.role == LibraryRole.owner;

  /// Whether this member can edit the library.
  bool get canEdit => member.canEditAlbums;

  /// Role display string.
  String get roleDisplayName {
    switch (member.role) {
      case LibraryRole.owner:
        return 'Owner';
      case LibraryRole.editor:
        return 'Can edit';
      case LibraryRole.viewer:
        return 'Can view';
    }
  }

  @override
  List<Object?> get props => [member, fullName, email, avatarUrl];
}
