import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/add_album_provider.dart';

/// Screen for selecting how to add an album to the library.
///
/// Provides options for scanning a barcode, searching Discogs, or
/// (placeholder) taking a photo of the cover.
class AddAlbumScreen extends ConsumerWidget {
  const AddAlbumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Album'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            ref.read(addAlbumProvider.notifier).reset();
            context.pop();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: Spacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Spacing.lg),
              Text(
                'How would you like to add an album?',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.xxl),

              // Scan Barcode option
              _AddMethodCard(
                icon: Icons.qr_code_scanner,
                title: 'Scan Barcode',
                description: 'Use your camera to scan the barcode on the album',
                onTap: () => context.push('/library/add/scan'),
              ),
              const SizedBox(height: Spacing.lg),

              // Search Discogs option
              _AddMethodCard(
                icon: Icons.search,
                title: 'Search Discogs',
                description: 'Search by artist name, album title, or catalog number',
                onTap: () => context.push('/library/add/search'),
              ),
              const SizedBox(height: Spacing.lg),

              // Photo option (coming soon)
              _AddMethodCard(
                icon: Icons.camera_alt_outlined,
                title: 'Photo of Cover',
                description: 'Take a photo of the album cover to identify it',
                isComingSoon: true,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Photo recognition coming soon!'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card representing an add method option.
class _AddMethodCard extends StatelessWidget {
  const _AddMethodCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.isComingSoon = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool isComingSoon;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isComingSoon ? 0.5 : 1.0,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.largeRadius,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                    borderRadius: AppRadius.mediumRadius,
                  ),
                  child: Icon(
                    icon,
                    size: 28,
                    color: SaturdayColors.primaryDark,
                  ),
                ),
                const SizedBox(width: Spacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (isComingSoon) ...[
                            const SizedBox(width: Spacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: SaturdayColors.secondary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Soon',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: SaturdayColors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
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
