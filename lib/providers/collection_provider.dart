import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/collection_item.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/cratelist_provider.dart';
import 'package:saturday_consumer_app/providers/library_filter_provider.dart';

/// Type-narrowing filter for the unified library grid.
enum CollectionTypeFilter { all, albums, cratelists }

/// Selected type chip on the library screen. Resets to [all] each session
/// (intentionally not persisted, per design).
final collectionTypeFilterProvider =
    StateProvider<CollectionTypeFilter>((ref) => CollectionTypeFilter.all);

/// The unified, ordered list of items to render in the library grid:
/// cratelists pinned at the top (when shown) followed by albums (in the
/// user's current sort order).
///
/// Cratelists are hidden when the user has an album-only filter active
/// (genre, decade, favorites) and the type chip is [CollectionTypeFilter.all],
/// matching the user's narrowing intent. They are always shown when
/// [CollectionTypeFilter.cratelists] is selected, regardless of those
/// album-specific filters.
final collectionItemsProvider =
    FutureProvider<List<CollectionItem>>((ref) async {
  final type = ref.watch(collectionTypeFilterProvider);
  final hasAlbumFilters = ref.watch(hasActiveFiltersProvider);

  final showAlbums = type != CollectionTypeFilter.cratelists;
  final showCratelists = switch (type) {
    CollectionTypeFilter.albums => false,
    CollectionTypeFilter.cratelists => true,
    CollectionTypeFilter.all => !hasAlbumFilters,
  };

  final items = <CollectionItem>[];

  if (showCratelists) {
    final cratelists = await ref.watch(cratelistPreviewsProvider.future);
    items.addAll(cratelists.map(CollectionCratelistItem.new));
  }

  if (showAlbums) {
    final albums = await ref.watch(libraryAlbumsProvider.future);
    items.addAll(albums.map(CollectionAlbumItem.new));
  }

  return items;
});
