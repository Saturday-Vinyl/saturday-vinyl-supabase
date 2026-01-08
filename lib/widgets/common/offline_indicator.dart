import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/connectivity_provider.dart';

/// A banner that displays when the app is offline.
///
/// Shows a small banner at the top or bottom of the screen to inform
/// the user they are viewing cached data.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({
    super.key,
    this.position = OfflineBannerPosition.bottom,
  });

  /// Where to position the banner.
  final OfflineBannerPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);

    if (!isOffline) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      color: SaturdayColors.warning.withValues(alpha: 0.9),
      child: SafeArea(
        top: position == OfflineBannerPosition.top,
        bottom: position == OfflineBannerPosition.bottom,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              'You\'re offline - viewing cached data',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Position for the offline banner.
enum OfflineBannerPosition {
  top,
  bottom,
}

/// A widget that wraps content and shows an offline banner when needed.
class OfflineAwareScaffold extends ConsumerWidget {
  const OfflineAwareScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.showOfflineBanner = true,
    this.bannerPosition = OfflineBannerPosition.bottom,
  });

  /// The main body of the scaffold.
  final Widget body;

  /// Optional app bar.
  final PreferredSizeWidget? appBar;

  /// Optional floating action button.
  final Widget? floatingActionButton;

  /// Optional bottom navigation bar.
  final Widget? bottomNavigationBar;

  /// Whether to show the offline banner.
  final bool showOfflineBanner;

  /// Where to position the offline banner.
  final OfflineBannerPosition bannerPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);

    return Scaffold(
      appBar: appBar,
      body: Column(
        children: [
          // Top banner position
          if (showOfflineBanner &&
              isOffline &&
              bannerPosition == OfflineBannerPosition.top)
            const OfflineBanner(position: OfflineBannerPosition.top),

          // Main content
          Expanded(child: body),

          // Bottom banner position (above bottom nav)
          if (showOfflineBanner &&
              isOffline &&
              bannerPosition == OfflineBannerPosition.bottom &&
              bottomNavigationBar == null)
            const OfflineBanner(position: OfflineBannerPosition.bottom),
        ],
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showOfflineBanner &&
                    isOffline &&
                    bannerPosition == OfflineBannerPosition.bottom)
                  const OfflineBanner(position: OfflineBannerPosition.bottom),
                bottomNavigationBar!,
              ],
            )
          : null,
    );
  }
}

/// A small offline indicator icon.
///
/// Shows a cloud-off icon when offline, useful for app bars.
class OfflineIndicatorIcon extends ConsumerWidget {
  const OfflineIndicatorIcon({
    super.key,
    this.size = 20,
    this.color,
  });

  /// Icon size.
  final double size;

  /// Icon color (defaults to warning color).
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);

    if (!isOffline) {
      return const SizedBox.shrink();
    }

    return Tooltip(
      message: 'You\'re offline',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        child: Icon(
          Icons.cloud_off,
          size: size,
          color: color ?? SaturdayColors.warning,
        ),
      ),
    );
  }
}

/// A widget that disables its child when offline.
///
/// Use this to wrap buttons or other interactive elements that
/// require network connectivity.
class OfflineDisabled extends ConsumerWidget {
  const OfflineDisabled({
    super.key,
    required this.child,
    this.offlineMessage = 'This action requires an internet connection',
    this.showTooltip = true,
  });

  /// The widget to disable when offline.
  final Widget child;

  /// Message to show when attempting to use while offline.
  final String offlineMessage;

  /// Whether to show a tooltip when disabled.
  final bool showTooltip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOffline = ref.watch(isOfflineProvider);

    if (!isOffline) {
      return child;
    }

    // Wrap in a tooltip and disable interaction.
    final disabled = IgnorePointer(
      ignoring: true,
      child: Opacity(
        opacity: 0.5,
        child: child,
      ),
    );

    if (showTooltip) {
      return Tooltip(
        message: offlineMessage,
        child: disabled,
      );
    }

    return disabled;
  }
}

/// Shows a "Last updated" timestamp when viewing cached data.
class CacheTimestamp extends StatelessWidget {
  const CacheTimestamp({
    super.key,
    required this.timestamp,
    this.prefix = 'Last updated',
  });

  /// The timestamp to display.
  final DateTime timestamp;

  /// Text to show before the time.
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    String timeAgo;
    if (difference.inMinutes < 1) {
      timeAgo = 'just now';
    } else if (difference.inMinutes < 60) {
      timeAgo = '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      timeAgo = '${difference.inHours}h ago';
    } else {
      timeAgo = '${difference.inDays}d ago';
    }

    return Text(
      '$prefix $timeAgo',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: SaturdayColors.secondary,
            fontStyle: FontStyle.italic,
          ),
    );
  }
}
