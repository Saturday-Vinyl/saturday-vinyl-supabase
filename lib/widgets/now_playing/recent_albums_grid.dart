import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';

/// A grid of recently played albums for quick selection.
///
/// Tapping an album sets it as now playing.
class RecentAlbumsGrid extends ConsumerWidget {
  const RecentAlbumsGrid({
    super.key,
    this.maxItems = 8,
    this.crossAxisCount = 4,
    this.onAlbumSelected,
  });

  /// Maximum number of albums to display.
  final int maxItems;

  /// Number of columns in the grid.
  final int crossAxisCount;

  /// Optional callback when an album is selected.
  final ValueChanged<LibraryAlbum>? onAlbumSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);

    return recentlyPlayed.when(
      data: (albums) {
        if (albums.isEmpty) {
          return _buildEmptyState(context);
        }
        return _buildGrid(context, ref, albums.take(maxItems).toList());
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(Spacing.xl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => _buildErrorState(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: Spacing.cardPadding,
      decoration: AppDecorations.card,
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.history,
              size: 48,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'No recent albums',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              'Albums you play will appear here',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Container(
      padding: Spacing.cardPadding,
      decoration: AppDecorations.card,
      child: Center(
        child: Text(
          'Failed to load recent albums',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: SaturdayColors.error,
              ),
        ),
      ),
    );
  }

  Widget _buildGrid(
    BuildContext context,
    WidgetRef ref,
    List<LibraryAlbum> albums,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: Spacing.sm,
        mainAxisSpacing: Spacing.sm,
        childAspectRatio: 1,
      ),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        return _RecentAlbumGridTile(
          libraryAlbum: albums[index],
          onTap: () {
            ref.read(nowPlayingProvider.notifier).setNowPlaying(albums[index]);
            onAlbumSelected?.call(albums[index]);
          },
        );
      },
    );
  }
}

/// A single album tile in the recent albums grid.
class _RecentAlbumGridTile extends StatelessWidget {
  const _RecentAlbumGridTile({
    required this.libraryAlbum,
    required this.onTap,
  });

  final LibraryAlbum libraryAlbum;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final album = libraryAlbum.album;
    final coverUrl = album?.coverImageUrl;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: AppRadius.mediumRadius,
          boxShadow: AppShadows.card,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.mediumRadius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Album art
              _buildAlbumArt(coverUrl),

              // Hover overlay with play icon
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: AppRadius.mediumRadius,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            SaturdayColors.primaryDark.withValues(alpha: 0.4),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: SaturdayColors.white.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: SaturdayColors.primaryDark,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumArt(String? coverUrl) {
    if (coverUrl == null || coverUrl.isEmpty) {
      return _buildPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: coverUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => _buildShimmer(),
      errorWidget: (context, url, error) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.album_outlined,
          size: 32,
          color: SaturdayColors.secondary,
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.1),
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
