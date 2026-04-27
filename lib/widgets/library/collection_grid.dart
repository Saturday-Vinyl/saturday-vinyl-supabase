import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/models/collection_item.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/repositories/cratelist_repository.dart';
import 'package:saturday_consumer_app/widgets/library/album_card.dart';
import 'package:saturday_consumer_app/widgets/library/cratelist_tile.dart';

/// Unified grid that renders [CollectionItem]s — a mix of album and
/// cratelist tiles in one scroll view. Cratelist tiles include a small
/// type-indicator badge so users can distinguish them from album tiles.
class CollectionGrid extends StatelessWidget {
  const CollectionGrid({
    super.key,
    required this.items,
    this.onAlbumTap,
    this.onAlbumLongPress,
    this.onCratelistTap,
    this.padding,
  });

  final List<CollectionItem> items;
  final void Function(LibraryAlbum album)? onAlbumTap;
  final void Function(LibraryAlbum album)? onAlbumLongPress;
  final void Function(CratelistPreview preview)? onCratelistTap;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _crossAxisCount(constraints.maxWidth);

        return GridView.builder(
          padding: padding ?? Spacing.pagePadding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: Spacing.lg,
            crossAxisSpacing: Spacing.lg,
            childAspectRatio: _childAspectRatio(
              constraints.maxWidth,
              crossAxisCount,
            ),
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return switch (item) {
              CollectionAlbumItem(:final libraryAlbum) => AlbumCard(
                  libraryAlbum: libraryAlbum,
                  onTap: () => onAlbumTap?.call(libraryAlbum),
                  onLongPress: () => onAlbumLongPress?.call(libraryAlbum),
                ),
              CollectionCratelistItem(:final preview) => CratelistTile(
                  preview: preview,
                  showTypeIndicator: true,
                  onTap: () => onCratelistTap?.call(preview),
                ),
            };
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
    final spacing = Spacing.lg * (crossAxisCount + 1);
    final availableWidth = width - spacing;
    final itemWidth = availableWidth / crossAxisCount;
    const textHeight = 60.0;
    final itemHeight = itemWidth + textHeight;
    return itemWidth / itemHeight;
  }
}

/// Sliver variant of [CollectionGrid] for use inside a [CustomScrollView].
class SliverCollectionGrid extends StatelessWidget {
  const SliverCollectionGrid({
    super.key,
    required this.items,
    this.onAlbumTap,
    this.onAlbumLongPress,
    this.onCratelistTap,
    this.padding,
  });

  final List<CollectionItem> items;
  final void Function(LibraryAlbum album)? onAlbumTap;
  final void Function(LibraryAlbum album)? onAlbumLongPress;
  final void Function(CratelistPreview preview)? onCratelistTap;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _crossAxisCount(constraints.crossAxisExtent);

        return SliverPadding(
          padding: padding ?? Spacing.pagePadding,
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: Spacing.lg,
              crossAxisSpacing: Spacing.lg,
              childAspectRatio: _childAspectRatio(
                constraints.crossAxisExtent,
                crossAxisCount,
              ),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                return switch (item) {
                  CollectionAlbumItem(:final libraryAlbum) => AlbumCard(
                      libraryAlbum: libraryAlbum,
                      onTap: () => onAlbumTap?.call(libraryAlbum),
                      onLongPress: () => onAlbumLongPress?.call(libraryAlbum),
                    ),
                  CollectionCratelistItem(:final preview) => CratelistTile(
                      preview: preview,
                      showTypeIndicator: true,
                      onTap: () => onCratelistTap?.call(preview),
                    ),
                };
              },
              childCount: items.length,
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
    final spacing = Spacing.lg * (crossAxisCount + 1);
    final availableWidth = width - spacing;
    final itemWidth = availableWidth / crossAxisCount;
    const textHeight = 60.0;
    final itemHeight = itemWidth + textHeight;
    return itemWidth / itemHeight;
  }
}
