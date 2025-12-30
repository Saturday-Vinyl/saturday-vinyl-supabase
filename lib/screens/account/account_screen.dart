import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';

/// Account screen - user profile and settings.
///
/// Features:
/// - User profile info
/// - Device management
/// - Shared libraries
/// - App settings
/// - Help & support
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentSupabaseUserProvider);
    return Scaffold(
      appBar: const SaturdayAppBar(
        title: 'Account',
        showLibrarySwitcher: false,
        showSearch: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: Spacing.pagePadding,
          children: [
            // Profile card
            _buildProfileCard(context, user),

            Spacing.sectionGap,

            // Devices section
            _buildSectionHeader(context, 'Devices'),
            Spacing.itemGap,
            _buildSettingsTile(
              context,
              icon: Icons.speaker_group,
              title: 'My Devices',
              subtitle: 'No devices connected',
              onTap: () {
                // TODO: Navigate to device management
              },
            ),
            _buildSettingsTile(
              context,
              icon: Icons.add_circle_outline,
              title: 'Add Device',
              subtitle: 'Connect a Saturday turntable or speaker',
              onTap: () {
                // TODO: Start device setup
              },
            ),

            Spacing.sectionGap,

            // Libraries section
            _buildSectionHeader(context, 'Libraries'),
            Spacing.itemGap,
            _buildSettingsTile(
              context,
              icon: Icons.library_music,
              title: 'My Libraries',
              subtitle: '1 library',
              onTap: () {
                // TODO: Navigate to libraries
              },
            ),
            _buildSettingsTile(
              context,
              icon: Icons.share,
              title: 'Shared Libraries',
              subtitle: 'No shared libraries',
              onTap: () {
                // TODO: Navigate to shared libraries
              },
            ),

            Spacing.sectionGap,

            // Settings section
            _buildSectionHeader(context, 'Settings'),
            Spacing.itemGap,
            _buildSettingsTile(
              context,
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              onTap: () {
                // TODO: Navigate to notifications
              },
            ),
            _buildSettingsTile(
              context,
              icon: Icons.palette_outlined,
              title: 'Appearance',
              onTap: () {
                // TODO: Navigate to appearance settings
              },
            ),
            _buildSettingsTile(
              context,
              icon: Icons.storage_outlined,
              title: 'Storage',
              onTap: () {
                // TODO: Navigate to storage settings
              },
            ),

            Spacing.sectionGap,

            // Support section
            _buildSectionHeader(context, 'Support'),
            Spacing.itemGap,
            _buildSettingsTile(
              context,
              icon: Icons.help_outline,
              title: 'Help & FAQ',
              onTap: () {
                // TODO: Open help
              },
            ),
            _buildSettingsTile(
              context,
              icon: Icons.mail_outline,
              title: 'Contact Us',
              onTap: () {
                // TODO: Open contact
              },
            ),
            _buildSettingsTile(
              context,
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'Version 1.0.0',
              onTap: () {
                // TODO: Show about dialog
              },
            ),

            Spacing.sectionGap,

            // Sign out button
            if (ref.watch(currentSupabaseUserProvider) != null)
              _buildSignOutButton(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildSignOutButton(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Sign Out'),
            content: const Text('Are you sure you want to sign out?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Sign Out'),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          await ref.read(signOutProvider.future);
          if (context.mounted) {
            context.go(RoutePaths.login);
          }
        }
      },
      icon: Icon(Icons.logout, color: SaturdayColors.error),
      label: Text(
        'Sign Out',
        style: TextStyle(color: SaturdayColors.error),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, dynamic user) {
    final isSignedIn = user != null;

    return GestureDetector(
      onTap: () {
        if (isSignedIn) {
          // TODO: Navigate to profile details
        } else {
          context.push(RoutePaths.login);
        }
      },
      child: Container(
        decoration: AppDecorations.card,
        padding: Spacing.cardPadding,
        child: Row(
          children: [
            // Avatar
            Container(
              width: 64,
              height: 64,
              decoration: AppDecorations.avatar,
              child: Icon(
                isSignedIn ? Icons.person : Icons.person_outline,
                size: 32,
                color: SaturdayColors.white,
              ),
            ),
            Spacing.horizontalGapLg,
            // User info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSignedIn
                        ? (user.userMetadata?['full_name'] as String? ??
                            user.email ??
                            'User')
                        : 'Sign In',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSignedIn
                        ? user.email ?? ''
                        : 'Sign in to sync your library across devices',
                    style: TextStyle(
                      color: SaturdayColors.secondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
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

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppDecorations.card,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
