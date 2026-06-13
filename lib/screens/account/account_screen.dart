import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/library_member.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/providers/intro_splash_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/services/push_token_service.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/devices/devices.dart';
import 'package:saturday_consumer_app/widgets/foundation/saturday_skeleton.dart';

/// Account screen — profile, devices, collections, and settings.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentSupabaseUserProvider);
    final colors = SaturdayColorTokens.of(context);

    return Scaffold(
      appBar: const SaturdayAppBar(
        title: 'Account',
        showLibrarySwitcher: false,
        showSearch: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SaturdaySpace.space4),
          children: [
            _ProfileCard(user: user, colors: colors),

            const SizedBox(height: SaturdaySpace.space8),

            _SectionEyebrow(label: 'Devices', colors: colors),
            const SizedBox(height: SaturdaySpace.space3),
            _DevicesSection(colors: colors),

            const SizedBox(height: SaturdaySpace.space8),

            _SectionEyebrow(label: 'Collections', colors: colors),
            const SizedBox(height: SaturdaySpace.space3),
            _CollectionsSection(colors: colors),

            const SizedBox(height: SaturdaySpace.space8),

            _SectionEyebrow(label: 'Settings', colors: colors),
            const SizedBox(height: SaturdaySpace.space3),
            _SettingsTile(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              colors: colors,
              onTap: () => context.pushNamed(RouteNames.notificationSettings),
            ),
            _SettingsTile(
              icon: Icons.tv,
              title: 'Pair TV',
              subtitle: 'Connect your Saturday Apple TV app',
              colors: colors,
              onTap: () => context.pushNamed(RouteNames.pairTv),
            ),
            _SettingsTile(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              colors: colors,
              onTap: () {
                // TODO: Navigate to appearance settings
              },
            ),
            _SettingsTile(
              icon: Icons.storage_outlined,
              title: 'Storage',
              colors: colors,
              onTap: () {
                // TODO: Navigate to storage settings
              },
            ),

            const SizedBox(height: SaturdaySpace.space8),

            _SectionEyebrow(label: 'Support', colors: colors),
            const SizedBox(height: SaturdaySpace.space3),
            _SettingsTile(
              icon: Icons.help_outline,
              title: 'Help',
              colors: colors,
              onTap: () {
                // TODO: Open help
              },
            ),
            _SettingsTile(
              icon: Icons.mail_outline,
              title: 'Contact',
              colors: colors,
              onTap: () {
                // TODO: Open contact
              },
            ),
            _SettingsTile(
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'Version 1.0.0',
              colors: colors,
              onTap: () {
                // TODO: Show about dialog
              },
            ),

            const SizedBox(height: SaturdaySpace.space8),

            if (user != null)
              _SignOutButton(
                onSignOut: () async {
                  // Destructive actions are sovereign per the constitution —
                  // no confirmation modal. Recovery is signing back in.
                  await ref.read(signOutProvider.future);
                  if (context.mounted) context.go(RoutePaths.login);
                },
              ),

            if (kDebugMode) ...[
              const SizedBox(height: SaturdaySpace.space8),
              _SectionEyebrow(label: 'Debug', colors: colors),
              const SizedBox(height: SaturdaySpace.space3),
              _SettingsTile(
                icon: Icons.replay,
                title: 'Reset intro splash',
                subtitle: 'Show splash screen on next launch',
                colors: colors,
                onTap: () async {
                  await ref
                      .read(introSplashNotifierProvider.notifier)
                      .resetSplash();
                },
              ),
              _SettingsTile(
                icon: Icons.play_arrow,
                title: 'Show intro splash now',
                subtitle: 'Navigate to splash screen immediately',
                colors: colors,
                onTap: () => context.go(RoutePaths.introSplash),
              ),
            ],

            if (_isAdmin(user)) ...[
              const SizedBox(height: SaturdaySpace.space8),
              _SectionEyebrow(label: 'Admin', colors: colors),
              const SizedBox(height: SaturdaySpace.space3),
              _SettingsTile(
                icon: Icons.vpn_key,
                title: 'Push token',
                subtitle: 'View and copy the current FCM token',
                colors: colors,
                onTap: () => _showPushTokenDialog(context),
              ),
            ],
          ],
        ),
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
}

// =============================================================================
// Profile card
// =============================================================================

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.user, required this.colors});

  final dynamic user;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final isSignedIn = user != null;
    final name = isSignedIn
        ? (user.userMetadata?['full_name'] as String?)
        : null;
    final email = isSignedIn ? user.email as String? : null;
    final primaryLine = name ?? email ?? (isSignedIn ? 'Signed in' : 'Sign in');
    final secondaryLine = isSignedIn
        ? (name != null && email != null ? email : null)
        : 'Sync your collection across devices';

    return GestureDetector(
      onTap: () {
        if (isSignedIn) {
          context.pushNamed(RouteNames.profile);
        } else {
          context.push(RoutePaths.login);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(SaturdaySpace.space4),
        decoration: BoxDecoration(
          color: colors.paperElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.borderQuiet),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colors.paper,
                shape: BoxShape.circle,
                border: Border.all(color: colors.borderQuiet),
              ),
              child: Icon(
                isSignedIn ? Icons.person : Icons.person_outline,
                size: 32,
                color: colors.ink,
              ),
            ),
            const SizedBox(width: SaturdaySpace.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    primaryLine,
                    style: SaturdayType.body.copyWith(
                      fontSize: 16,
                      fontWeight: SaturdayType.medium,
                      color: colors.ink,
                    ),
                  ),
                  if (secondaryLine != null) ...[
                    const SizedBox(height: SaturdaySpace.space1),
                    Text(
                      secondaryLine,
                      style: SaturdayType.meta.copyWith(
                        color: colors.inkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colors.inkTertiary),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Section eyebrow
// =============================================================================

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.label, required this.colors});

  final String label;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: SaturdayType.eyebrow.copyWith(color: colors.inkSecondary),
    );
  }
}

// =============================================================================
// Settings tile
// =============================================================================

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final SaturdayColorTokens colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: SaturdaySpace.space2),
      decoration: BoxDecoration(
        color: colors.paperElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderQuiet),
      ),
      child: ListTile(
        leading: Icon(icon, color: colors.ink),
        title: Text(
          title,
          style: SaturdayType.body.copyWith(color: colors.ink),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: SaturdayType.meta.copyWith(color: colors.inkSecondary),
              )
            : null,
        trailing: Icon(Icons.chevron_right, color: colors.inkTertiary),
        onTap: onTap,
      ),
    );
  }
}

// =============================================================================
// Sign-out button (no confirmation — destructive actions are sovereign)
// =============================================================================

class _SignOutButton extends StatelessWidget {
  const _SignOutButton({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () async => onSignOut(),
      icon: const Icon(Icons.logout),
      label: const Text('Sign out'),
    );
  }
}

// =============================================================================
// Devices section
// =============================================================================

class _DevicesSection extends ConsumerWidget {
  const _DevicesSection({required this.colors});

  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(userDevicesProvider);

    return devicesAsync.when(
      data: (devices) {
        final hubCount = devices.where((d) => d.isHub).length;
        final crateCount = devices.where((d) => d.isCrate).length;
        final onlineCount =
            devices.where((d) => d.isEffectivelyOnline).length;

        return Column(
          children: [
            DeviceMiniCard(
              hubCount: hubCount,
              crateCount: crateCount,
              onlineCount: onlineCount,
              onTap: () => context.pushNamed(RouteNames.deviceList),
            ),
            const SizedBox(height: SaturdaySpace.space2),
            _SettingsTile(
              icon: Icons.add_circle_outline,
              title: 'Add device',
              subtitle: 'Connect a Saturday hub or crate',
              colors: colors,
              onTap: () => context.pushNamed(RouteNames.deviceSetup),
            ),
          ],
        );
      },
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: SaturdaySpace.space2),
        child: SaturdaySkeleton.rect(
          width: double.infinity,
          height: 96,
          radius: 12,
        ),
      ),
      error: (error, stack) {
        debugPrint('Device loading error: $error');
        debugPrint('Stack trace: $stack');
        return _SettingsTile(
          icon: Icons.error_outline,
          title: 'Devices',
          subtitle: "Devices aren't responding.",
          colors: colors,
          onTap: () => ref.invalidate(userDevicesProvider),
        );
      },
    );
  }
}

// =============================================================================
// Collections section (previously "Libraries")
// =============================================================================

class _CollectionsSection extends ConsumerWidget {
  const _CollectionsSection({required this.colors});

  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final librariesAsync = ref.watch(userLibrariesProvider);

    return librariesAsync.when(
      data: (libraries) {
        final ownedLibraries =
            libraries.where((l) => l.role == LibraryRole.owner).toList();
        final sharedLibraries =
            libraries.where((l) => l.role != LibraryRole.owner).toList();

        final ownedCount = ownedLibraries.length;
        final sharedCount = sharedLibraries.length;

        return Column(
          children: [
            _SettingsTile(
              icon: Icons.library_music,
              title: 'My collections',
              subtitle: ownedCount == 0
                  ? 'No collections'
                  : '$ownedCount ${ownedCount == 1 ? 'collection' : 'collections'}',
              colors: colors,
              onTap: () => context.pushNamed(RouteNames.libraryDetails),
            ),
            _SettingsTile(
              icon: Icons.share,
              title: 'Shared with me',
              subtitle: sharedCount == 0
                  ? 'No shared collections'
                  : '$sharedCount ${sharedCount == 1 ? 'collection' : 'collections'}',
              colors: colors,
              onTap: () {
                if (sharedCount == 0) return;
                ref.read(currentLibraryIdProvider.notifier).state =
                    sharedLibraries.first.library.id;
                context.pushNamed(RouteNames.libraryDetails);
              },
            ),
          ],
        );
      },
      loading: () => Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: SaturdaySpace.space2),
            child: SaturdaySkeleton.rect(
              width: double.infinity,
              height: 64,
              radius: 12,
            ),
          ),
          SaturdaySkeleton.rect(
            width: double.infinity,
            height: 64,
            radius: 12,
          ),
        ],
      ),
      error: (error, stack) => _SettingsTile(
        icon: Icons.error_outline,
        title: 'Collections',
        subtitle: "Collections aren't loading.",
        colors: colors,
        onTap: () => ref.invalidate(userLibrariesProvider),
      ),
    );
  }
}

// =============================================================================
// Push token dialog (admin / debug)
// =============================================================================

class _PushTokenDialog extends StatefulWidget {
  const _PushTokenDialog();

  @override
  State<_PushTokenDialog> createState() => _PushTokenDialogState();
}

class _PushTokenDialogState extends State<_PushTokenDialog> {
  bool _refreshing = false;
  bool _justCopied = false;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final token = PushTokenService.instance.currentToken;

    return AlertDialog(
      title: const Text('Push token'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (token == null)
              Text(
                'No token registered yet.',
                style: SaturdayType.body.copyWith(color: colors.ink),
              )
            else
              SelectableText(
                token,
                style: SaturdayType.mono.copyWith(
                  fontSize: 12,
                  color: colors.ink,
                ),
              ),
            const SizedBox(height: SaturdaySpace.space3),
            Text(
              'Compare against push_notification_tokens.token in Supabase. '
              'If they differ, tap refresh to rotate.',
              style: SaturdayType.meta.copyWith(color: colors.inkSecondary),
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
                  if (!mounted) return;
                  setState(() => _justCopied = true);
                  Future.delayed(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _justCopied = false);
                  });
                },
          child: Text(_justCopied ? 'Copied' : 'Copy'),
        ),
        TextButton(
          onPressed: _refreshing
              ? null
              : () async {
                  setState(() => _refreshing = true);
                  await PushTokenService.instance.forceRefresh();
                  if (!mounted) return;
                  setState(() => _refreshing = false);
                },
          child: Text(_refreshing ? 'Refreshing' : 'Refresh'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
