import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/repositories/cratelist_repository.dart';

/// A single cell of the unified library grid: either an owned album or a
/// curated cratelist. Used to render albums and cratelists inline in one
/// scrollable view without losing type information.
sealed class CollectionItem {
  const CollectionItem();
}

class CollectionAlbumItem extends CollectionItem {
  final LibraryAlbum libraryAlbum;
  const CollectionAlbumItem(this.libraryAlbum);
}

class CollectionCratelistItem extends CollectionItem {
  final CratelistPreview preview;
  const CollectionCratelistItem(this.preview);
}
