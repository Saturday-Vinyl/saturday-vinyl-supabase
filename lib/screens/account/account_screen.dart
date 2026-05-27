import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_member.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/providers/intro_splash_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/services/push_token_service.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/devices/devices.dart';

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
            _buildDevicesSection(context, ref),

            Spacing.sectionGap,

            // Libraries section
            _buildSectionHeader(context, 'Libraries'),
            Spacing.itemGap,
            _buildLibrariesSection(context, ref),

            Spacing.sectionGap,

            // Settings section
            _buildSectionHeader(context, 'Settings'),
            Spacing.itemGap,
            _buildSettingsTile(
              context,
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              onTap: () => context.pushNamed(RouteNames.notificationSettings),
            ),
            _buildSettingsTile(
              context,
              icon: Icons.tv,
              title: 'Pair TV',
              subtitle: 'Connect your Saturday Apple TV app',
              onTap: () => context.pushNamed(RouteNames.pairTv),
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

            // Debug section (only in debug mode)
            if (kDebugMode) ...[
              Spacing.sectionGap,
              _buildSectionHeader(context, 'Debug'),
              Spacing.itemGap,
              _buildSettingsTile(
                context,
                icon: Icons.replay,
                title: 'Reset Intro Splash',
                subtitle: 'Show splash screen on next launch',
                onTap: () async {
                  await ref
                      .read(introSplashNotifierProvider.notifier)
                      .resetSplash();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Splash reset. Restart app to see it.'),
                        ),
                      );
                  }
                },
              ),
              _buildSettingsTile(
                context,
                icon: Icons.play_arrow,
                title: 'Show Intro Splash Now',
                subtitle: 'Navigate to splash screen immediately',
                onTap: () {
                  // Navigate directly without resetting state to avoid redirect loops
                  context.go(RoutePaths.introSplash);
                },
              ),
            ],

            // Admin section — visible in release builds for @saturdayvinyl.com users
            if (_isAdmin(user)) ...[
              Spacing.sectionGap,
              _buildSectionHeader(context, 'Admin'),
              Spacing.itemGap,
              _buildSettingsTile(
                context,
                icon: Icons.vpn_key,
                title: 'Push Token',
                subtitle: 'View and copy the current FCM token',
                onTap: () => _showPushTokenDialog(context),
              ),
            ],
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
          context.pushNamed(RouteNames.profile);
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

  bool _isAdmin(dynamic user) {
    final email = user?.email as String?;
    return email != null && email.endsWith('@saturdayvinyl.com');
  }

  Future<void> _showPushTokenDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => const _PushTokenDialog(),
    );
  }

  Widget _buildDevicesSection(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(userDevicesProvider);

    return devicesAsync.when(
      data: (devices) {
        final hubCount = devices.where((d) => d.isHub).length;
        final crateCount = devices.where((d) => d.isCrate).length;
        // Use isEffectivelyOnline to account for heartbeat staleness
        final onlineCount = devices.where((d) => d.isEffectivelyOnline).length;

        return Column(
          children: [
            // Device summary card
            DeviceMiniCard(
              hubCount: hubCount,
              crateCount: crateCount,
              onlineCount: onlineCount,
              onTap: () => context.pushNamed(RouteNames.deviceList),
            ),
            const SizedBox(height: 8),
            // Add device button
            _buildSettingsTile(
              context,
              icon: Icons.add_circle_outline,
              title: 'Add Device',
              subtitle: 'Connect a Saturday Hub or Crate',
              onTap: () => context.pushNamed(RouteNames.deviceSetup),
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) {
        // Log the error for debugging
        debugPrint('Device loading error: $error');
        debugPrint('Stack trace: $stack');
        return _buildSettingsTile(
          context,
          icon: Icons.error_outline,
          title: 'My Devices',
          subtitle: 'Tap to retry',
          onTap: () => ref.invalidate(userDevicesProvider),
        );
      },
    );
  }

  Widget _buildLibrariesSection(BuildContext context, WidgetRef ref) {
    final librariesAsync = ref.watch(userLibrariesProvider);

    return librariesAsync.when(
      data: (libraries) {
        // Separate owned vs shared libraries
        final ownedLibraries =
            libraries.where((l) => l.role == LibraryRole.owner).toList();
        final sharedLibraries =
            libraries.where((l) => l.role != LibraryRole.owner).toList();

        final ownedCount = ownedLibraries.length;
        final sharedCount = sharedLibraries.length;

        return Column(
          children: [
            // My Libraries - navigate to current library details
            _buildSettingsTile(
              context,
              icon: Icons.library_music,
              title: 'My Libraries',
              subtitle: ownedCount == 0
                  ? 'No libraries'
                  : '$ownedCount ${ownedCount == 1 ? 'library' : 'libraries'}',
              onTap: () {
                // Navigate to current library details
                context.pushNamed(RouteNames.libraryDetails);
              },
            ),
            // Shared Libraries
            _buildSettingsTile(
              context,
              icon: Icons.share,
              title: 'Shared with Me',
              subtitle: sharedCount == 0
                  ? 'No shared libraries'
                  : '$sharedCount ${sharedCount == 1 ? 'library' : 'libraries'}',
              onTap: () {
                if (sharedCount > 0) {
                  // Switch to first shared library and go to its details
                  ref.read(currentLibraryIdProvider.notifier).state =
                      sharedLibraries.first.library.id;
                  context.pushNamed(RouteNames.libraryDetails);
                } else {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No shared libraries yet. Ask someone to share their library with you!',
                        ),
                      ),
                    );
                }
              },
            ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stack) => _buildSettingsTile(
        context,
        icon: Icons.error_outline,
        title: 'Libraries',
        subtitle: 'Tap to retry',
        onTap: () => ref.invalidate(userLibrariesProvider),
      ),
    );
  }
}

class _PushTokenDialog extends StatefulWidget {
  const _PushTokenDialog();

  @override
  State<_PushTokenDialog> createState() => _PushTokenDialogState();
}

class _PushTokenDialogState extends State<_PushTokenDialog> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) {
    final token = PushTokenService.instance.currentToken;
    return AlertDialog(
      title: const Text('Push Token'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (token == null)
              const Text('No token registered yet.')
            else
              SelectableText(
                token,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Compare against push_notification_tokens.token in Supabase. '
              'If they differ, tap Refresh to rotate.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: token == null
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: token));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..clearSnackBars()
                      ..showSnackBar(
                        const SnackBar(content: Text('Token copied')),
                      );
                  }
                },
          child: const Text('Copy'),
        ),
        TextButton(
          onPressed: _refreshing
              ? null
              : () async {
                  setState(() => _refreshing = true);
                  final fresh =
                      await PushTokenService.instance.forceRefresh();
                  if (!context.mounted) return;
                  setState(() => _refreshing = false);
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          fresh != null
                              ? 'Token refreshed'
                              : 'Refresh failed — check logs',
                        ),
                      ),
                    );
                },
          child: _refreshing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Refresh'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
