import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/collection_item.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/repositories/cratelist_repository.dart';
import 'package:saturday_consumer_app/widgets/library/album_card.dart';
import 'package:saturday_consumer_app/widgets/library/cratelist_cover.dart';

/// Unified list that renders [CollectionItem]s vertically. Album rows reuse
/// [AlbumListTile]; cratelist rows render a thumbnail composite with name
/// and item count.
class CollectionList extends StatelessWidget {
  const CollectionList({
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
    return ListView.separated(
      padding: padding ??
          const EdgeInsets.symmetric(vertical: SaturdaySpace.space3),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: SaturdaySpace.space1),
      itemBuilder: (context, index) {
        final item = items[index];
        return switch (item) {
          CollectionAlbumItem(:final libraryAlbum) => AlbumListTile(
              libraryAlbum: libraryAlbum,
              onTap: () => onAlbumTap?.call(libraryAlbum),
              onLongPress: () => onAlbumLongPress?.call(libraryAlbum),
            ),
          CollectionCratelistItem(:final preview) => _CratelistListTile(
              preview: preview,
              onTap: () => onCratelistTap?.call(preview),
            ),
        };
      },
    );
  }
}

/// Sliver variant of [CollectionList] for use inside a [CustomScrollView].
class SliverCollectionList extends StatelessWidget {
  const SliverCollectionList({
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
    return SliverPadding(
      padding: padding ??
          const EdgeInsets.symmetric(vertical: SaturdaySpace.space3),
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const SizedBox(height: SaturdaySpace.space1),
        itemBuilder: (context, index) {
          final item = items[index];
          return switch (item) {
            CollectionAlbumItem(:final libraryAlbum) => AlbumListTile(
                libraryAlbum: libraryAlbum,
                onTap: () => onAlbumTap?.call(libraryAlbum),
                onLongPress: () => onAlbumLongPress?.call(libraryAlbum),
              ),
            CollectionCratelistItem(:final preview) => _CratelistListTile(
                preview: preview,
                onTap: () => onCratelistTap?.call(preview),
              ),
          };
        },
      ),
    );
  }
}

class _CratelistListTile extends StatelessWidget {
  const _CratelistListTile({required this.preview, this.onTap});

  final CratelistPreview preview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final cratelist = preview.cratelist;

    return InkWell(
      onTap: onTap,
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
              child: Stack(
                children: [
                  CratelistCover(
                    coverUrls: preview.coverUrls,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: colors.ink.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.library_music,
                        size: 11,
                        color: colors.paper,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: SaturdaySpace.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    cratelist.name,
                    style: SaturdayType.body.copyWith(
                      fontWeight: SaturdayType.medium,
                      color: colors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _countLabel(preview.itemCount),
                    style: SaturdayType.meta.copyWith(
                      color: colors.inkSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _countLabel(int count) {
    if (count == 0) return 'Empty cratelist';
    if (count == 1) return 'Cratelist · 1 album';
    return 'Cratelist · $count albums';
  }
}
