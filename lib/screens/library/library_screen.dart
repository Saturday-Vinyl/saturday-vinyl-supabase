import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/collection_item.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/collection_provider.dart';
import 'package:saturday_consumer_app/providers/cratelist_provider.dart';
import 'package:saturday_consumer_app/providers/library_filter_provider.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';
import 'package:saturday_consumer_app/providers/library_view_provider.dart';
import 'package:saturday_consumer_app/repositories/cratelist_repository.dart';
import 'package:saturday_consumer_app/screens/library/create_cratelist_sheet.dart';
import 'package:saturday_consumer_app/screens/onboarding/quick_start_screen.dart';
import 'package:saturday_consumer_app/screens/tablet/tablet_home_screen.dart';
import 'package:saturday_consumer_app/widgets/common/empty_state.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/library/album_quick_actions.dart';
import 'package:saturday_consumer_app/widgets/library/collection_grid.dart';
import 'package:saturday_consumer_app/widgets/library/collection_list.dart';
import 'package:saturday_consumer_app/widgets/library/collection_type_chips.dart';
import 'package:saturday_consumer_app/widgets/library/filter_bar.dart';
import 'package:saturday_consumer_app/widgets/library/filter_bottom_sheet.dart';
import 'package:saturday_consumer_app/widgets/library/view_toggle.dart';

/// Library screen — unified browse view for the user's vinyl collection.
///
/// Albums and cratelists share a single grid/list. Type chips narrow to
/// one or the other; cratelists are pinned to the top when shown.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  Widget build(BuildContext context) {
    final librariesAsync = ref.watch(userLibrariesProvider);

    return librariesAsync.when(
      data: (libraries) {
        if (libraries.isEmpty) return _buildNoLibrariesState();
        return _buildLibraryContent(context);
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
      error: (error, _) => Scaffold(
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

  Widget _buildLibraryContent(BuildContext context) {
    ref.watch(filterSyncProvider);

    final itemsAsync = ref.watch(collectionItemsProvider);
    final viewMode = ref.watch(libraryViewModeProvider);
    final filterState = ref.watch(libraryFilterProvider);
    final hasFilters = ref.watch(hasActiveFiltersProvider);
    final type = ref.watch(collectionTypeFilterProvider);

    return Scaffold(
      appBar: const SaturdayAppBar(
        showLibrarySwitcher: true,
        showSearch: true,
      ),
      body: SafeArea(
        child: itemsAsync.when(
          data: (items) => _buildScrollView(
            context,
            ref,
            items,
            viewMode,
            filterState,
            hasFilters,
            type,
          ),
          loading: () => const LoadingIndicator.medium(
            message: 'Loading your library...',
          ),
          error: (error, _) => ErrorDisplay.fullScreen(
            message: error.toString(),
            onRetry: () => ref.invalidate(collectionItemsProvider),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddMenu(context),
        tooltip: 'Add',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildScrollView(
    BuildContext context,
    WidgetRef ref,
    List<CollectionItem> items,
    LibraryViewMode viewMode,
    LibraryFilterState filterState,
    bool hasFilters,
    CollectionTypeFilter type,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(libraryAlbumsProvider);
        ref.invalidate(cratelistPreviewsProvider);
        ref.invalidate(collectionItemsProvider);
        await ref.read(collectionItemsProvider.future);
      },
      child: CustomScrollView(
        slivers: [
          // Type chips — floating header that collapses on scroll down and
          // reappears on scroll up.
          SliverAppBar(
            primary: false,
            automaticallyImplyLeading: false,
            floating: true,
            snap: true,
            pinned: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: _chipsHeight,
            titleSpacing: 0,
            title: const CollectionTypeChips(),
          ),
          // Filter bar — stays pinned so users can adjust filters mid-scroll.
          SliverPersistentHeader(
            pinned: true,
            delegate: _FilterBarHeaderDelegate(
              child: _buildFilterBar(context, ref, filterState, viewMode),
              height: _filterBarHeight,
            ),
          ),
          if (items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyForState(context, type, hasFilters),
            )
          else if (viewMode == LibraryViewMode.grid)
            SliverCollectionGrid(
              items: items,
              onAlbumTap: (album) => _onAlbumTap(context, album),
              onAlbumLongPress: (album) =>
                  _onAlbumLongPress(context, ref, album),
              onCratelistTap: (preview) =>
                  _onCratelistTap(context, preview),
            )
          else
            SliverCollectionList(
              items: items,
              onAlbumTap: (album) => _onAlbumTap(context, album),
              onAlbumLongPress: (album) =>
                  _onAlbumLongPress(context, ref, album),
              onCratelistTap: (preview) =>
                  _onCratelistTap(context, preview),
            ),
        ],
      ),
    );
  }

  static const double _chipsHeight = 56;
  static const double _filterBarHeight = 56;

  Widget _buildEmptyForState(
    BuildContext context,
    CollectionTypeFilter type,
    bool hasFilters,
  ) {
    if (hasFilters && type != CollectionTypeFilter.cratelists) {
      return EmptyState.noFilterResults(
        onClearFilters: () =>
            ref.read(libraryFilterProvider.notifier).clearFilters(),
      );
    }

    if (type == CollectionTypeFilter.cratelists) {
      return EmptyState(
        icon: Icons.queue_music,
        title: 'No cratelists yet',
        message: 'Group records from your library into ordered crates you '
            'can queue up to play.',
        actionLabel: 'New cratelist',
        onAction: () => _onCreateCratelist(context),
      );
    }

    // type == albums or all, no filters
    return EmptyState.library(
      onAddAlbum: () => _showAddAlbumSubMenu(context),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Text(
                'Add to library',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: _menuIcon(Icons.camera_alt),
              title: const Text('Scan album'),
              subtitle: const Text(
                'Scan barcode or photograph album cover',
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/library/add/scan');
              },
            ),
            ListTile(
              leading: _menuIcon(Icons.search),
              title: const Text('Search album'),
              subtitle: const Text(
                'Search by artist, album, or catalog number',
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/library/add/search');
              },
            ),
            ListTile(
              leading: _menuIcon(Icons.queue_music),
              title: const Text('New cratelist'),
              subtitle: const Text(
                'Group records to play in order',
              ),
              onTap: () {
                Navigator.pop(context);
                _onCreateCratelist(context);
              },
            ),
            const SizedBox(height: Spacing.lg),
          ],
        ),
      ),
    );
  }

  void _showAddAlbumSubMenu(BuildContext context) {
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
              leading: _menuIcon(Icons.camera_alt),
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
              leading: _menuIcon(Icons.search),
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

  Widget _menuIcon(IconData icon) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: SaturdayColors.primaryDark),
    );
  }

  Future<void> _onCreateCratelist(BuildContext context) async {
    final created = await CreateCratelistSheet.show(context);
    if (created == null || !context.mounted) return;
    context.push('/library/cratelists/${created.id}');
  }

  Widget _buildFilterBar(
    BuildContext context,
    WidgetRef ref,
    LibraryFilterState filterState,
    LibraryViewMode viewMode,
  ) {
    return Row(
      children: [
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

  void _onAlbumTap(BuildContext context, LibraryAlbum album) {
    handleAlbumTap(context, ref, album.id);
  }

  void _onAlbumLongPress(
    BuildContext context,
    WidgetRef ref,
    LibraryAlbum album,
  ) {
    showAlbumQuickActions(context, ref, album);
  }

  void _onCratelistTap(BuildContext context, CratelistPreview preview) {
    context.push('/library/cratelists/${preview.cratelist.id}');
  }

  Widget _buildNoLibrariesState() {
    return const QuickStartScreen();
  }
}

/// Pins the filter bar at the top of the scroll view so the user can adjust
/// filters mid-scroll. The chips above can collapse, but the filter bar
/// stays visible.
class _FilterBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  _FilterBarHeaderDelegate({required this.child, required this.height});

  final Widget child;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(child: child),
          const Divider(height: 1),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_FilterBarHeaderDelegate oldDelegate) {
    return child != oldDelegate.child || height != oldDelegate.height;
  }
}
