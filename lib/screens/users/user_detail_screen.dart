import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/user.dart';
import 'package:saturday_app/providers/users_provider.dart';
import 'package:saturday_app/widgets/common/app_button.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/common/user_avatar.dart';
import 'package:saturday_app/utils/extensions.dart';

class UserDetailScreen extends ConsumerWidget {
  final User user;

  const UserDetailScreen({super.key, required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allPermissionsAsync = ref.watch(allPermissionsProvider);
    final userPermissionsAsync = ref.watch(userPermissionDetailsProvider(user.id));

    return Scaffold(
      backgroundColor: SaturdayColors.light,
      appBar: AppBar(
        title: const Text('User Details'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User profile card
            _buildProfileCard(context),
            const SizedBox(height: 24),

            // Permissions section
            Text(
              'Permissions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: SaturdayColors.primaryDark,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            if (user.isAdmin)
              _buildAdminNotice()
            else
              allPermissionsAsync.when(
                data: (permissions) => userPermissionsAsync.when(
                  data: (userPermissions) => _buildPermissionsList(
                    context,
                    ref,
                    permissions,
                    userPermissions,
                  ),
                  loading: () => const LoadingIndicator(message: 'Loading permissions...'),
                  error: (error, stack) => _buildError(error.toString()),
                ),
                loading: () => const LoadingIndicator(message: 'Loading...'),
                error: (error, stack) => _buildError(error.toString()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: SaturdayColors.secondaryGrey, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            UserAvatar(
              displayName: user.fullName,
              email: user.email,
              size: AvatarSize.large,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.fullName ?? 'Unknown User',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: SaturdayColors.primaryDark,
                          ),
                        ),
                      ),
                      if (user.isAdmin) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: SaturdayColors.success,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ADMIN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.email,
                    style: const TextStyle(
                      fontSize: 14,
                      color: SaturdayColors.secondaryGrey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildInfoChip(
                        'Joined ${user.createdAt.friendlyDate}',
                        Icons.calendar_today,
                      ),
                      const SizedBox(width: 8),
                      _buildInfoChip(
                        user.isActive ? 'Active' : 'Inactive',
                        Icons.circle,
                        color: user.isActive ? SaturdayColors.success : SaturdayColors.error,
                      ),
                    ],
                  ),
                  if (user.lastLogin != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Last login: ${user.lastLogin!.timeAgo}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: SaturdayColors.secondaryGrey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, IconData icon, {Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? SaturdayColors.secondaryGrey).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color ?? SaturdayColors.secondaryGrey,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color ?? SaturdayColors.secondaryGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminNotice() {
    return Card(
      elevation: 0,
      color: SaturdayColors.info.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: SaturdayColors.info, width: 1),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: SaturdayColors.info),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'This user is an administrator and has access to all features.',
                style: TextStyle(
                  color: SaturdayColors.info,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsList(
    BuildContext context,
    WidgetRef ref,
    List permissions,
    Map<String, bool> userPermissions,
  ) {
    return Column(
      children: permissions.map((permission) {
        final hasPermission = userPermissions[permission.id] ?? false;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: SaturdayColors.secondaryGrey, width: 1),
          ),
          child: CheckboxListTile(
            title: Text(
              permission.name.snakeToTitleCase,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: SaturdayColors.primaryDark,
              ),
            ),
            subtitle: permission.description != null
                ? Text(
                    permission.description!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SaturdayColors.secondaryGrey,
                    ),
                  )
                : null,
            value: hasPermission,
            activeColor: SaturdayColors.success,
            onChanged: (bool? value) {
              if (value == null) return;
              _handlePermissionToggle(context, ref, permission.id, value);
            },
          ),
        );
      }).toList(),
    );
  }

  Future<void> _handlePermissionToggle(
    BuildContext context,
    WidgetRef ref,
    String permissionId,
    bool grant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(grant ? 'Grant Permission' : 'Revoke Permission'),
        content: Text(
          grant
              ? 'Are you sure you want to grant this permission to ${user.fullName ?? user.email}?'
              : 'Are you sure you want to revoke this permission from ${user.fullName ?? user.email}?',
        ),
        actions: [
          AppButton(
            text: 'Cancel',
            style: AppButtonStyle.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            text: grant ? 'Grant' : 'Revoke',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userManagement = ref.read(userManagementProvider);

      if (grant) {
        await userManagement.grantPermission(
          userId: user.id,
          permissionId: permissionId,
        );
      } else {
        await userManagement.revokePermission(
          userId: user.id,
          permissionId: permissionId,
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              grant ? 'Permission granted successfully' : 'Permission revoked successfully',
            ),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${error.toString()}'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Widget _buildError(String error) {
    return Card(
      color: SaturdayColors.error.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: SaturdayColors.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error,
                style: const TextStyle(color: SaturdayColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
