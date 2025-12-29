import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart'
    show
        currentAlbumFiltersProvider,
        currentAlbumSortProvider,
        libraryGenresProvider,
        libraryYearRangeProvider;
import 'package:saturday_consumer_app/providers/library_view_provider.dart';
import 'package:saturday_consumer_app/repositories/album_repository.dart';

/// Keys for storing filter/sort preferences.
const String _sortOptionKey = 'library_sort_option';

/// State class for library filters.
class LibraryFilterState {
  final AlbumSortOption sortOption;
  final Set<String> selectedGenres;
  final Set<String> selectedDecades;
  final String? selectedLocationId;
  final bool favoritesOnly;

  const LibraryFilterState({
    this.sortOption = AlbumSortOption.dateAddedDesc,
    this.selectedGenres = const {},
    this.selectedDecades = const {},
    this.selectedLocationId,
    this.favoritesOnly = false,
  });

  /// Returns true if any filters are active.
  bool get hasActiveFilters =>
      selectedGenres.isNotEmpty ||
      selectedDecades.isNotEmpty ||
      selectedLocationId != null ||
      favoritesOnly;

  /// Returns the count of active filters.
  int get activeFilterCount {
    int count = 0;
    if (selectedGenres.isNotEmpty) count++;
    if (selectedDecades.isNotEmpty) count++;
    if (selectedLocationId != null) count++;
    if (favoritesOnly) count++;
    return count;
  }

  /// Converts the state to AlbumFilters for repository use.
  AlbumFilters? toAlbumFilters() {
    if (!hasActiveFilters) return null;

    // Convert decades to year range
    int? yearFrom;
    int? yearTo;
    if (selectedDecades.isNotEmpty) {
      final decades = selectedDecades.map((d) => int.tryParse(d) ?? 0).toList();
      yearFrom = decades.reduce((a, b) => a < b ? a : b);
      yearTo = decades.reduce((a, b) => a > b ? a : b) + 9;
    }

    return AlbumFilters(
      genres: selectedGenres.isNotEmpty ? selectedGenres.toList() : null,
      yearFrom: yearFrom,
      yearTo: yearTo,
      isFavorite: favoritesOnly ? true : null,
    );
  }

  LibraryFilterState copyWith({
    AlbumSortOption? sortOption,
    Set<String>? selectedGenres,
    Set<String>? selectedDecades,
    String? selectedLocationId,
    bool? clearLocationId,
    bool? favoritesOnly,
  }) {
    return LibraryFilterState(
      sortOption: sortOption ?? this.sortOption,
      selectedGenres: selectedGenres ?? this.selectedGenres,
      selectedDecades: selectedDecades ?? this.selectedDecades,
      selectedLocationId:
          clearLocationId == true ? null : (selectedLocationId ?? this.selectedLocationId),
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    );
  }
}

/// StateNotifier for managing library filters with persistence.
class LibraryFilterNotifier extends StateNotifier<LibraryFilterState> {
  LibraryFilterNotifier(this._prefs) : super(_loadInitialState(_prefs));

  final SharedPreferences _prefs;

  /// Load the initial state from preferences.
  static LibraryFilterState _loadInitialState(SharedPreferences prefs) {
    final sortIndex = prefs.getInt(_sortOptionKey);
    final sortOption = sortIndex != null && sortIndex < AlbumSortOption.values.length
        ? AlbumSortOption.values[sortIndex]
        : AlbumSortOption.dateAddedDesc;

    return LibraryFilterState(sortOption: sortOption);
  }

  /// Set the sort option and persist it.
  Future<void> setSortOption(AlbumSortOption option) async {
    state = state.copyWith(sortOption: option);
    await _prefs.setInt(_sortOptionKey, option.index);
  }

  /// Toggle a genre filter.
  void toggleGenre(String genre) {
    final newGenres = Set<String>.from(state.selectedGenres);
    if (newGenres.contains(genre)) {
      newGenres.remove(genre);
    } else {
      newGenres.add(genre);
    }
    state = state.copyWith(selectedGenres: newGenres);
  }

  /// Set selected genres.
  void setGenres(Set<String> genres) {
    state = state.copyWith(selectedGenres: genres);
  }

  /// Toggle a decade filter.
  void toggleDecade(String decade) {
    final newDecades = Set<String>.from(state.selectedDecades);
    if (newDecades.contains(decade)) {
      newDecades.remove(decade);
    } else {
      newDecades.add(decade);
    }
    state = state.copyWith(selectedDecades: newDecades);
  }

  /// Set selected decades.
  void setDecades(Set<String> decades) {
    state = state.copyWith(selectedDecades: decades);
  }

  /// Set the location filter.
  void setLocation(String? locationId) {
    if (locationId == null) {
      state = state.copyWith(clearLocationId: true);
    } else {
      state = state.copyWith(selectedLocationId: locationId);
    }
  }

  /// Toggle favorites only filter.
  void toggleFavoritesOnly() {
    state = state.copyWith(favoritesOnly: !state.favoritesOnly);
  }

  /// Set favorites only filter.
  void setFavoritesOnly(bool value) {
    state = state.copyWith(favoritesOnly: value);
  }

  /// Clear all filters (but keep sort option).
  void clearFilters() {
    state = LibraryFilterState(sortOption: state.sortOption);
  }

  /// Clear all filters and reset sort to default.
  void resetAll() {
    state = const LibraryFilterState();
    _prefs.remove(_sortOptionKey);
  }
}

/// Provider for library filter state with persistence.
final libraryFilterProvider =
    StateNotifierProvider<LibraryFilterNotifier, LibraryFilterState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LibraryFilterNotifier(prefs);
});

/// Provider that returns true if any filters are active.
final hasActiveFiltersProvider = Provider<bool>((ref) {
  return ref.watch(libraryFilterProvider).hasActiveFilters;
});

/// Provider that returns the count of active filters.
final activeFilterCountProvider = Provider<int>((ref) {
  return ref.watch(libraryFilterProvider).activeFilterCount;
});

/// Provider for the current sort option.
final currentSortOptionProvider = Provider<AlbumSortOption>((ref) {
  return ref.watch(libraryFilterProvider).sortOption;
});

/// Provider for available decades based on library content.
final availableDecadesProvider = Provider<List<String>>((ref) {
  final yearRange = ref.watch(libraryYearRangeProvider);
  if (yearRange.min == null || yearRange.max == null) return [];

  final startDecade = (yearRange.min! ~/ 10) * 10;
  final endDecade = (yearRange.max! ~/ 10) * 10;

  final decades = <String>[];
  for (int decade = startDecade; decade <= endDecade; decade += 10) {
    decades.add(decade.toString());
  }
  return decades;
});

/// Provider for available genres in the current library.
/// Re-exports from album_provider for convenience.
final availableGenresProvider = Provider<List<String>>((ref) {
  return ref.watch(libraryGenresProvider);
});

/// Provider that syncs filter state to album provider.
///
/// This provider watches the filter state and updates the album provider's
/// sort and filter settings. It should be watched by the library screen.
final filterSyncProvider = Provider<void>((ref) {
  final filterState = ref.watch(libraryFilterProvider);

  // Update the album provider's sort and filter settings
  ref.read(currentAlbumSortProvider.notifier).state = filterState.sortOption;
  ref.read(currentAlbumFiltersProvider.notifier).state =
      filterState.toAlbumFilters();
});
