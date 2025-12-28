import 'package:saturday_consumer_app/models/album.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Sort options for library albums.
enum AlbumSortOption {
  artistAsc,
  artistDesc,
  titleAsc,
  titleDesc,
  dateAddedAsc,
  dateAddedDesc,
  yearAsc,
  yearDesc,
}

/// Filter options for library albums.
class AlbumFilters {
  final List<String>? genres;
  final int? yearFrom;
  final int? yearTo;
  final bool? isFavorite;

  const AlbumFilters({
    this.genres,
    this.yearFrom,
    this.yearTo,
    this.isFavorite,
  });
}

/// Repository for album-related database operations.
class AlbumRepository extends BaseRepository {
  static const _albumsTable = 'albums';
  static const _libraryAlbumsTable = 'library_albums';

  /// Gets a canonical album by ID.
  Future<Album?> getAlbum(String albumId) async {
    final response = await client
        .from(_albumsTable)
        .select()
        .eq('id', albumId)
        .maybeSingle();

    if (response == null) return null;
    return Album.fromJson(response);
  }

  /// Gets a canonical album by Discogs ID.
  Future<Album?> getAlbumByDiscogsId(int discogsId) async {
    final response = await client
        .from(_albumsTable)
        .select()
        .eq('discogs_id', discogsId)
        .maybeSingle();

    if (response == null) return null;
    return Album.fromJson(response);
  }

  /// Creates a new canonical album record.
  Future<Album> createAlbum(Album album) async {
    final response = await client
        .from(_albumsTable)
        .insert(album.toJson()..remove('id'))
        .select()
        .single();

    return Album.fromJson(response);
  }

  /// Searches canonical albums by title or artist.
  Future<List<Album>> searchAlbums(String query, {int limit = 20}) async {
    final response = await client
        .from(_albumsTable)
        .select()
        .or('title.ilike.%$query%,artist.ilike.%$query%')
        .limit(limit);

    return (response as List).map((row) => Album.fromJson(row)).toList();
  }

  /// Gets all albums in a library with optional filtering and sorting.
  Future<List<LibraryAlbum>> getLibraryAlbums(
    String libraryId, {
    AlbumFilters? filters,
    AlbumSortOption sort = AlbumSortOption.artistAsc,
    int? limit,
    int? offset,
  }) async {
    // Build the base query with filters
    var filterQuery = client
        .from(_libraryAlbumsTable)
        .select('*, album:albums(*)') // Join with albums table
        .eq('library_id', libraryId);

    // Apply filters
    if (filters?.isFavorite == true) {
      filterQuery = filterQuery.eq('is_favorite', true);
    }

    // Build order clause
    final (column, ascending) = _getSortParams(sort);

    // Apply sorting and pagination
    final List<dynamic> response;
    if (offset != null) {
      response = await filterQuery
          .order(column, ascending: ascending)
          .range(offset, offset + (limit ?? 20) - 1);
    } else if (limit != null) {
      response = await filterQuery
          .order(column, ascending: ascending)
          .limit(limit);
    } else {
      response = await filterQuery.order(column, ascending: ascending);
    }

    // Filter by album properties (genres, year) in memory
    // since they require the joined album data
    var results =
        response.map((row) => LibraryAlbum.fromJson(row as Map<String, dynamic>)).toList();

    if (filters != null) {
      results = results.where((la) {
        final album = la.album;
        if (album == null) return true;

        // Genre filter
        if (filters.genres != null && filters.genres!.isNotEmpty) {
          final hasGenre =
              album.genres.any((g) => filters.genres!.contains(g));
          if (!hasGenre) return false;
        }

        // Year filter
        if (filters.yearFrom != null && album.year != null) {
          if (album.year! < filters.yearFrom!) return false;
        }
        if (filters.yearTo != null && album.year != null) {
          if (album.year! > filters.yearTo!) return false;
        }

        return true;
      }).toList();
    }

    return results;
  }

  (String, bool) _getSortParams(AlbumSortOption sort) {
    switch (sort) {
      case AlbumSortOption.artistAsc:
        return ('album(artist)', true);
      case AlbumSortOption.artistDesc:
        return ('album(artist)', false);
      case AlbumSortOption.titleAsc:
        return ('album(title)', true);
      case AlbumSortOption.titleDesc:
        return ('album(title)', false);
      case AlbumSortOption.dateAddedAsc:
        return ('added_at', true);
      case AlbumSortOption.dateAddedDesc:
        return ('added_at', false);
      case AlbumSortOption.yearAsc:
        return ('album(year)', true);
      case AlbumSortOption.yearDesc:
        return ('album(year)', false);
    }
  }

  /// Gets a single library album by ID.
  Future<LibraryAlbum?> getLibraryAlbum(String libraryAlbumId) async {
    final response = await client
        .from(_libraryAlbumsTable)
        .select('*, album:albums(*)')
        .eq('id', libraryAlbumId)
        .maybeSingle();

    if (response == null) return null;
    return LibraryAlbum.fromJson(response);
  }

  /// Adds an album to a library.
  Future<LibraryAlbum> addAlbumToLibrary(
    String libraryId,
    String albumId,
    String userId,
  ) async {
    final response = await client
        .from(_libraryAlbumsTable)
        .insert({
          'library_id': libraryId,
          'album_id': albumId,
          'added_by': userId,
          'added_at': DateTime.now().toIso8601String(),
          'is_favorite': false,
        })
        .select('*, album:albums(*)')
        .single();

    return LibraryAlbum.fromJson(response);
  }

  /// Removes an album from a library.
  Future<void> removeAlbumFromLibrary(String libraryAlbumId) async {
    await client.from(_libraryAlbumsTable).delete().eq('id', libraryAlbumId);
  }

  /// Updates a library album (notes, favorite status).
  Future<LibraryAlbum> updateLibraryAlbum(LibraryAlbum libraryAlbum) async {
    final response = await client
        .from(_libraryAlbumsTable)
        .update({
          'notes': libraryAlbum.notes,
          'is_favorite': libraryAlbum.isFavorite,
        })
        .eq('id', libraryAlbum.id)
        .select('*, album:albums(*)')
        .single();

    return LibraryAlbum.fromJson(response);
  }

  /// Toggles the favorite status of a library album.
  Future<LibraryAlbum> toggleFavorite(String libraryAlbumId) async {
    // Get current state
    final current = await getLibraryAlbum(libraryAlbumId);
    if (current == null) {
      throw Exception('Library album not found');
    }

    // Toggle and save
    return updateLibraryAlbum(
      current.copyWith(isFavorite: !current.isFavorite),
    );
  }

  /// Gets the count of albums in a library.
  Future<int> getLibraryAlbumCount(String libraryId) async {
    final response = await client
        .from(_libraryAlbumsTable)
        .select()
        .eq('library_id', libraryId)
        .count();

    return response.count;
  }
}
