import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/widgets/library/album_card.dart';

/// A responsive grid view of albums.
///
/// Displays albums in a grid with 2 columns on phones and 3-4 on tablets.
/// Album art is displayed prominently with title and artist below.
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({
    super.key,
    required this.albums,
    this.onAlbumTap,
    this.padding,
  });

  /// The list of library albums to display.
  final List<LibraryAlbum> albums;

  /// Callback when an album is tapped.
  final void Function(LibraryAlbum album)? onAlbumTap;

  /// Optional padding around the grid.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Determine number of columns based on screen width
        final crossAxisCount = _calculateCrossAxisCount(constraints.maxWidth);

        return GridView.builder(
          padding: padding ?? Spacing.pagePadding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: Spacing.lg,
            crossAxisSpacing: Spacing.lg,
            // Aspect ratio accounts for text below the square album art
            // Album art is 1:1, plus ~60px for text
            childAspectRatio: _calculateChildAspectRatio(constraints.maxWidth, crossAxisCount),
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return AlbumCard(
              libraryAlbum: album,
              onTap: () => onAlbumTap?.call(album),
            );
          },
        );
      },
    );
  }

  /// Calculate the number of columns based on available width.
  int _calculateCrossAxisCount(double width) {
    if (width < 400) {
      return 2; // Phone portrait
    } else if (width < 600) {
      return 3; // Phone landscape / small tablet
    } else if (width < 900) {
      return 4; // Tablet portrait
    } else {
      return 5; // Tablet landscape / large screen
    }
  }

  /// Calculate child aspect ratio based on width and column count.
  ///
  /// We need to account for the text below the album art.
  /// Album art is square (1:1), plus about 60px for 2-3 lines of text.
  double _calculateChildAspectRatio(double width, int crossAxisCount) {
    final spacing = Spacing.lg * (crossAxisCount + 1); // Including outer padding
    final availableWidth = width - spacing;
    final itemWidth = availableWidth / crossAxisCount;
    // Item height = square album art + text area
    final textHeight = 60.0;
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
    this.padding,
  });

  /// The list of library albums to display.
  final List<LibraryAlbum> albums;

  /// Callback when an album is tapped.
  final void Function(LibraryAlbum album)? onAlbumTap;

  /// Optional padding around the grid.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _calculateCrossAxisCount(constraints.crossAxisExtent);

        return SliverPadding(
          padding: padding ?? Spacing.pagePadding,
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: Spacing.lg,
              crossAxisSpacing: Spacing.lg,
              childAspectRatio: _calculateChildAspectRatio(
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
                );
              },
              childCount: albums.length,
            ),
          ),
        );
      },
    );
  }

  int _calculateCrossAxisCount(double width) {
    if (width < 400) {
      return 2;
    } else if (width < 600) {
      return 3;
    } else if (width < 900) {
      return 4;
    } else {
      return 5;
    }
  }

  double _calculateChildAspectRatio(double width, int crossAxisCount) {
    final spacing = Spacing.lg * (crossAxisCount + 1);
    final availableWidth = width - spacing;
    final itemWidth = availableWidth / crossAxisCount;
    const textHeight = 60.0;
    final itemHeight = itemWidth + textHeight;
    return itemWidth / itemHeight;
  }
}
