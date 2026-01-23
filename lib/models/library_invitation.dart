import 'package:equatable/equatable.dart';
import 'package:saturday_consumer_app/models/library_member.dart';

/// Status of a library invitation.
enum InvitationStatus {
  pending,
  accepted,
  rejected,
  expired,
  revoked;

  static InvitationStatus fromString(String value) {
    return InvitationStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => InvitationStatus.pending,
    );
  }
}

/// Represents a library invitation.
///
/// Invitations are created when a library owner shares their library
/// with another user by email. The invitation contains a unique token
/// used in deep links for accepting the invitation.
///
/// Key behaviors:
/// - Invitations expire after 7 days
/// - The `finalized_user_id` tracks who actually accepted (may differ from
///   the originally invited user if they sign up with a different email)
/// - Only pending invitations can be accepted or rejected
class LibraryInvitation extends Equatable {
  final String id;
  final String libraryId;
  final String? libraryName;
  final String? libraryDescription;
  final String invitedEmail;
  final String? invitedUserId;
  final LibraryRole role;
  final InvitationStatus status;
  final String token;
  final String invitedBy;
  final String? inviterName;
  final String? inviterEmail;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final String? finalizedUserId;

  const LibraryInvitation({
    required this.id,
    required this.libraryId,
    this.libraryName,
    this.libraryDescription,
    required this.invitedEmail,
    this.invitedUserId,
    required this.role,
    required this.status,
    required this.token,
    required this.invitedBy,
    this.inviterName,
    this.inviterEmail,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedAt,
    this.finalizedUserId,
  });

  /// Creates an invitation from database JSON.
  ///
  /// Handles both direct table queries and the enriched response
  /// from `get_invitation_by_token` function.
  factory LibraryInvitation.fromJson(Map<String, dynamic> json) {
    return LibraryInvitation(
      id: json['id'] as String? ?? json['invitation_id'] as String,
      libraryId: json['library_id'] as String,
      libraryName: json['library_name'] as String?,
      libraryDescription: json['library_description'] as String?,
      invitedEmail: json['invited_email'] as String,
      invitedUserId: json['invited_user_id'] as String?,
      role: LibraryRole.fromString(json['role'] as String),
      status: InvitationStatus.fromString(json['status'] as String),
      token: json['token'] as String? ?? '',
      invitedBy: json['invited_by'] as String? ?? '',
      inviterName: json['inviter_name'] as String?,
      inviterEmail: json['inviter_email'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      acceptedAt: json['accepted_at'] != null
          ? DateTime.parse(json['accepted_at'] as String)
          : null,
      finalizedUserId: json['finalized_user_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'library_id': libraryId,
      'library_name': libraryName,
      'library_description': libraryDescription,
      'invited_email': invitedEmail,
      'invited_user_id': invitedUserId,
      'role': role.name,
      'status': status.name,
      'token': token,
      'invited_by': invitedBy,
      'inviter_name': inviterName,
      'inviter_email': inviterEmail,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'accepted_at': acceptedAt?.toIso8601String(),
      'finalized_user_id': finalizedUserId,
    };
  }

  LibraryInvitation copyWith({
    String? id,
    String? libraryId,
    String? libraryName,
    String? libraryDescription,
    String? invitedEmail,
    String? invitedUserId,
    LibraryRole? role,
    InvitationStatus? status,
    String? token,
    String? invitedBy,
    String? inviterName,
    String? inviterEmail,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? acceptedAt,
    String? finalizedUserId,
  }) {
    return LibraryInvitation(
      id: id ?? this.id,
      libraryId: libraryId ?? this.libraryId,
      libraryName: libraryName ?? this.libraryName,
      libraryDescription: libraryDescription ?? this.libraryDescription,
      invitedEmail: invitedEmail ?? this.invitedEmail,
      invitedUserId: invitedUserId ?? this.invitedUserId,
      role: role ?? this.role,
      status: status ?? this.status,
      token: token ?? this.token,
      invitedBy: invitedBy ?? this.invitedBy,
      inviterName: inviterName ?? this.inviterName,
      inviterEmail: inviterEmail ?? this.inviterEmail,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      finalizedUserId: finalizedUserId ?? this.finalizedUserId,
    );
  }

  /// Whether the invitation is still valid and can be accepted.
  bool get isValid =>
      status == InvitationStatus.pending && DateTime.now().isBefore(expiresAt);

  /// Whether the invitation has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Human-readable role description.
  String get roleDescription =>
      role == LibraryRole.editor ? 'Can view and edit' : 'Can view';

  /// Display name for the inviter.
  String get inviterDisplayName => inviterName ?? inviterEmail ?? 'Someone';

  @override
  List<Object?> get props => [
        id,
        libraryId,
        libraryName,
        invitedEmail,
        invitedUserId,
        role,
        status,
        token,
        invitedBy,
        createdAt,
        expiresAt,
        acceptedAt,
        finalizedUserId,
      ];
}
