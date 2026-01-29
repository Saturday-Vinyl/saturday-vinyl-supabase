import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/notification_preferences_provider.dart';
import 'package:saturday_consumer_app/providers/notification_provider.dart';

/// Screen for managing notification preferences.
///
/// Settings are synced to the server so that Edge Functions can check them
/// before sending push notifications.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationState = ref.watch(notificationProvider);
    final prefsState = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: prefsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: Spacing.pagePadding,
              children: [
                // Permission status
                _buildPermissionSection(context, ref, notificationState),
                Spacing.sectionGap,

                // Now Playing notifications
                _buildSectionHeader(context, 'Now Playing'),
                Spacing.itemGap,
                _buildNotificationToggle(
                  context,
                  ref,
                  icon: Icons.album,
                  title: 'Now Playing alerts',
                  subtitle:
                      'Get notified when a record is placed on your Saturday Hub',
                  value: prefsState.nowPlayingEnabled,
                  enabled: notificationState.hasPermission,
                  onChanged: (value) => ref
                      .read(notificationPreferencesProvider.notifier)
                      .setNowPlayingEnabled(value),
                ),
                _buildNotificationToggle(
                  context,
                  ref,
                  icon: Icons.replay,
                  title: 'Flip reminders',
                  subtitle:
                      'Get reminded when it\'s time to flip to the next side',
                  value: prefsState.flipRemindersEnabled,
                  enabled: notificationState.hasPermission,
                  onChanged: (value) => ref
                      .read(notificationPreferencesProvider.notifier)
                      .setFlipRemindersEnabled(value),
                ),

                Spacing.sectionGap,

                // Device notifications
                _buildSectionHeader(context, 'Devices'),
                Spacing.itemGap,
                _buildNotificationToggle(
                  context,
                  ref,
                  icon: Icons.wifi_off,
                  title: 'Device offline alerts',
                  subtitle:
                      'Get notified when a device loses connection for more than 10 minutes',
                  value: prefsState.deviceOfflineEnabled,
                  enabled: notificationState.hasPermission,
                  onChanged: (value) => ref
                      .read(notificationPreferencesProvider.notifier)
                      .setDeviceOfflineEnabled(value),
                ),
                _buildNotificationToggle(
                  context,
                  ref,
                  icon: Icons.wifi,
                  title: 'Device online alerts',
                  subtitle:
                      'Get notified when a device reconnects after being offline',
                  value: prefsState.deviceOnlineEnabled,
                  enabled: notificationState.hasPermission,
                  onChanged: (value) => ref
                      .read(notificationPreferencesProvider.notifier)
                      .setDeviceOnlineEnabled(value),
                ),
                _buildNotificationToggle(
                  context,
                  ref,
                  icon: Icons.battery_alert,
                  title: 'Low battery alerts',
                  subtitle:
                      'Get notified when a device\'s battery drops below 20%',
                  value: prefsState.batteryLowEnabled,
                  enabled: notificationState.hasPermission,
                  onChanged: (value) => ref
                      .read(notificationPreferencesProvider.notifier)
                      .setBatteryLowEnabled(value),
                ),

                // Error message if sync failed
                if (prefsState.error != null) ...[
                  Spacing.sectionGap,
                  Container(
                    padding: Spacing.cardPadding,
                    decoration: BoxDecoration(
                      color: SaturdayColors.error.withValues(alpha: 0.1),
                      borderRadius: AppRadius.mediumRadius,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: SaturdayColors.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Settings may not be saved. Please try again.',
                            style: TextStyle(color: SaturdayColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Spacer at bottom
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildPermissionSection(
    BuildContext context,
    WidgetRef ref,
    NotificationState notificationState,
  ) {
    final hasPermission = notificationState.hasPermission;

    return Container(
      padding: Spacing.cardPadding,
      decoration: BoxDecoration(
        color: hasPermission
            ? SaturdayColors.success.withValues(alpha: 0.1)
            : SaturdayColors.warning.withValues(alpha: 0.1),
        borderRadius: AppRadius.largeRadius,
      ),
      child: Row(
        children: [
          Icon(
            hasPermission
                ? Icons.notifications_active
                : Icons.notifications_off,
            color: hasPermission ? SaturdayColors.success : SaturdayColors.warning,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasPermission
                      ? 'Notifications enabled'
                      : 'Notifications disabled',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  hasPermission
                      ? 'You can customize which notifications you receive below.'
                      : 'Enable notifications to receive alerts about your devices and records.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondary,
                      ),
                ),
              ],
            ),
          ),
          if (!hasPermission)
            TextButton(
              onPressed: () async {
                await ref
                    .read(notificationProvider.notifier)
                    .requestPermissions();
              },
              child: const Text('Enable'),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: SaturdayColors.secondary,
            ),
      ),
    );
  }

  Widget _buildNotificationToggle(
    BuildContext context,
    WidgetRef ref, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AppDecorations.card,
      child: ListTile(
        leading: Icon(
          icon,
          color: enabled ? SaturdayColors.primaryDark : SaturdayColors.secondary,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: enabled ? null : SaturdayColors.secondary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: SaturdayColors.secondary,
            fontSize: 12,
          ),
        ),
        trailing: Switch.adaptive(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeTrackColor: SaturdayColors.success,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
