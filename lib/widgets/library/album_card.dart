import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';

/// A card widget displaying album information.
///
/// Used in both grid and list views to show album art, title, and artist.
/// Supports tapping to navigate to album detail.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.libraryAlbum,
    this.onTap,
    this.showYear = false,
  });

  /// The library album to display.
  final LibraryAlbum libraryAlbum;

  /// Callback when the card is tapped.
  final VoidCallback? onTap;

  /// Whether to show the year below the artist.
  final bool showYear;

  @override
  Widget build(BuildContext context) {
    final album = libraryAlbum.album;
    final title = album?.title ?? 'Unknown Album';
    final artist = album?.artist ?? 'Unknown Artist';
    final year = album?.year;
    final coverUrl = album?.coverImageUrl;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album art
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: AppRadius.largeRadius,
                boxShadow: AppShadows.card,
              ),
              child: ClipRRect(
                borderRadius: AppRadius.largeRadius,
                child: _buildAlbumArt(coverUrl),
              ),
            ),
          ),
          const SizedBox(height: Spacing.sm),

          // Title
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // Artist
          Text(
            artist,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // Year (optional)
          if (showYear && year != null)
            Text(
              year.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
            ),
        ],
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
          size: AppIconSizes.feature,
          color: SaturdayColors.secondary,
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.1),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(
            SaturdayColors.secondary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

/// A list tile variant of the album card for list view display.
///
/// Shows album art as a thumbnail with title, artist, and year on the right.
class AlbumListTile extends StatelessWidget {
  const AlbumListTile({
    super.key,
    required this.libraryAlbum,
    this.onTap,
    this.trailing,
  });

  /// The library album to display.
  final LibraryAlbum libraryAlbum;

  /// Callback when the tile is tapped.
  final VoidCallback? onTap;

  /// Optional trailing widget (e.g., favorite indicator, menu).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final album = libraryAlbum.album;
    final title = album?.title ?? 'Unknown Album';
    final artist = album?.artist ?? 'Unknown Artist';
    final year = album?.year;
    final coverUrl = album?.coverImageUrl;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mediumRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            // Album art thumbnail
            Container(
              width: AlbumArtSizes.small,
              height: AlbumArtSizes.small,
              decoration: BoxDecoration(
                borderRadius: AppRadius.mediumRadius,
                boxShadow: AppShadows.card,
              ),
              child: ClipRRect(
                borderRadius: AppRadius.mediumRadius,
                child: _buildAlbumArt(coverUrl),
              ),
            ),
            const SizedBox(width: Spacing.md),

            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SaturdayColors.secondary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (year != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      year.toString(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondary,
                          ),
                    ),
                  ],
                ],
              ),
            ),

            // Favorite indicator
            if (libraryAlbum.isFavorite) ...[
              const SizedBox(width: Spacing.sm),
              Icon(
                Icons.favorite,
                size: AppIconSizes.md,
                color: SaturdayColors.error,
              ),
            ],

            // Trailing widget
            if (trailing != null) ...[
              const SizedBox(width: Spacing.sm),
              trailing!,
            ],
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
          size: AppIconSizes.lg,
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
