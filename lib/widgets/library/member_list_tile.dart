import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_member_with_user.dart';

/// A list tile displaying a library member with avatar, name, and role.
///
/// Features:
/// - Avatar with initials fallback
/// - Display name and email
/// - Role badge (Owner, Can edit, Can view)
/// - Current user indicator
/// - Remove button for owners managing members
class MemberListTile extends StatelessWidget {
  final LibraryMemberWithUser member;
  final bool isCurrentUser;
  final bool canRemove;
  final VoidCallback? onRemove;

  const MemberListTile({
    super.key,
    required this.member,
    this.isCurrentUser = false,
    this.canRemove = false,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _buildAvatar(),
      title: Row(
        children: [
          Expanded(
            child: Text(
              member.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isCurrentUser)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: SaturdayColors.secondary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'You',
                style: TextStyle(
                  fontSize: 12,
                  color: SaturdayColors.secondary,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        member.email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: SaturdayColors.secondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRoleBadge(context),
          if (canRemove && onRemove != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                Icons.remove_circle_outline,
                color: SaturdayColors.error,
              ),
              tooltip: 'Remove member',
              onPressed: onRemove,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    if (member.avatarUrl != null) {
      return CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(member.avatarUrl!),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    }

    return CircleAvatar(
      radius: 20,
      backgroundColor: _getAvatarColor(),
      child: Text(
        member.initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRoleBadge(BuildContext context) {
    final (backgroundColor, textColor, text) = _getRoleBadgeStyle();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: textColor,
        ),
      ),
    );
  }

  (Color, Color, String) _getRoleBadgeStyle() {
    if (member.isOwner) {
      return (
        SaturdayColors.primaryDark.withValues(alpha: 0.1),
        SaturdayColors.primaryDark,
        'Owner',
      );
    }

    if (member.canEdit) {
      return (
        Colors.green.withValues(alpha: 0.1),
        Colors.green.shade700,
        'Can edit',
      );
    }

    return (
      SaturdayColors.secondary.withValues(alpha: 0.1),
      SaturdayColors.secondary,
      'Can view',
    );
  }

  Color _getAvatarColor() {
    // Generate a consistent color based on the user's email
    final hash = member.email.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
    ];
    return colors[hash.abs() % colors.length];
  }
}
