import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/services/discogs_service.dart';

/// A search result item for library albums.
class LibrarySearchResultItem extends StatelessWidget {
  const LibrarySearchResultItem({
    super.key,
    required this.libraryAlbum,
    required this.onTap,
  });

  final LibraryAlbum libraryAlbum;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final album = libraryAlbum.album;
    final title = album?.title ?? 'Unknown Album';
    final artist = album?.artist ?? 'Unknown Artist';
    final year = album?.year?.toString() ?? '';
    final coverUrl = album?.coverImageUrl;

    return ListTile(
      onTap: onTap,
      leading: _AlbumArtThumbnail(coverUrl: coverUrl),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        artist + (year.isNotEmpty ? ' ($year)' : ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: SaturdayColors.secondary),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: SaturdayColors.success.withValues(alpha: 0.15),
          borderRadius: AppRadius.smallRadius,
        ),
        child: Text(
          'In Library',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: SaturdayColors.success,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// A search result item for Discogs results.
class DiscogsSearchResultItem extends StatelessWidget {
  const DiscogsSearchResultItem({
    super.key,
    required this.result,
    required this.onTap,
    required this.onAdd,
    this.isAdding = false,
  });

  final DiscogsSearchResult result;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final bool isAdding;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: _AlbumArtThumbnail(coverUrl: result.coverImageUrl),
      title: Text(
        result.albumTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.artist + (result.year != null ? ' (${result.year})' : ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: SaturdayColors.secondary),
          ),
          if (result.labels.isNotEmpty || result.catno != null)
            Text(
              [
                if (result.labels.isNotEmpty) result.labels.first,
                if (result.catno != null) result.catno,
              ].join(' - '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondary.withValues(alpha: 0.7),
                  ),
            ),
        ],
      ),
      isThreeLine: result.labels.isNotEmpty || result.catno != null,
      trailing: isAdding
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.add_circle_outline),
              color: SaturdayColors.primaryDark,
              tooltip: 'Add to Library',
              onPressed: onAdd,
            ),
    );
  }
}

/// Album art thumbnail for search results.
class _AlbumArtThumbnail extends StatelessWidget {
  const _AlbumArtThumbnail({this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: AppRadius.smallRadius,
        color: SaturdayColors.secondary.withValues(alpha: 0.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: coverUrl != null && coverUrl!.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: coverUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => _buildPlaceholder(),
              errorWidget: (_, __, ___) => _buildPlaceholder(),
            )
          : _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Icon(
        Icons.album_outlined,
        size: 24,
        color: SaturdayColors.secondary,
      ),
    );
  }
}
