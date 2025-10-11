import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/user_avatar.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/loading_indicator.dart';
import '../../utils/app_logger.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  Future<void> _handleLogout(BuildContext context, WidgetRef ref) async {
    try {
      final authService = ref.read(authServiceProvider);
      await authService.signOut();
      AppLogger.info('User signed out successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Sign out failed', error, stackTrace);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to sign out. Please try again.'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserAsync = ref.watch(currentUserProvider);
    final permissionsAsync = ref.watch(userPermissionsProvider);

    return Scaffold(
      backgroundColor: SaturdayColors.light,
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          currentUserAsync.when(
            data: (user) => user != null
                ? Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: UserAvatar(
                      photoUrl: null, // Google photo URL would go here
                      displayName: user.fullName,
                      email: user.email,
                      size: AvatarSize.small,
                    ),
                  )
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: currentUserAsync.when(
        data: (user) {
          if (user == null) {
            return const Center(
              child: Text('No user data available'),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Section
                _buildProfileCard(user, ref),
                const SizedBox(height: 24),

                // Permissions Section
                _buildPermissionsCard(user, permissionsAsync),
                const SizedBox(height: 24),

                // Actions Section
                _buildActionsCard(context, ref),
              ],
            ),
          );
        },
        loading: () => const LoadingIndicator(message: 'Loading profile...'),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: SaturdayColors.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading profile',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: SaturdayColors.secondaryGrey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(user, WidgetRef ref) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(
          color: SaturdayColors.secondaryGrey,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  photoUrl: null,
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
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (user.isAdmin) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
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
                      const SizedBox(height: 4),
                      Text(
                        user.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 12,
                          color: user.isActive
                              ? SaturdayColors.success
                              : SaturdayColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsCard(user, AsyncValue<List<String>> permissionsAsync) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(
          color: SaturdayColors.secondaryGrey,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Permissions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: SaturdayColors.primaryDark,
              ),
            ),
            const SizedBox(height: 12),
            permissionsAsync.when(
              data: (permissions) {
                if (user.isAdmin) {
                  return const Text(
                    'As an admin, you have access to all features.',
                    style: TextStyle(
                      color: SaturdayColors.secondaryGrey,
                      fontSize: 14,
                    ),
                  );
                }
                if (permissions.isEmpty) {
                  return const Text(
                    'No permissions assigned yet.',
                    style: TextStyle(
                      color: SaturdayColors.secondaryGrey,
                      fontSize: 14,
                    ),
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: permissions.map((permission) {
                    return Chip(
                      label: Text(
                        _formatPermissionName(permission),
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: SaturdayColors.info.withValues(alpha: 0.2),
                      side: const BorderSide(
                        color: SaturdayColors.info,
                        width: 1,
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const Text(
                'Loading permissions...',
                style: TextStyle(
                  color: SaturdayColors.secondaryGrey,
                  fontSize: 14,
                ),
              ),
              error: (_, __) => const Text(
                'Failed to load permissions',
                style: TextStyle(
                  color: SaturdayColors.error,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context, WidgetRef ref) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(
          color: SaturdayColors.secondaryGrey,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Account Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: SaturdayColors.primaryDark,
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              text: 'Sign Out',
              icon: Icons.logout,
              style: AppButtonStyle.secondary,
              onPressed: () => _handleLogout(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  String _formatPermissionName(String permission) {
    // Convert snake_case to Title Case
    return permission
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }
}
