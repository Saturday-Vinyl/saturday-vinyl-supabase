import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/album.dart';

/// A hero-sized album art display for the Now Playing screen.
///
/// Displays the album artwork prominently with rounded corners
/// and optional shadow. Falls back to a placeholder when no
/// image is available.
class AlbumArtHero extends StatelessWidget {
  const AlbumArtHero({
    super.key,
    required this.album,
    this.onTap,
  });

  /// The album to display artwork for.
  final Album? album;

  /// Callback when the artwork is tapped (for full-screen view).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final coverUrl = album?.coverImageUrl;

    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.largeRadius,
            boxShadow: AppShadows.elevated,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.largeRadius,
            child: _buildAlbumArt(coverUrl),
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
          size: 80,
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
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation(
            SaturdayColors.secondary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
