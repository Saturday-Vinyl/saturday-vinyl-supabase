import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/library_artist.dart';
import 'package:saturday_consumer_app/providers/add_album_provider.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/services/discogs_service.dart';

/// State for global search.
class SearchState {
  final String query;
  final bool isSearching;
  final List<LibraryAlbum> libraryResults;
  final List<DiscogsSearchResult> discogsResults;
  final List<LibraryArtist> libraryArtists;
  final List<DiscogsArtistResult> discogsArtists;
  final String? error;
  final bool hasSearched;

  const SearchState({
    this.query = '',
    this.isSearching = false,
    this.libraryResults = const [],
    this.discogsResults = const [],
    this.libraryArtists = const [],
    this.discogsArtists = const [],
    this.error,
    this.hasSearched = false,
  });

  SearchState copyWith({
    String? query,
    bool? isSearching,
    List<LibraryAlbum>? libraryResults,
    List<DiscogsSearchResult>? discogsResults,
    List<LibraryArtist>? libraryArtists,
    List<DiscogsArtistResult>? discogsArtists,
    String? error,
    bool? hasSearched,
  }) {
    return SearchState(
      query: query ?? this.query,
      isSearching: isSearching ?? this.isSearching,
      libraryResults: libraryResults ?? this.libraryResults,
      discogsResults: discogsResults ?? this.discogsResults,
      libraryArtists: libraryArtists ?? this.libraryArtists,
      discogsArtists: discogsArtists ?? this.discogsArtists,
      error: error,
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }

  bool get hasResults =>
      libraryResults.isNotEmpty ||
      discogsResults.isNotEmpty ||
      libraryArtists.isNotEmpty ||
      discogsArtists.isNotEmpty;

  bool get isEmpty => !isSearching && hasSearched && !hasResults;
}

/// Notifier for global search state.
class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._ref) : super(const SearchState());

  final Ref _ref;
  Timer? _debounceTimer;

  static const _debounceDelay = Duration(milliseconds: 300);

  /// Updates the search query with debouncing.
  void setQuery(String query) {
    state = state.copyWith(query: query, error: null);

    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      state = state.copyWith(
        isSearching: false,
        libraryResults: [],
        discogsResults: [],
        libraryArtists: [],
        discogsArtists: [],
        hasSearched: false,
      );
      return;
    }

    state = state.copyWith(isSearching: true);

    _debounceTimer = Timer(_debounceDelay, () {
      _performSearch(query);
    });
  }

  /// Performs the actual search.
  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    try {
      // Search in parallel: library albums + artists, Discogs albums + artists.
      final results = await Future.wait([
        _searchLibrary(query),
        _searchDiscogs(query),
        _searchLibraryArtists(query),
        _searchDiscogsArtists(query),
      ]);

      state = state.copyWith(
        isSearching: false,
        libraryResults: results[0] as List<LibraryAlbum>,
        discogsResults: results[1] as List<DiscogsSearchResult>,
        libraryArtists: results[2] as List<LibraryArtist>,
        discogsArtists: results[3] as List<DiscogsArtistResult>,
        hasSearched: true,
      );
    } catch (e) {
      state = state.copyWith(
        isSearching: false,
        error: e.toString(),
        hasSearched: true,
      );
    }
  }

  /// Searches albums in the current library.
  Future<List<LibraryAlbum>> _searchLibrary(String query) async {
    final currentLibraryId = _ref.read(currentLibraryIdProvider);
    if (currentLibraryId == null) return [];

    // Get all library albums and filter in memory
    // (For a production app, you'd want server-side search)
    final albumsAsync = await _ref.read(libraryAlbumsProvider.future);

    final normalizedQuery = query.toLowerCase();
    return albumsAsync.where((la) {
      final album = la.album;
      if (album == null) return false;

      final title = album.title.toLowerCase();
      final artist = album.artist.toLowerCase();
      final genres = album.genres.map((g) => g.toLowerCase()).toList();

      return title.contains(normalizedQuery) ||
          artist.contains(normalizedQuery) ||
          genres.any((g) => g.contains(normalizedQuery));
    }).toList();
  }

  /// Searches albums on Discogs.
  Future<List<DiscogsSearchResult>> _searchDiscogs(String query) async {
    try {
      final discogsService = _ref.read(discogsServiceProvider);
      return await discogsService.search(query, perPage: 10);
    } catch (e) {
      // Don't fail the whole search if Discogs fails
      return [];
    }
  }

  /// Searches distinct artists in the current library.
  Future<List<LibraryArtist>> _searchLibraryArtists(String query) async {
    final currentLibraryId = _ref.read(currentLibraryIdProvider);
    if (currentLibraryId == null) return [];

    try {
      final albumRepo = _ref.read(albumRepositoryProvider);
      return await albumRepo.searchLibraryArtists(currentLibraryId, query);
    } catch (e) {
      return [];
    }
  }

  /// Searches artists on Discogs.
  Future<List<DiscogsArtistResult>> _searchDiscogsArtists(String query) async {
    try {
      final discogsService = _ref.read(discogsServiceProvider);
      return await discogsService.searchArtists(query, perPage: 5);
    } catch (e) {
      // Don't fail the whole search if Discogs fails
      return [];
    }
  }

  /// Clears the search.
  void clear() {
    _debounceTimer?.cancel();
    state = const SearchState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Provider for global search.
final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref);
});

/// Recent searches provider (stored in memory for now).
final recentSearchesProvider = StateProvider<List<String>>((ref) => []);

/// Adds a search query to recent searches.
void addToRecentSearches(WidgetRef ref, String query) {
  if (query.trim().isEmpty) return;

  final current = ref.read(recentSearchesProvider);
  final updated = [
    query,
    ...current.where((s) => s != query),
  ].take(5).toList();

  ref.read(recentSearchesProvider.notifier).state = updated;
}
