import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library_invitation.dart';
import 'package:saturday_consumer_app/models/library_member.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

/// FutureProvider.family to fetch an invitation by its token.
///
/// Used when handling deep links to display invitation details
/// before the user accepts or rejects.
final invitationByTokenProvider =
    FutureProvider.family<LibraryInvitation?, String>((ref, token) async {
  final repo = ref.watch(invitationRepositoryProvider);
  return repo.getInvitationByToken(token);
});

/// FutureProvider for pending invitations for the current user.
///
/// Returns invitations that have been sent to the user's email
/// that are still pending (not accepted, rejected, or expired).
final userPendingInvitationsProvider =
    FutureProvider<List<LibraryInvitation>>((ref) async {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return [];

  final repo = ref.watch(invitationRepositoryProvider);
  return repo.getPendingInvitationsForUser(user.email);
});

/// FutureProvider.family for pending invitations for a specific library.
///
/// Used by library owners to see who has been invited but hasn't responded.
final libraryPendingInvitationsProvider =
    FutureProvider.family<List<LibraryInvitation>, String>(
        (ref, libraryId) async {
  final repo = ref.watch(invitationRepositoryProvider);
  return repo.getLibraryInvitations(libraryId);
});

/// Provider for the count of pending invitations for the current user.
final pendingInvitationCountProvider = Provider<int>((ref) {
  final invitations = ref.watch(userPendingInvitationsProvider);
  return invitations.whenOrNull(data: (invites) => invites.length) ?? 0;
});

/// StateProvider to store a pending invite code during auth redirect.
///
/// When a user opens an invite link but isn't logged in, the code is stored
/// here so it can be used after authentication completes.
final pendingInviteCodeProvider = StateProvider<String?>((ref) => null);

/// State class for invitation actions.
class InvitationActionState {
  final bool isLoading;
  final String? error;
  final LibraryInvitation? result;

  const InvitationActionState({
    this.isLoading = false,
    this.error,
    this.result,
  });

  InvitationActionState copyWith({
    bool? isLoading,
    String? error,
    LibraryInvitation? result,
  }) {
    return InvitationActionState(
      isLoading: isLoading ?? this.isLoading,
      error: error,
      result: result ?? this.result,
    );
  }
}

/// StateNotifier for managing invitation actions (send, accept, reject, revoke).
class InvitationNotifier extends StateNotifier<InvitationActionState> {
  InvitationNotifier(this._ref) : super(const InvitationActionState());

  final Ref _ref;

  /// Sends a library invitation.
  ///
  /// Returns the created invitation on success, null on failure.
  Future<LibraryInvitation?> sendInvitation({
    required String libraryId,
    required String email,
    required LibraryRole role,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final repo = _ref.read(invitationRepositoryProvider);
      final invitation = await repo.sendInvitation(
        libraryId: libraryId,
        email: email,
        role: role,
      );

      // Invalidate the library's pending invitations
      _ref.invalidate(libraryPendingInvitationsProvider(libraryId));

      state = state.copyWith(isLoading: false, result: invitation);
      return invitation;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  /// Accepts an invitation by its token.
  ///
  /// Returns true on success, false on failure.
  Future<bool> acceptInvitation(String token) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final userId = _ref.read(currentUserIdProvider);
      if (userId == null) {
        throw Exception('Not authenticated');
      }

      final repo = _ref.read(invitationRepositoryProvider);
      final invitation = await repo.acceptInvitation(token, userId);

      // Invalidate libraries to show the new library
      _ref.invalidate(userLibrariesProvider);
      _ref.invalidate(userPendingInvitationsProvider);

      // Clear any pending invite code
      _ref.read(pendingInviteCodeProvider.notifier).state = null;

      state = state.copyWith(isLoading: false, result: invitation);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Rejects an invitation by its token.
  ///
  /// Returns true on success, false on failure.
  Future<bool> rejectInvitation(String token) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final repo = _ref.read(invitationRepositoryProvider);
      final invitation = await repo.rejectInvitation(token);

      // Invalidate pending invitations
      _ref.invalidate(userPendingInvitationsProvider);

      // Clear any pending invite code
      _ref.read(pendingInviteCodeProvider.notifier).state = null;

      state = state.copyWith(isLoading: false, result: invitation);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Revokes an invitation (owner action).
  ///
  /// Returns true on success, false on failure.
  Future<bool> revokeInvitation(String invitationId, String libraryId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final userId = _ref.read(currentUserIdProvider);
      if (userId == null) {
        throw Exception('Not authenticated');
      }

      final repo = _ref.read(invitationRepositoryProvider);
      await repo.revokeInvitation(invitationId, userId);

      // Invalidate the library's pending invitations
      _ref.invalidate(libraryPendingInvitationsProvider(libraryId));

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return false;
    }
  }

  /// Clears any error state.
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Resets the state to initial.
  void reset() {
    state = const InvitationActionState();
  }
}

/// Provider for invitation actions (send, accept, reject, revoke).
final invitationNotifierProvider =
    StateNotifierProvider<InvitationNotifier, InvitationActionState>((ref) {
  return InvitationNotifier(ref);
});
