import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/widgets/library/album_card.dart';

/// A responsive grid view of albums.
///
/// Displays albums in a grid with 2 columns on phones and 3-4 on tablets.
/// Album art is displayed prominently with title and artist below.
/// Supports long-press for quick actions.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _crossAxisCount(constraints.maxWidth);

        return GridView.builder(
          padding: padding ?? const EdgeInsets.all(SaturdaySpace.space4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: SaturdaySpace.space4,
            crossAxisSpacing: SaturdaySpace.space4,
            childAspectRatio: _childAspectRatio(
              constraints.maxWidth,
              crossAxisCount,
            ),
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return AlbumCard(
              libraryAlbum: album,
              onTap: () => onAlbumTap?.call(album),
              onLongPress: () => onAlbumLongPress?.call(album),
            );
          },
        );
      },
    );
  }

  int _crossAxisCount(double width) {
    if (width < 400) return 2;
    if (width < 600) return 3;
    if (width < 900) return 4;
    return 5;
  }

  double _childAspectRatio(double width, int crossAxisCount) {
    final spacing = SaturdaySpace.space4 * (crossAxisCount + 1);
    final availableWidth = width - spacing;
    final itemWidth = availableWidth / crossAxisCount;
    const textHeight = 60.0;
    final itemHeight = itemWidth + textHeight;
    return itemWidth / itemHeight;
  }
}

/// A Sliver version of the album grid for use in CustomScrollView.
class SliverAlbumGrid extends StatelessWidget {
  const SliverAlbumGrid({
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
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _crossAxisCount(constraints.crossAxisExtent);

        return SliverPadding(
          padding: padding ?? const EdgeInsets.all(SaturdaySpace.space4),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: SaturdaySpace.space4,
              crossAxisSpacing: SaturdaySpace.space4,
              childAspectRatio: _childAspectRatio(
                constraints.crossAxisExtent,
                crossAxisCount,
              ),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final album = albums[index];
                return AlbumCard(
                  libraryAlbum: album,
                  onTap: () => onAlbumTap?.call(album),
                  onLongPress: () => onAlbumLongPress?.call(album),
                );
              },
              childCount: albums.length,
            ),
          ),
        );
      },
    );
  }

  int _crossAxisCount(double width) {
    if (width < 400) return 2;
    if (width < 600) return 3;
    if (width < 900) return 4;
    return 5;
  }

  double _childAspectRatio(double width, int crossAxisCount) {
    final spacing = SaturdaySpace.space4 * (crossAxisCount + 1);
    final availableWidth = width - spacing;
    final itemWidth = availableWidth / crossAxisCount;
    const textHeight = 60.0;
    final itemHeight = itemWidth + textHeight;
    return itemWidth / itemHeight;
  }
}
