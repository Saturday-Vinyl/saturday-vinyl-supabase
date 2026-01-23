import 'package:saturday_consumer_app/models/library_invitation.dart';
import 'package:saturday_consumer_app/models/library_member.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for library invitation operations.
///
/// Handles creating, fetching, and managing library invitations.
/// Invitation emails are sent via an Edge Function.
class InvitationRepository extends BaseRepository {
  static const _tableName = 'library_invitations';
  static const _edgeFunctionName = 'send-library-invitation';

  /// Sends a library invitation via the Edge Function.
  ///
  /// The Edge Function handles:
  /// - Validating the user is the library owner
  /// - Creating the invitation record
  /// - Sending the invitation email
  ///
  /// Returns the created invitation, or throws on error.
  Future<LibraryInvitation> sendInvitation({
    required String libraryId,
    required String email,
    required LibraryRole role,
  }) async {
    final response = await client.functions.invoke(
      _edgeFunctionName,
      body: {
        'library_id': libraryId,
        'email': email.toLowerCase().trim(),
        'role': role.name,
      },
    );

    if (response.status != 200) {
      final error = response.data?['error'] as String? ?? 'Failed to send invitation';
      throw Exception(error);
    }

    // The Edge Function returns a subset of invitation fields
    // We construct a LibraryInvitation from it
    final data = response.data as Map<String, dynamic>;
    return LibraryInvitation(
      id: data['id'] as String,
      libraryId: libraryId,
      libraryName: data['library_name'] as String?,
      invitedEmail: data['invited_email'] as String,
      role: LibraryRole.fromString(data['role'] as String),
      status: InvitationStatus.pending,
      token: data['token'] as String,
      invitedBy: '', // Not returned by Edge Function
      createdAt: DateTime.now(),
      expiresAt: DateTime.parse(data['expires_at'] as String),
    );
  }

  /// Gets an invitation by its token using the database function.
  ///
  /// This is used when handling deep links to show invitation details
  /// before the user accepts or rejects.
  Future<LibraryInvitation?> getInvitationByToken(String token) async {
    final response = await client
        .rpc('get_invitation_by_token', params: {'p_token': token});

    if (response == null || (response as List).isEmpty) {
      return null;
    }

    final data = response[0] as Map<String, dynamic>;

    // Check if expired based on the is_expired flag from the function
    final isExpired = data['is_expired'] as bool? ?? false;
    final status = isExpired
        ? InvitationStatus.expired
        : InvitationStatus.fromString(data['status'] as String);

    return LibraryInvitation(
      id: data['invitation_id'] as String,
      libraryId: data['library_id'] as String,
      libraryName: data['library_name'] as String?,
      libraryDescription: data['library_description'] as String?,
      invitedEmail: data['invited_email'] as String,
      role: LibraryRole.fromString(data['role'] as String),
      status: status,
      token: token,
      invitedBy: '', // Not returned by this function
      inviterName: data['inviter_name'] as String?,
      inviterEmail: data['inviter_email'] as String?,
      createdAt: DateTime.parse(data['created_at'] as String),
      expiresAt: DateTime.parse(data['expires_at'] as String),
    );
  }

  /// Accepts an invitation by its token.
  ///
  /// The accepting user is specified by [userId]. This allows the invitation
  /// to be accepted by any user with the token, not just the originally
  /// invited email address.
  ///
  /// On success, a library_member record is created automatically by the
  /// database function.
  Future<LibraryInvitation> acceptInvitation(String token, String userId) async {
    final response = await client.rpc('accept_invitation_by_token', params: {
      'p_token': token,
      'p_accepting_user_id': userId,
    });

    if (response == null) {
      throw Exception('Failed to accept invitation');
    }

    return LibraryInvitation.fromJson(response as Map<String, dynamic>);
  }

  /// Rejects an invitation by its token.
  Future<LibraryInvitation> rejectInvitation(String token) async {
    final response = await client.rpc('reject_invitation_by_token', params: {
      'p_token': token,
    });

    if (response == null) {
      throw Exception('Failed to reject invitation');
    }

    return LibraryInvitation.fromJson(response as Map<String, dynamic>);
  }

  /// Gets pending invitations for a library.
  ///
  /// This is used by the library owner to see who has been invited
  /// but hasn't responded yet.
  Future<List<LibraryInvitation>> getLibraryInvitations(String libraryId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('library_id', libraryId)
        .eq('status', 'pending')
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('created_at', ascending: false);

    return (response as List)
        .map((row) => LibraryInvitation.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Gets pending invitations for a user by their email.
  ///
  /// This is used to show the user any pending invitations they have received.
  Future<List<LibraryInvitation>> getPendingInvitationsForUser(String email) async {
    final response = await client
        .from(_tableName)
        .select('''
          *,
          libraries!inner(name, description),
          inviter:users!invited_by(full_name, email)
        ''')
        .eq('invited_email', email.toLowerCase())
        .eq('status', 'pending')
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('created_at', ascending: false);

    return (response as List).map((row) {
      final data = row as Map<String, dynamic>;
      final library = data['libraries'] as Map<String, dynamic>?;
      final inviter = data['inviter'] as Map<String, dynamic>?;

      return LibraryInvitation(
        id: data['id'] as String,
        libraryId: data['library_id'] as String,
        libraryName: library?['name'] as String?,
        libraryDescription: library?['description'] as String?,
        invitedEmail: data['invited_email'] as String,
        invitedUserId: data['invited_user_id'] as String?,
        role: LibraryRole.fromString(data['role'] as String),
        status: InvitationStatus.fromString(data['status'] as String),
        token: data['token'] as String,
        invitedBy: data['invited_by'] as String,
        inviterName: inviter?['full_name'] as String?,
        inviterEmail: inviter?['email'] as String?,
        createdAt: DateTime.parse(data['created_at'] as String),
        expiresAt: DateTime.parse(data['expires_at'] as String),
        acceptedAt: data['accepted_at'] != null
            ? DateTime.parse(data['accepted_at'] as String)
            : null,
        finalizedUserId: data['finalized_user_id'] as String?,
      );
    }).toList();
  }

  /// Revokes an invitation.
  ///
  /// Only the library owner can revoke invitations.
  Future<void> revokeInvitation(String invitationId, String userId) async {
    final response = await client.rpc('revoke_invitation', params: {
      'p_invitation_id': invitationId,
      'p_user_id': userId,
    });

    if (response == null) {
      throw Exception('Failed to revoke invitation');
    }
  }
}
