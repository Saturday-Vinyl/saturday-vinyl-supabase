import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/album.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/repositories/album_repository.dart';

// Re-export enums and classes for convenience
export 'package:saturday_consumer_app/repositories/album_repository.dart'
    show AlbumSortOption, AlbumFilters;

/// FutureProvider for ALL albums in the current library (unfiltered).
///
/// Used for computing available genres, years, etc.
/// For display, use [libraryAlbumsProvider] which respects filters.
final allLibraryAlbumsProvider =
    FutureProvider<List<LibraryAlbum>>((ref) async {
  final libraryId = ref.watch(currentLibraryIdProvider);
  if (libraryId == null) return [];

  final albumRepo = ref.watch(albumRepositoryProvider);
  return albumRepo.getLibraryAlbums(libraryId);
});

/// Provider for current sort option.
/// This is updated by libraryFilterProvider.
final currentAlbumSortProvider = StateProvider<AlbumSortOption>((ref) {
  return AlbumSortOption.dateAddedDesc;
});

/// Provider for current filters.
/// This is updated by libraryFilterProvider.
final currentAlbumFiltersProvider = StateProvider<AlbumFilters?>((ref) {
  return null;
});

/// FutureProvider for albums in the current library.
///
/// Respects current sort and filter settings.
final libraryAlbumsProvider =
    FutureProvider<List<LibraryAlbum>>((ref) async {
  final libraryId = ref.watch(currentLibraryIdProvider);
  if (libraryId == null) return [];

  final albumRepo = ref.watch(albumRepositoryProvider);
  final sort = ref.watch(currentAlbumSortProvider);
  final filters = ref.watch(currentAlbumFiltersProvider);

  return albumRepo.getLibraryAlbums(
    libraryId,
    sort: sort,
    filters: filters,
  );
});

/// Provider for the count of albums in the current library.
final libraryAlbumCountProvider = FutureProvider<int>((ref) async {
  final libraryId = ref.watch(currentLibraryIdProvider);
  if (libraryId == null) return 0;

  final albumRepo = ref.watch(albumRepositoryProvider);
  return albumRepo.getLibraryAlbumCount(libraryId);
});

/// FutureProvider.family for fetching a canonical album by ID.
final albumByIdProvider =
    FutureProvider.family<Album?, String>((ref, albumId) async {
  final albumRepo = ref.watch(albumRepositoryProvider);
  return albumRepo.getAlbum(albumId);
});

/// FutureProvider.family for fetching a library album by ID.
final libraryAlbumByIdProvider =
    FutureProvider.family<LibraryAlbum?, String>((ref, libraryAlbumId) async {
  final albumRepo = ref.watch(albumRepositoryProvider);
  return albumRepo.getLibraryAlbum(libraryAlbumId);
});

/// FutureProvider.family for searching albums.
final albumSearchProvider =
    FutureProvider.family<List<Album>, String>((ref, query) async {
  if (query.isEmpty) return [];

  final albumRepo = ref.watch(albumRepositoryProvider);
  return albumRepo.searchAlbums(query);
});

/// Provider for favorite albums in the current library.
final favoriteAlbumsProvider =
    FutureProvider<List<LibraryAlbum>>((ref) async {
  final libraryId = ref.watch(currentLibraryIdProvider);
  if (libraryId == null) return [];

  final albumRepo = ref.watch(albumRepositoryProvider);
  return albumRepo.getLibraryAlbums(
    libraryId,
    filters: const AlbumFilters(isFavorite: true),
  );
});

/// Provider for unique genres in the current library.
/// Uses allLibraryAlbumsProvider to get genres from all albums, not just filtered.
final libraryGenresProvider = Provider<List<String>>((ref) {
  final albums = ref.watch(allLibraryAlbumsProvider);
  return albums.whenOrNull(
        data: (albumList) {
          final genres = <String>{};
          for (final la in albumList) {
            if (la.album != null) {
              genres.addAll(la.album!.genres);
            }
          }
          final sorted = genres.toList()..sort();
          return sorted;
        },
      ) ??
      [];
});

/// Provider for the year range in the current library.
/// Uses allLibraryAlbumsProvider to get range from all albums, not just filtered.
final libraryYearRangeProvider = Provider<({int? min, int? max})>((ref) {
  final albums = ref.watch(allLibraryAlbumsProvider);
  return albums.whenOrNull(
        data: (albumList) {
          int? minYear;
          int? maxYear;
          for (final la in albumList) {
            final year = la.album?.year;
            if (year != null) {
              minYear =
                  minYear == null ? year : (year < minYear ? year : minYear);
              maxYear =
                  maxYear == null ? year : (year > maxYear ? year : maxYear);
            }
          }
          return (min: minYear, max: maxYear);
        },
      ) ??
      (min: null, max: null);
});
