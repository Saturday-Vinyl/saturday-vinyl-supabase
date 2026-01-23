import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_invitation.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/invitation_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';

/// Screen for viewing and accepting/rejecting a library invitation.
///
/// Handles multiple scenarios:
/// - Valid invitation with logged-in user
/// - Valid invitation with logged-out user (prompts login)
/// - Expired invitation
/// - Invalid/not found invitation
/// - Already accepted/rejected invitation
/// - Already a member of the library
class InvitationAcceptScreen extends ConsumerStatefulWidget {
  final String inviteCode;

  const InvitationAcceptScreen({
    super.key,
    required this.inviteCode,
  });

  @override
  ConsumerState<InvitationAcceptScreen> createState() =>
      _InvitationAcceptScreenState();
}

class _InvitationAcceptScreenState
    extends ConsumerState<InvitationAcceptScreen> {
  bool _isAccepting = false;
  bool _isRejecting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final invitationAsync =
        ref.watch(invitationByTokenProvider(widget.inviteCode));
    final isSignedIn = ref.watch(isSignedInProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library Invitation'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _navigateAway(),
        ),
      ),
      body: SafeArea(
        child: invitationAsync.when(
          data: (invitation) {
            if (invitation == null) {
              return _buildNotFoundState();
            }
            return _buildInvitationContent(context, invitation, isSignedIn);
          },
          loading: () => const LoadingIndicator.medium(
            message: 'Loading invitation...',
          ),
          error: (error, stack) => ErrorDisplay.fullScreen(
            message: 'Failed to load invitation',
            onRetry: () =>
                ref.invalidate(invitationByTokenProvider(widget.inviteCode)),
          ),
        ),
      ),
    );
  }

  Widget _buildInvitationContent(
    BuildContext context,
    LibraryInvitation invitation,
    bool isSignedIn,
  ) {
    // Check invitation status
    if (invitation.isExpired ||
        invitation.status == InvitationStatus.expired) {
      return _buildExpiredState(invitation);
    }

    if (invitation.status == InvitationStatus.accepted) {
      return _buildAlreadyAcceptedState(invitation);
    }

    if (invitation.status == InvitationStatus.rejected) {
      return _buildAlreadyRejectedState(invitation);
    }

    if (invitation.status == InvitationStatus.revoked) {
      return _buildRevokedState(invitation);
    }

    // Valid invitation - show details
    return _buildValidInvitationContent(context, invitation, isSignedIn);
  }

  Widget _buildValidInvitationContent(
    BuildContext context,
    LibraryInvitation invitation,
    bool isSignedIn,
  ) {
    return SingleChildScrollView(
      padding: Spacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),

          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.library_music,
              size: 40,
              color: SaturdayColors.primaryDark,
            ),
          ),

          const SizedBox(height: 24),

          // Invitation message
          Text(
            'You\'ve been invited!',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          Text(
            '${invitation.inviterDisplayName} invited you to join their library',
            style: TextStyle(
              color: SaturdayColors.secondary,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Library details card
          Container(
            decoration: AppDecorations.card,
            padding: Spacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Library name
                Text(
                  invitation.libraryName ?? 'Vinyl Library',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),

                if (invitation.libraryDescription?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    invitation.libraryDescription!,
                    style: TextStyle(color: SaturdayColors.secondary),
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // Role
                Row(
                  children: [
                    Icon(
                      invitation.role.name == 'editor'
                          ? Icons.edit_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: SaturdayColors.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Permission: ${invitation.roleDescription}',
                      style: TextStyle(color: SaturdayColors.secondary),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Invited by
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 20,
                      color: SaturdayColors.secondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'From: ${invitation.inviterDisplayName}',
                      style: TextStyle(color: SaturdayColors.secondary),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Error message
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SaturdayColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: SaturdayColors.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: SaturdayColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Actions
          if (!isSignedIn) ...[
            // Not signed in - show login prompt
            _buildLoginPrompt(context),
          ] else ...[
            // Signed in - show accept/reject buttons
            _buildActionButtons(context, invitation),
          ],
        ],
      ),
    );
  }

  Widget _buildLoginPrompt(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SaturdayColors.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                color: SaturdayColors.secondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Sign in or create an account to accept this invitation',
                  style: TextStyle(color: SaturdayColors.secondary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        ElevatedButton(
          onPressed: () => _navigateToLogin(),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('Sign In'),
        ),

        const SizedBox(height: 12),

        OutlinedButton(
          onPressed: () => _navigateToSignup(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: const Text('Create Account'),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    LibraryInvitation invitation,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed:
              _isAccepting || _isRejecting ? null : () => _acceptInvitation(),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          child: _isAccepting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Accept Invitation'),
        ),

        const SizedBox(height: 12),

        OutlinedButton(
          onPressed:
              _isAccepting || _isRejecting ? null : () => _rejectInvitation(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: SaturdayColors.error,
          ),
          child: _isRejecting
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: SaturdayColors.error,
                  ),
                )
              : const Text('Decline'),
        ),
      ],
    );
  }

  Widget _buildNotFoundState() {
    return _buildErrorState(
      icon: Icons.link_off,
      title: 'Invitation Not Found',
      message: 'This invitation link is invalid or has already been used.',
    );
  }

  Widget _buildExpiredState(LibraryInvitation invitation) {
    return _buildErrorState(
      icon: Icons.timer_off,
      title: 'Invitation Expired',
      message:
          'This invitation from ${invitation.inviterDisplayName} has expired. '
          'Ask them to send you a new one.',
    );
  }

  Widget _buildAlreadyAcceptedState(LibraryInvitation invitation) {
    return _buildSuccessState(
      icon: Icons.check_circle,
      title: 'Already Accepted',
      message:
          'You\'ve already joined ${invitation.libraryName ?? 'this library'}.',
      buttonText: 'Go to Library',
      onButtonPressed: () => _navigateToLibrary(invitation.libraryId),
    );
  }

  Widget _buildAlreadyRejectedState(LibraryInvitation invitation) {
    return _buildErrorState(
      icon: Icons.block,
      title: 'Invitation Declined',
      message: 'You previously declined this invitation. '
          'Ask ${invitation.inviterDisplayName} to send you a new one if you changed your mind.',
    );
  }

  Widget _buildRevokedState(LibraryInvitation invitation) {
    return _buildErrorState(
      icon: Icons.cancel,
      title: 'Invitation Revoked',
      message: 'This invitation has been revoked by the library owner.',
    );
  }

  Widget _buildErrorState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: SaturdayColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: SaturdayColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: SaturdayColors.secondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _navigateAway(),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessState({
    required IconData icon,
    required String title,
    required String message,
    required String buttonText,
    required VoidCallback onButtonPressed,
  }) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 40,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: SaturdayColors.secondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onButtonPressed,
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptInvitation() async {
    setState(() {
      _isAccepting = true;
      _error = null;
    });

    try {
      final success = await ref
          .read(invitationNotifierProvider.notifier)
          .acceptInvitation(widget.inviteCode);

      if (success && mounted) {
        // Get the invitation to find the library ID
        final invitation =
            ref.read(invitationByTokenProvider(widget.inviteCode)).valueOrNull;

        if (invitation != null) {
          // Switch to the new library
          ref.read(currentLibraryIdProvider.notifier).state =
              invitation.libraryId;

          // Show success and navigate to library
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'You\'ve joined ${invitation.libraryName ?? 'the library'}!',
              ),
            ),
          );

          _navigateToLibrary(invitation.libraryId);
        } else {
          context.go(RoutePaths.library);
        }
      } else if (mounted) {
        final errorState = ref.read(invitationNotifierProvider);
        setState(() {
          _error = errorState.error ?? 'Failed to accept invitation';
          _isAccepting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isAccepting = false;
        });
      }
    }
  }

  Future<void> _rejectInvitation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Invitation'),
        content: const Text(
          'Are you sure you want to decline this invitation?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Decline',
              style: TextStyle(color: SaturdayColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRejecting = true;
      _error = null;
    });

    try {
      final success = await ref
          .read(invitationNotifierProvider.notifier)
          .rejectInvitation(widget.inviteCode);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation declined')),
        );
        _navigateAway();
      } else if (mounted) {
        final errorState = ref.read(invitationNotifierProvider);
        setState(() {
          _error = errorState.error ?? 'Failed to decline invitation';
          _isRejecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isRejecting = false;
        });
      }
    }
  }

  void _navigateToLogin() {
    // Store the invite code for after login
    ref.read(pendingInviteCodeProvider.notifier).state = widget.inviteCode;
    context.go(RoutePaths.login);
  }

  void _navigateToSignup() {
    // Store the invite code for after signup
    ref.read(pendingInviteCodeProvider.notifier).state = widget.inviteCode;
    context.go(RoutePaths.signup);
  }

  void _navigateToLibrary(String libraryId) {
    context.go(RoutePaths.library);
  }

  void _navigateAway() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RoutePaths.nowPlaying);
    }
  }
}
