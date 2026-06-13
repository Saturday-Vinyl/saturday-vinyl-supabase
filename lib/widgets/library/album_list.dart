import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/widgets/library/album_card.dart';

/// A list view of albums.
///
/// Displays albums in a vertical list with thumbnail artwork on the left
/// and title, artist, and year on the right.
class AlbumList extends StatelessWidget {
  const AlbumList({
    super.key,
    required this.albums,
    this.onAlbumTap,
    this.onAlbumLongPress,
    this.padding,
  });

  final List<LibraryAlbum> albums;
  final void Function(LibraryAlbum album)? onAlbumTap;
  final void Function(LibraryAlbum album)? onAlbumLongPress;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding ??
          const EdgeInsets.symmetric(vertical: SaturdaySpace.space3),
      itemCount: albums.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: SaturdaySpace.space1),
      itemBuilder: (context, index) {
        final album = albums[index];
        return AlbumListTile(
          libraryAlbum: album,
          onTap: () => onAlbumTap?.call(album),
          onLongPress: onAlbumLongPress != null
              ? () => onAlbumLongPress!(album)
              : null,
        );
      },
    );
  }
}

/// A Sliver version of the album list for use in CustomScrollView.
class SliverAlbumList extends StatelessWidget {
  const SliverAlbumList({
    super.key,
    required this.albums,
    this.onAlbumTap,
    this.onAlbumLongPress,
    this.padding,
  });

  final List<LibraryAlbum> albums;
  final void Function(LibraryAlbum album)? onAlbumTap;
  final void Function(LibraryAlbum album)? onAlbumLongPress;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: padding ??
          const EdgeInsets.symmetric(vertical: SaturdaySpace.space3),
      sliver: SliverList.separated(
        itemCount: albums.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: SaturdaySpace.space1),
        itemBuilder: (context, index) {
          final album = albums[index];
          return AlbumListTile(
            libraryAlbum: album,
            onTap: () => onAlbumTap?.call(album),
            onLongPress: onAlbumLongPress != null
                ? () => onAlbumLongPress!(album)
                : null,
          );
        },
      ),
    );
  }
}
