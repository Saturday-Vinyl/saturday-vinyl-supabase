import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/library_album.dart';

/// A card widget displaying album information.
///
/// Used in both grid and list views to show album art, title, and artist.
/// Supports tapping to navigate to album detail and long-press for quick
/// actions. The album title renders in serif italic per the Saturday
/// constitution; the artist renders in sans.
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    super.key,
    required this.libraryAlbum,
    this.onTap,
    this.onLongPress,
    this.showYear = false,
  });

  final LibraryAlbum libraryAlbum;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showYear;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final album = libraryAlbum.album;
    final title = album?.title ?? 'Unknown album';
    final artist = album?.artist ?? 'Unknown artist';
    final year = album?.year;
    final coverUrl = album?.coverImageUrl;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _AlbumArt(coverUrl: coverUrl, colors: colors),
            ),
          ),
          const SizedBox(height: SaturdaySpace.space2),
          Text(
            title,
            style: SaturdayType.body.copyWith(
              fontFamily: SaturdayType.fontSerif,
              fontStyle: FontStyle.italic,
              color: colors.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            artist,
            style: SaturdayType.meta.copyWith(color: colors.inkSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (showYear && year != null)
            Text(
              year.toString(),
              style: SaturdayType.meta.copyWith(color: colors.inkTertiary),
            ),
        ],
      ),
    );
  }
}

/// A list tile variant of the album card for list view display.
///
/// Shows album art as a thumbnail with title (serif italic) and artist
/// (sans) on the right. Supports long-press for quick actions.
class AlbumListTile extends StatelessWidget {
  const AlbumListTile({
    super.key,
    required this.libraryAlbum,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final LibraryAlbum libraryAlbum;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final album = libraryAlbum.album;
    final title = album?.title ?? 'Unknown album';
    final artist = album?.artist ?? 'Unknown artist';
    final year = album?.year;
    final coverUrl = album?.coverImageUrl;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SaturdaySpace.space4,
          vertical: SaturdaySpace.space2,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _AlbumArt(coverUrl: coverUrl, colors: colors),
              ),
            ),
            const SizedBox(width: SaturdaySpace.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: SaturdayType.body.copyWith(
                      fontFamily: SaturdayType.fontSerif,
                      fontStyle: FontStyle.italic,
                      color: colors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    style: SaturdayType.body.copyWith(
                      color: colors.inkSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (year != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      year.toString(),
                      style: SaturdayType.meta.copyWith(
                        color: colors.inkTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // The Saturday constitution bans like/favorite/star affordances.
            // Until the favorites model is removed at the data layer, render
            // the marker in ink (not red) and treat it as a visual placeholder.
            if (libraryAlbum.isFavorite) ...[
              const SizedBox(width: SaturdaySpace.space2),
              Icon(Icons.favorite, size: 20, color: colors.ink),
            ],
            if (trailing != null) ...[
              const SizedBox(width: SaturdaySpace.space2),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Cover art surface — image, paper-tone held space, or paper-tone empty.
class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.coverUrl, required this.colors});

  final String? coverUrl;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    if (coverUrl == null || coverUrl!.isEmpty) {
      return _placeholder(colors);
    }
    return CachedNetworkImage(
      imageUrl: coverUrl!,
      fit: BoxFit.cover,
      placeholder: (context, _) => _held(colors),
      errorWidget: (context, _, __) => _placeholder(colors),
    );
  }

  static Widget _placeholder(SaturdayColorTokens colors) {
    return Container(
      color: colors.paperElevated,
      child: Center(
        child: Icon(Icons.album_outlined, size: 32, color: colors.inkTertiary),
      ),
    );
  }

  static Widget _held(SaturdayColorTokens colors) {
    // Held space while the cover loads — static, no shimmer per the
    // constitution.
    return Container(color: colors.paperElevated);
  }
}
