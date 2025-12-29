import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/widgets/now_playing/recent_albums_grid.dart';

/// Screen for manually setting what's now playing.
///
/// Provides multiple input methods:
/// - Choose from library
/// - Scan barcode
/// - Recent albums quick selection
class SetNowPlayingScreen extends ConsumerWidget {
  const SetNowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Now Playing'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: Spacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Input method cards
              _InputMethodCard(
                icon: Icons.library_music_outlined,
                title: 'Choose from Library',
                subtitle: 'Browse your vinyl collection',
                onTap: () {
                  context.go(RoutePaths.library);
                },
              ),
              const SizedBox(height: Spacing.md),

              _InputMethodCard(
                icon: Icons.qr_code_scanner,
                title: 'Scan Barcode',
                subtitle: 'Scan the album\'s barcode',
                onTap: () {
                  _navigateToScanner(context, ref);
                },
              ),
              const SizedBox(height: Spacing.md),

              _InputMethodCard(
                icon: Icons.camera_alt_outlined,
                title: 'Photo of Cover',
                subtitle: 'Coming soon',
                enabled: false,
                onTap: () {},
              ),

              Spacing.sectionGap,

              // Recent albums section
              Text(
                'Quick Selection',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                'Tap to set as now playing',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondary,
                    ),
              ),
              const SizedBox(height: Spacing.md),

              // Recent albums grid
              const RecentAlbumsGrid(
                maxItems: 8,
                crossAxisCount: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToScanner(BuildContext context, WidgetRef ref) {
    // Navigate to barcode scanner with callback for Now Playing
    context.push('/library/add/scan').then((result) {
      if (result != null && context.mounted) {
        // If an album was found/added, it should be set as now playing
        // The barcode scanner flow handles this
        context.go(RoutePaths.nowPlaying);
      }
    });
  }
}

/// A card representing an input method option.
class _InputMethodCard extends StatelessWidget {
  const _InputMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Material(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: AppRadius.largeRadius,
          child: Container(
            padding: Spacing.cardPadding,
            decoration: BoxDecoration(
              borderRadius: AppRadius.largeRadius,
              boxShadow: AppShadows.card,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                    borderRadius: AppRadius.mediumRadius,
                  ),
                  child: Icon(
                    icon,
                    color: SaturdayColors.primaryDark,
                    size: 24,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondary,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: SaturdayColors.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
