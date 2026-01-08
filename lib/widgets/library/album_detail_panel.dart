import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
import 'package:saturday_consumer_app/widgets/library/track_list.dart';

/// A condensed album detail panel for tablet dual-pane layouts.
///
/// Shows album info in a panel format with close button, designed
/// to display alongside the library grid.
class AlbumDetailPanel extends ConsumerWidget {
  const AlbumDetailPanel({
    super.key,
    required this.libraryAlbumId,
    required this.onClose,
    this.onSetAsNowPlaying,
    this.onAssociateTag,
  });

  /// The library album ID to display.
  final String libraryAlbumId;

  /// Callback when the panel should close.
  final VoidCallback onClose;

  /// Callback when "Set as Now Playing" is tapped.
  final VoidCallback? onSetAsNowPlaying;

  /// Callback when "Associate Tag" is tapped.
  final VoidCallback? onAssociateTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumAsync = ref.watch(libraryAlbumByIdProvider(libraryAlbumId));

    return Column(
      children: [
        // Header with close button
        _buildHeader(context),
        const Divider(height: 1),

        // Content
        Expanded(
          child: albumAsync.when(
            data: (album) => album != null
                ? _buildContent(context, ref, album)
                : const ErrorDisplay.fullScreen(
                    message: 'Album not found',
                  ),
            loading: () => const LoadingIndicator.medium(),
            error: (error, _) => ErrorDisplay.fullScreen(
              message: error.toString(),
              onRetry: () => ref.invalidate(libraryAlbumByIdProvider(libraryAlbumId)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      height: kToolbarHeight,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: onClose,
          ),
          Text(
            'Album Details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    LibraryAlbum libraryAlbum,
  ) {
    final album = libraryAlbum.album;
    if (album == null) {
      return const ErrorDisplay.fullScreen(
        message: 'Album data not available',
      );
    }

    return SingleChildScrollView(
      padding: Spacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album art and info row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Album art
              ClipRRect(
                borderRadius: AppRadius.mediumRadius,
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: album.coverImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: album.coverImageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => _buildArtPlaceholder(),
                          errorWidget: (_, __, ___) => _buildArtPlaceholder(),
                        )
                      : _buildArtPlaceholder(),
                ),
              ),
              const SizedBox(width: Spacing.lg),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      album.artist,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: SaturdayColors.secondary,
                          ),
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      [
                        if (album.year != null) album.year.toString(),
                        if (album.label != null) album.label,
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: Spacing.xl),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ref.read(nowPlayingProvider.notifier).setNowPlaying(libraryAlbum);
                    onSetAsNowPlaying?.call();
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(width: Spacing.md),
              OutlinedButton.icon(
                onPressed: onAssociateTag,
                icon: const Icon(Icons.qr_code),
                label: const Text('Tag'),
              ),
            ],
          ),

          const SizedBox(height: Spacing.xl),

          // Genres
          if (album.genres.isNotEmpty) ...[
            Text(
              'Genres',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: album.genres
                  .map((genre) => Chip(
                        label: Text(genre),
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
            const SizedBox(height: Spacing.xl),
          ],

          // Tracks
          if (album.tracks.isNotEmpty) ...[
            Text(
              'Tracks',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Spacing.sm),
            CompactTrackList(
              tracks: album.tracks,
              maxTracks: 10,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArtPlaceholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.album_outlined,
          size: 48,
          color: SaturdayColors.secondary,
        ),
      ),
    );
  }
}
