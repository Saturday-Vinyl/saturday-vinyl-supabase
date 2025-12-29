import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/recommendations_provider.dart';

/// A horizontal carousel showing recommended albums for "Up Next".
///
/// Shows albums based on the currently playing album's genre/style,
/// supplemented by recently played albums.
class UpNextCarousel extends ConsumerWidget {
  const UpNextCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upNext = ref.watch(upNextProvider);

    return upNext.when(
      data: (albums) {
        if (albums.isEmpty) {
          return const SizedBox.shrink();
        }
        return _UpNextContent(albums: albums);
      },
      loading: () => const _UpNextLoading(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _UpNextContent extends StatelessWidget {
  const _UpNextContent({required this.albums});

  final List<LibraryAlbum> albums;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.lg,
              Spacing.lg,
              Spacing.md,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Up Next',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  '${albums.length} suggestions',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondary,
                      ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              itemCount: albums.length,
              itemBuilder: (context, index) {
                return _UpNextTile(
                  libraryAlbum: albums[index],
                  isFirst: index == 0,
                  isLast: index == albums.length - 1,
                );
              },
            ),
          ),
          const SizedBox(height: Spacing.md),
        ],
      ),
    );
  }
}

class _UpNextLoading extends StatelessWidget {
  const _UpNextLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: AppDecorations.card,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

/// A single album tile in the Up Next carousel.
class _UpNextTile extends ConsumerWidget {
  const _UpNextTile({
    required this.libraryAlbum,
    this.isFirst = false,
    this.isLast = false,
  });

  final LibraryAlbum libraryAlbum;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = libraryAlbum.album;
    final title = album?.title ?? 'Unknown';
    final artist = album?.artist ?? 'Unknown';
    final coverUrl = album?.coverImageUrl;

    return GestureDetector(
      onTap: () {
        // Navigate to album detail
        context.push('/library/album/${libraryAlbum.id}');
      },
      onLongPress: () {
        // Quick action to set as now playing
        _showQuickActions(context, ref);
      },
      child: Container(
        width: 100,
        margin: EdgeInsets.only(
          right: isLast ? 0 : Spacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album art with play overlay
            Stack(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.mediumRadius,
                    boxShadow: AppShadows.card,
                  ),
                  child: ClipRRect(
                    borderRadius: AppRadius.mediumRadius,
                    child: _buildAlbumArt(coverUrl),
                  ),
                ),
                // Play button overlay
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: AppRadius.mediumRadius,
                      onTap: () {
                        ref
                            .read(nowPlayingProvider.notifier)
                            .setNowPlaying(libraryAlbum);
                      },
                      child: Center(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: SaturdayColors.primaryDark.withValues(alpha: 0.8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            color: SaturdayColors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            // Title
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // Artist
            Text(
              artist,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondary,
                    fontSize: 11,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
          size: 40,
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

  void _showQuickActions(BuildContext context, WidgetRef ref) {
    final album = libraryAlbum.album;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: const Text('Play Now'),
              subtitle: Text(album?.title ?? 'Unknown'),
              onTap: () {
                Navigator.pop(context);
                ref
                    .read(nowPlayingProvider.notifier)
                    .setNowPlaying(libraryAlbum);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(context);
                context.push('/library/album/${libraryAlbum.id}');
              },
            ),
          ],
        ),
      ),
    );
  }
}
