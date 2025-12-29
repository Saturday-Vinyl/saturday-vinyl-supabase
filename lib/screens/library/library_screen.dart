import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/library_filter_provider.dart';
import 'package:saturday_consumer_app/providers/library_view_provider.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/library/album_grid.dart';
import 'package:saturday_consumer_app/widgets/library/album_list.dart';
import 'package:saturday_consumer_app/widgets/library/album_quick_actions.dart';
import 'package:saturday_consumer_app/widgets/library/filter_bar.dart';
import 'package:saturday_consumer_app/widgets/library/filter_bottom_sheet.dart';
import 'package:saturday_consumer_app/widgets/library/sort_dropdown.dart';
import 'package:saturday_consumer_app/widgets/library/view_toggle.dart';

/// Library screen - shows the user's vinyl collection.
///
/// Features:
/// - Grid/list view toggle for albums
/// - Sort and filter options
/// - Quick search within library
/// - Add album via scanning or search
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the sync provider to keep album provider in sync with filter state
    ref.watch(filterSyncProvider);

    final albumsAsync = ref.watch(libraryAlbumsProvider);
    final viewMode = ref.watch(libraryViewModeProvider);
    final filterState = ref.watch(libraryFilterProvider);
    final hasFilters = ref.watch(hasActiveFiltersProvider);

    return Scaffold(
      appBar: const SaturdayAppBar(
        showLibrarySwitcher: true,
        showSearch: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Sort/view toolbar
            _buildToolbar(context, ref, filterState, viewMode),

            // Filter bar (shows when filters are active or always visible)
            _buildFilterBar(context, ref, filterState),

            const Divider(height: 1),

            // Album content
            Expanded(
              child: albumsAsync.when(
                data: (albums) => _buildAlbumContent(
                  context,
                  ref,
                  albums,
                  viewMode,
                  hasFilters,
                ),
                loading: () => _buildLoadingState(),
                error: (error, stack) => _buildErrorState(
                  context,
                  ref,
                  error.toString(),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // TODO: Navigate to add album screen
        },
        tooltip: 'Add Album',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Build the toolbar with sort options and view toggle.
  Widget _buildToolbar(
    BuildContext context,
    WidgetRef ref,
    LibraryFilterState filterState,
    LibraryViewMode viewMode,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.sm,
        vertical: Spacing.xs,
      ),
      child: Row(
        children: [
          // Sort dropdown
          SortDropdown(
            currentSort: filterState.sortOption,
            onSortChanged: (sort) {
              ref.read(libraryFilterProvider.notifier).setSortOption(sort);
            },
          ),
          const Spacer(),
          // View toggle
          ViewToggleIconButton(
            currentMode: viewMode,
            onModeChanged: (mode) {
              ref.read(libraryViewModeProvider.notifier).setViewMode(mode);
            },
          ),
        ],
      ),
    );
  }

  /// Build the filter bar with active filter chips.
  Widget _buildFilterBar(
    BuildContext context,
    WidgetRef ref,
    LibraryFilterState filterState,
  ) {
    return FilterBar(
      selectedGenres: filterState.selectedGenres,
      selectedDecades: filterState.selectedDecades,
      favoritesOnly: filterState.favoritesOnly,
      activeFilterCount: filterState.activeFilterCount,
      onGenreRemoved: (genre) {
        ref.read(libraryFilterProvider.notifier).toggleGenre(genre);
      },
      onDecadeRemoved: (decade) {
        ref.read(libraryFilterProvider.notifier).toggleDecade(decade);
      },
      onFavoritesToggled: () {
        ref.read(libraryFilterProvider.notifier).toggleFavoritesOnly();
      },
      onClearAll: () {
        ref.read(libraryFilterProvider.notifier).clearFilters();
      },
      onFilterTap: () => _showFilterSheet(context, ref),
    );
  }

  /// Show the full filter bottom sheet.
  void _showFilterSheet(BuildContext context, WidgetRef ref) {
    final filterState = ref.read(libraryFilterProvider);
    final availableGenres = ref.read(availableGenresProvider);
    final availableDecades = ref.read(availableDecadesProvider);

    showFilterBottomSheet(
      context: context,
      selectedGenres: filterState.selectedGenres,
      selectedDecades: filterState.selectedDecades,
      favoritesOnly: filterState.favoritesOnly,
      availableGenres: availableGenres,
      availableDecades: availableDecades,
      currentSort: filterState.sortOption,
      onApply: ({
        required Set<String> genres,
        required Set<String> decades,
        required bool favoritesOnly,
        required AlbumSortOption sort,
      }) {
        final notifier = ref.read(libraryFilterProvider.notifier);
        notifier.setGenres(genres);
        notifier.setDecades(decades);
        notifier.setFavoritesOnly(favoritesOnly);
        notifier.setSortOption(sort);
      },
    );
  }

  /// Build the album content based on view mode.
  Widget _buildAlbumContent(
    BuildContext context,
    WidgetRef ref,
    List<LibraryAlbum> albums,
    LibraryViewMode viewMode,
    bool hasFilters,
  ) {
    if (albums.isEmpty) {
      if (hasFilters) {
        return _buildNoResultsState(context, ref);
      }
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Invalidate the provider to trigger a refresh
        ref.invalidate(libraryAlbumsProvider);
        // Wait for the refresh to complete
        await ref.read(libraryAlbumsProvider.future);
      },
      child: viewMode == LibraryViewMode.grid
          ? AlbumGrid(
              albums: albums,
              onAlbumTap: (album) => _onAlbumTap(context, album),
              onAlbumLongPress: (album) =>
                  _onAlbumLongPress(context, ref, album),
            )
          : AlbumList(
              albums: albums,
              onAlbumTap: (album) => _onAlbumTap(context, album),
              onAlbumLongPress: (album) =>
                  _onAlbumLongPress(context, ref, album),
            ),
    );
  }

  /// Handle album tap - navigate to album detail.
  void _onAlbumTap(BuildContext context, LibraryAlbum album) {
    context.push('/library/album/${album.id}');
  }

  /// Handle album long-press - show quick actions menu.
  void _onAlbumLongPress(
    BuildContext context,
    WidgetRef ref,
    LibraryAlbum album,
  ) {
    showAlbumQuickActions(context, ref, album);
  }

  /// Build the loading state.
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: Spacing.lg),
          Text('Loading your library...'),
        ],
      ),
    );
  }

  /// Build the error state.
  Widget _buildErrorState(BuildContext context, WidgetRef ref, String error) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: SaturdayColors.error,
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Failed to load library',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SaturdayColors.secondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: Spacing.xl),
            ElevatedButton.icon(
              onPressed: () {
                ref.invalidate(libraryAlbumsProvider);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the empty state when no albums in library.
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.album_outlined,
              size: 80,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'Your library is empty',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Add albums by scanning barcodes or\nsearching the Discogs catalog',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SaturdayColors.secondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: Spacing.xxl),
            ElevatedButton.icon(
              onPressed: () {
                // TODO: Open scanner
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan Barcode'),
            ),
            const SizedBox(height: Spacing.md),
            OutlinedButton.icon(
              onPressed: () {
                // TODO: Open search
              },
              icon: const Icon(Icons.search),
              label: const Text('Search Discogs'),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the state when filters return no results.
  Widget _buildNoResultsState(BuildContext context, WidgetRef ref) {
    return Center(
      child: SingleChildScrollView(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.filter_list_off,
              size: 80,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              'No matching albums',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Try adjusting your filters to\nsee more results',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SaturdayColors.secondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: Spacing.xxl),
            ElevatedButton.icon(
              onPressed: () {
                ref.read(libraryFilterProvider.notifier).clearFilters();
              },
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }
}
