import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/library_filter_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/library_view_provider.dart';
import 'package:saturday_consumer_app/screens/onboarding/quick_start_screen.dart';
import 'package:saturday_consumer_app/screens/tablet/tablet_home_screen.dart';
import 'package:saturday_consumer_app/widgets/common/empty_state.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/library/album_grid.dart';
import 'package:saturday_consumer_app/widgets/library/album_list.dart';
import 'package:saturday_consumer_app/widgets/library/album_quick_actions.dart';
import 'package:saturday_consumer_app/widgets/library/filter_bar.dart';
import 'package:saturday_consumer_app/widgets/library/filter_bottom_sheet.dart';
import 'package:saturday_consumer_app/widgets/library/view_toggle.dart';

/// Library screen - shows the user's vinyl collection.
///
/// Features:
/// - Grid/list view toggle for albums
/// - Sort and filter options
/// - Quick search within library
/// - Add album via scanning or search
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  Widget build(BuildContext context) {
    // Check if user has any libraries
    final librariesAsync = ref.watch(userLibrariesProvider);

    return librariesAsync.when(
      data: (libraries) {
        if (libraries.isEmpty) {
          // Show empty state prompting user to create a library
          return _buildNoLibrariesState(context);
        }
        return _buildLibraryContent(context, ref);
      },
      loading: () => Scaffold(
        appBar: const SaturdayAppBar(
          showLibrarySwitcher: true,
          showSearch: true,
        ),
        body: const LoadingIndicator.medium(
          message: 'Loading your libraries...',
        ),
      ),
      error: (error, stack) => Scaffold(
        appBar: const SaturdayAppBar(
          showLibrarySwitcher: true,
          showSearch: true,
        ),
        body: ErrorDisplay.fullScreen(
          message: error.toString(),
          onRetry: () => ref.invalidate(userLibrariesProvider),
        ),
      ),
    );
  }

  /// Build the main library content when user has libraries.
  Widget _buildLibraryContent(BuildContext context, WidgetRef ref) {
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
            // Unified filter bar with sort, filters, and view toggle
            _buildFilterBar(context, ref, filterState, viewMode),

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
        onPressed: () => _showAddAlbumMenu(context),
        tooltip: 'Add Album',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Show the add album menu with camera and manual entry options.
  void _showAddAlbumMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                'Add Album',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: SaturdayColors.primaryDark,
                ),
              ),
              title: const Text('Use Camera'),
              subtitle: const Text(
                'Scan barcode or photograph album cover',
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/library/add/scan');
              },
            ),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.search,
                  color: SaturdayColors.primaryDark,
                ),
              ),
              title: const Text('Manual Entry'),
              subtitle: const Text(
                'Search by artist, album, or catalog number',
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/library/add/search');
              },
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ),
      ),
    );
  }

  /// Build the unified filter bar with sort, filters, and view toggle.
  Widget _buildFilterBar(
    BuildContext context,
    WidgetRef ref,
    LibraryFilterState filterState,
    LibraryViewMode viewMode,
  ) {
    return Row(
      children: [
        // Filter bar (takes remaining space)
        Expanded(
          child: FilterBar(
            selectedGenres: filterState.selectedGenres,
            selectedDecades: filterState.selectedDecades,
            favoritesOnly: filterState.favoritesOnly,
            currentSort: filterState.sortOption,
            isSortNonDefault: filterState.isSortNonDefault,
            totalActiveCount: filterState.totalActiveCount,
            onGenreRemoved: (genre) {
              ref.read(libraryFilterProvider.notifier).toggleGenre(genre);
            },
            onDecadeRemoved: (decade) {
              ref.read(libraryFilterProvider.notifier).toggleDecade(decade);
            },
            onFavoritesToggled: () {
              ref.read(libraryFilterProvider.notifier).toggleFavoritesOnly();
            },
            onSortReset: () {
              ref.read(libraryFilterProvider.notifier).resetSortToDefault();
            },
            onClearAll: () {
              ref.read(libraryFilterProvider.notifier).resetAll();
            },
            onFilterTap: () => _showFilterSheet(context, ref),
          ),
        ),
        // View toggle on the right
        Padding(
          padding: const EdgeInsets.only(right: Spacing.sm),
          child: ViewToggleIconButton(
            currentMode: viewMode,
            onModeChanged: (mode) {
              ref.read(libraryViewModeProvider.notifier).setViewMode(mode);
            },
          ),
        ),
      ],
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
  ///
  /// On tablets in landscape, this opens the album in the detail panel.
  /// On phones or tablets in portrait, navigates to the full detail screen.
  void _onAlbumTap(BuildContext context, LibraryAlbum album) {
    handleAlbumTap(context, ref, album.id);
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
    return const LoadingIndicator.medium(
      message: 'Loading your library...',
    );
  }

  /// Build the error state.
  Widget _buildErrorState(BuildContext context, WidgetRef ref, String error) {
    return ErrorDisplay.fullScreen(
      message: error,
      onRetry: () => ref.invalidate(libraryAlbumsProvider),
    );
  }

  /// Build the state when user has no libraries.
  ///
  /// Shows the QuickStartScreen inline instead of navigating to it.
  Widget _buildNoLibrariesState(BuildContext context) {
    return const QuickStartScreen();
  }

  /// Build the empty state when no albums in library.
  Widget _buildEmptyState(BuildContext context) {
    return EmptyState.library(
      onAddAlbum: () => _showAddAlbumMenu(context),
    );
  }

  /// Build the state when filters return no results.
  Widget _buildNoResultsState(BuildContext context, WidgetRef ref) {
    return EmptyState.noFilterResults(
      onClearFilters: () {
        ref.read(libraryFilterProvider.notifier).clearFilters();
      },
    );
  }
}
