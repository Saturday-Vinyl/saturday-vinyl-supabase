import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_details.dart';
import 'package:saturday_consumer_app/models/library_invitation.dart';
import 'package:saturday_consumer_app/models/library_member_with_user.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/invitation_provider.dart';
import 'package:saturday_consumer_app/providers/library_details_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
import 'package:saturday_consumer_app/widgets/library/member_list_tile.dart';
import 'package:saturday_consumer_app/widgets/library/share_library_bottom_sheet.dart';

/// Screen displaying library details, members, and popular albums.
///
/// Features:
/// - Library metadata (name, description, created date)
/// - Album count
/// - Member list with roles
/// - Popular albums by play count
/// - Share library button (owner only)
/// - Pending invitations section (owner only)
/// - Leave library option (non-owners)
class LibraryDetailsScreen extends ConsumerWidget {
  const LibraryDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryId = ref.watch(currentLibraryIdProvider);
    if (libraryId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Library Details')),
        body: const Center(child: Text('No library selected')),
      );
    }

    final detailsAsync = ref.watch(libraryDetailsProvider(libraryId));
    final isOwner = ref.watch(isCurrentLibraryOwnerProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library Details'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share Library',
              onPressed: () => _showShareSheet(context, ref, libraryId),
            ),
        ],
      ),
      body: detailsAsync.when(
        data: (details) => _buildContent(
          context,
          ref,
          details,
          isOwner,
          currentUserId,
          libraryId,
        ),
        loading: () => const LoadingIndicator.medium(
          message: 'Loading library details...',
        ),
        error: (error, stack) => ErrorDisplay.fullScreen(
          message: error.toString(),
          onRetry: () => ref.invalidate(libraryDetailsProvider(libraryId)),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    LibraryDetails details,
    bool isOwner,
    String? currentUserId,
    String libraryId,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(libraryDetailsProvider(libraryId));
        if (isOwner) {
          ref.invalidate(libraryPendingInvitationsProvider(libraryId));
        }
        await ref.read(libraryDetailsProvider(libraryId).future);
      },
      child: ListView(
        padding: Spacing.pagePadding,
        children: [
          // Library info card
          _buildInfoCard(context, details),

          Spacing.sectionGap,

          // Album count section
          _buildAlbumCountSection(context, details),

          Spacing.sectionGap,

          // Popular albums section
          if (details.popularAlbums.isNotEmpty) ...[
            _buildPopularAlbumsSection(context, ref, details),
            Spacing.sectionGap,
          ],

          // Members section
          _buildMembersSection(context, ref, details, isOwner, currentUserId),

          // Pending invitations section (owner only)
          if (isOwner) ...[
            Spacing.sectionGap,
            _buildPendingInvitationsSection(context, ref, libraryId),
          ],

          // Leave library button (non-owner only)
          if (!isOwner && currentUserId != null) ...[
            Spacing.sectionGap,
            _buildLeaveLibraryButton(context, ref, libraryId, currentUserId),
          ],

          // Share button at bottom (owner only)
          if (isOwner) ...[
            Spacing.sectionGap,
            _buildShareButton(context, ref, libraryId),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, LibraryDetails details) {
    return Container(
      decoration: AppDecorations.card,
      padding: Spacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Library name
          Text(
            details.library.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),

          if (details.library.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              details.library.description!,
              style: TextStyle(
                color: SaturdayColors.secondary,
                fontSize: 14,
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Created date
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 16,
                color: SaturdayColors.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Created ${_formatDate(details.library.createdAt)}',
                style: TextStyle(
                  color: SaturdayColors.secondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Member count
          Row(
            children: [
              Icon(
                Icons.people_outline,
                size: 16,
                color: SaturdayColors.secondary,
              ),
              const SizedBox(width: 8),
              Text(
                '${details.memberCount} ${details.memberCount == 1 ? 'member' : 'members'}',
                style: TextStyle(
                  color: SaturdayColors.secondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumCountSection(BuildContext context, LibraryDetails details) {
    return Container(
      decoration: AppDecorations.card,
      padding: Spacing.cardPadding,
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.album,
              size: 28,
              color: SaturdayColors.primaryDark,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${details.albumCount}',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  details.albumCount == 1 ? 'Album' : 'Albums',
                  style: TextStyle(
                    color: SaturdayColors.secondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // Navigate back to library screen
              Navigator.of(context).pop();
            },
            child: const Text('View All'),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularAlbumsSection(
    BuildContext context,
    WidgetRef ref,
    LibraryDetails details,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Most Played'),
        const SizedBox(height: 12),
        Container(
          decoration: AppDecorations.card,
          child: Column(
            children: details.popularAlbums.map((album) {
              final index = details.popularAlbums.indexOf(album);
              return Column(
                children: [
                  ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: album.coverImageUrl != null
                          ? Image.network(
                              album.coverImageUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildAlbumPlaceholder(),
                            )
                          : _buildAlbumPlaceholder(),
                    ),
                    title: Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: SaturdayColors.secondary),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${album.playCount}',
                          style: TextStyle(
                            color: SaturdayColors.secondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.play_arrow,
                          size: 16,
                          color: SaturdayColors.secondary,
                        ),
                      ],
                    ),
                    onTap: () {
                      context.push('${RoutePaths.library}/album/${album.id}');
                    },
                  ),
                  if (index < details.popularAlbums.length - 1)
                    const Divider(height: 1, indent: 72),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Icon(
        Icons.album,
        color: SaturdayColors.secondary,
      ),
    );
  }

  Widget _buildMembersSection(
    BuildContext context,
    WidgetRef ref,
    LibraryDetails details,
    bool isOwner,
    String? currentUserId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Members'),
        const SizedBox(height: 12),
        Container(
          decoration: AppDecorations.card,
          child: Column(
            children: details.members.asMap().entries.map((entry) {
              final index = entry.key;
              final member = entry.value;
              final isCurrentUser = member.member.userId == currentUserId;

              return Column(
                children: [
                  MemberListTile(
                    member: member,
                    isCurrentUser: isCurrentUser,
                    canRemove: isOwner && !member.isOwner && !isCurrentUser,
                    onRemove: isOwner && !member.isOwner && !isCurrentUser
                        ? () => _confirmRemoveMember(
                              context,
                              ref,
                              details.library.id,
                              member,
                            )
                        : null,
                  ),
                  if (index < details.members.length - 1)
                    const Divider(height: 1, indent: 72),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPendingInvitationsSection(
    BuildContext context,
    WidgetRef ref,
    String libraryId,
  ) {
    final invitationsAsync =
        ref.watch(libraryPendingInvitationsProvider(libraryId));

    return invitationsAsync.when(
      data: (invitations) {
        if (invitations.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Pending Invitations'),
            const SizedBox(height: 12),
            Container(
              decoration: AppDecorations.card,
              child: Column(
                children: invitations.asMap().entries.map((entry) {
                  final index = entry.key;
                  final invitation = entry.value;

                  return Column(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                SaturdayColors.secondary.withValues(alpha: 0.2),
                          ),
                          child: Center(
                            child: Text(
                              invitation.invitedEmail[0].toUpperCase(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: SaturdayColors.secondary,
                              ),
                            ),
                          ),
                        ),
                        title: Text(invitation.invitedEmail),
                        subtitle: Text(
                          invitation.roleDescription,
                          style: TextStyle(color: SaturdayColors.secondary),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Revoke invitation',
                          onPressed: () => _confirmRevokeInvitation(
                            context,
                            ref,
                            invitation,
                            libraryId,
                          ),
                        ),
                      ),
                      if (index < invitations.length - 1)
                        const Divider(height: 1, indent: 72),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildLeaveLibraryButton(
    BuildContext context,
    WidgetRef ref,
    String libraryId,
    String userId,
  ) {
    return TextButton.icon(
      onPressed: () => _confirmLeaveLibrary(context, ref, libraryId, userId),
      icon: Icon(Icons.exit_to_app, color: SaturdayColors.error),
      label: Text(
        'Leave Library',
        style: TextStyle(color: SaturdayColors.error),
      ),
    );
  }

  Widget _buildShareButton(
    BuildContext context,
    WidgetRef ref,
    String libraryId,
  ) {
    return ElevatedButton.icon(
      onPressed: () => _showShareSheet(context, ref, libraryId),
      icon: const Icon(Icons.person_add),
      label: const Text('Invite Members'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: SaturdayColors.secondary,
          ),
    );
  }

  void _showShareSheet(BuildContext context, WidgetRef ref, String libraryId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => ShareLibraryBottomSheet(libraryId: libraryId),
    );
  }

  Future<void> _confirmRemoveMember(
    BuildContext context,
    WidgetRef ref,
    String libraryId,
    LibraryMemberWithUser member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
          'Are you sure you want to remove ${member.displayName} from this library?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Remove',
              style: TextStyle(color: SaturdayColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // TODO: Implement member removal via repository
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${member.displayName} has been removed')),
      );
      ref.invalidate(libraryDetailsProvider(libraryId));
    }
  }

  Future<void> _confirmRevokeInvitation(
    BuildContext context,
    WidgetRef ref,
    LibraryInvitation invitation,
    String libraryId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Invitation'),
        content: Text(
          'Are you sure you want to revoke the invitation to ${invitation.invitedEmail}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Revoke',
              style: TextStyle(color: SaturdayColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final success = await ref
          .read(invitationNotifierProvider.notifier)
          .revokeInvitation(invitation.id, libraryId);

      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invitation revoked')),
          );
        } else {
          final error = ref.read(invitationNotifierProvider).error;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error ?? 'Failed to revoke invitation')),
          );
        }
      }
    }
  }

  Future<void> _confirmLeaveLibrary(
    BuildContext context,
    WidgetRef ref,
    String libraryId,
    String userId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Library'),
        content: const Text(
          'Are you sure you want to leave this library? You will lose access to all albums in it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Leave',
              style: TextStyle(color: SaturdayColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      // TODO: Implement leave library via repository
      ref.invalidate(userLibrariesProvider);
      if (context.mounted) {
        context.go(RoutePaths.library);
      }
    }
  }

  /// Format a date as "Month Day, Year" (e.g., "Jan 15, 2024").
  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
