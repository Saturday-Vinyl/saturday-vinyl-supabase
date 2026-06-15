import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
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
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/foundation/saturday_skeleton.dart';
import 'package:saturday_consumer_app/widgets/library/album_quick_actions.dart';
import 'package:saturday_consumer_app/widgets/library/collection_grid.dart';
import 'package:saturday_consumer_app/widgets/library/collection_list.dart';
import 'package:saturday_consumer_app/widgets/library/collection_type_chips.dart';
import 'package:saturday_consumer_app/widgets/library/filter_bar.dart';
import 'package:saturday_consumer_app/widgets/library/filter_bottom_sheet.dart';
import 'package:saturday_consumer_app/widgets/library/view_toggle.dart';

/// Library (collection) screen — unified browse view for the listener's
/// vinyl collection. Albums and cratelists share a single grid/list; type
/// chips narrow to one or the other.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const double _chipsHeight = 56;
  static const double _filterBarHeight = 56;

  @override
  Widget build(BuildContext context) {
    final librariesAsync = ref.watch(userLibrariesProvider);

    return librariesAsync.when(
      data: (libraries) {
        if (libraries.isEmpty) return const QuickStartScreen();
        return _buildLibraryContent(context);
      },
      loading: () => Scaffold(
        appBar: const SaturdayAppBar(
          showLibrarySwitcher: true,
          showSearch: true,
        ),
        body: const _CollectionSkeletonGrid(),
      ),
      error: (error, _) => Scaffold(
        appBar: const SaturdayAppBar(
          showLibrarySwitcher: true,
          showSearch: true,
        ),
        body: _InlineError(
          message: "The collection isn't loading.",
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
    final colors = SaturdayColorTokens.of(context);

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
            colors,
          ),
          loading: () => const _CollectionSkeletonGrid(),
          error: (error, _) => _InlineError(
            message: "The collection isn't loading.",
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
    SaturdayColorTokens colors,
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
          SliverAppBar(
            primary: false,
            automaticallyImplyLeading: false,
            floating: true,
            snap: true,
            pinned: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: colors.paper,
            surfaceTintColor: Colors.transparent,
            toolbarHeight: _chipsHeight,
            titleSpacing: 0,
            title: const CollectionTypeChips(),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _FilterBarHeaderDelegate(
              child: _buildFilterBar(context, ref, filterState, viewMode),
              height: _filterBarHeight,
              colors: colors,
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
              onCratelistTap: (preview) => _onCratelistTap(context, preview),
            )
          else
            SliverCollectionList(
              items: items,
              onAlbumTap: (album) => _onAlbumTap(context, album),
              onAlbumLongPress: (album) =>
                  _onAlbumLongPress(context, ref, album),
              onCratelistTap: (preview) => _onCratelistTap(context, preview),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyForState(
    BuildContext context,
    CollectionTypeFilter type,
    bool hasFilters,
  ) {
    if (hasFilters && type != CollectionTypeFilter.cratelists) {
      return _EmptyPanel(
        title: 'No matching albums',
        message: 'Adjust the filters to see more.',
        actionLabel: 'Clear filters',
        onAction: () =>
            ref.read(libraryFilterProvider.notifier).clearFilters(),
      );
    }

    if (type == CollectionTypeFilter.cratelists) {
      return _EmptyPanel(
        title: 'No cratelists yet',
        message:
            'Group records from the collection into ordered crates to play through.',
        actionLabel: 'New cratelist',
        onAction: () => _onCreateCratelist(context),
      );
    }

    return _EmptyPanel(
      title: 'Nothing in the collection yet',
      message: 'Add a record to get started.',
      actionLabel: 'Add record',
      onAction: () => _showAddAlbumSubMenu(context),
    );
  }

  void _showAddMenu(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(SaturdaySpace.space4),
              child: Text(
                'Add to collection',
                style: SaturdayType.section.copyWith(
                  fontSize: 22,
                  color: colors.ink,
                ),
              ),
            ),
            ListTile(
              leading: _MenuIcon(icon: Icons.camera_alt, colors: colors),
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
              leading: _MenuIcon(icon: Icons.search, colors: colors),
              title: const Text('Search album'),
              subtitle: const Text(
                'Search by artist, album, or catalog number',
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/search');
              },
            ),
            ListTile(
              leading: _MenuIcon(icon: Icons.queue_music, colors: colors),
              title: const Text('New cratelist'),
              subtitle: const Text(
                'Group records to play in sequence',
              ),
              onTap: () {
                Navigator.pop(context);
                _onCreateCratelist(context);
              },
            ),
            const SizedBox(height: SaturdaySpace.space4),
          ],
        ),
      ),
    );
  }

  void _showAddAlbumSubMenu(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(SaturdaySpace.space4),
              child: Text(
                'Add a record',
                style: SaturdayType.section.copyWith(
                  fontSize: 22,
                  color: colors.ink,
                ),
              ),
            ),
            ListTile(
              leading: _MenuIcon(icon: Icons.camera_alt, colors: colors),
              title: const Text('Use camera'),
              subtitle: const Text(
                'Scan barcode or photograph album cover',
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/library/add/scan');
              },
            ),
            ListTile(
              leading: _MenuIcon(icon: Icons.search, colors: colors),
              title: const Text('Manual entry'),
              subtitle: const Text(
                'Search by artist, album, or catalog number',
              ),
              onTap: () {
                Navigator.pop(context);
                context.push('/search');
              },
            ),
            const SizedBox(height: SaturdaySpace.space4),
          ],
        ),
      ),
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
        const Padding(
          padding: EdgeInsets.only(right: SaturdaySpace.space2),
          child: _ViewToggleWrapper(),
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
}

// =============================================================================
// Filter-bar header — pinned across scrolls so filters stay reachable.
// =============================================================================

class _FilterBarHeaderDelegate extends SliverPersistentHeaderDelegate {
  _FilterBarHeaderDelegate({
    required this.child,
    required this.height,
    required this.colors,
  });

  final Widget child;
  final double height;
  final SaturdayColorTokens colors;

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
      color: colors.paper,
      elevation: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(child: child),
          Divider(height: 1, thickness: 1, color: colors.borderQuiet),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_FilterBarHeaderDelegate oldDelegate) {
    return child != oldDelegate.child ||
        height != oldDelegate.height ||
        colors != oldDelegate.colors;
  }
}

// =============================================================================
// View toggle — small wrapper so the riverpod read sits next to the widget.
// =============================================================================

class _ViewToggleWrapper extends ConsumerWidget {
  const _ViewToggleWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(libraryViewModeProvider);
    return ViewToggleIconButton(
      currentMode: viewMode,
      onModeChanged: (mode) {
        ref.read(libraryViewModeProvider.notifier).setViewMode(mode);
      },
    );
  }
}

// =============================================================================
// Inline error — factual sentence, retry tile, no apology language.
// =============================================================================

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SaturdaySpace.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: SaturdayType.body.copyWith(color: colors.ink),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SaturdaySpace.space4),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Empty panel — title + factual message + single action.
// =============================================================================

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SaturdaySpace.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: SaturdayType.section.copyWith(
                fontSize: 22,
                color: colors.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SaturdaySpace.space3),
            Text(
              message,
              style: SaturdayType.body.copyWith(color: colors.inkSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: SaturdaySpace.space6),
            ElevatedButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Skeleton grid — held layout while the collection loads.
// =============================================================================

class _CollectionSkeletonGrid extends StatelessWidget {
  const _CollectionSkeletonGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 400
            ? 2
            : constraints.maxWidth < 600
                ? 3
                : constraints.maxWidth < 900
                    ? 4
                    : 5;

        return GridView.builder(
          padding: const EdgeInsets.all(SaturdaySpace.space4),
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: SaturdaySpace.space4,
            crossAxisSpacing: SaturdaySpace.space4,
            childAspectRatio: _aspect(constraints.maxWidth, crossAxisCount),
          ),
          itemCount: crossAxisCount * 4,
          itemBuilder: (context, index) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AspectRatio(
                  aspectRatio: 1,
                  child: SaturdaySkeleton.square(
                    size: double.infinity,
                    radius: 8,
                  ),
                ),
                const SizedBox(height: SaturdaySpace.space2),
                SaturdaySkeleton.text(lines: 2, fontSize: 12),
              ],
            );
          },
        );
      },
    );
  }

  double _aspect(double width, int crossAxisCount) {
    final spacing = SaturdaySpace.space4 * (crossAxisCount + 1);
    final availableWidth = width - spacing;
    final itemWidth = availableWidth / crossAxisCount;
    const textHeight = 60.0;
    final itemHeight = itemWidth + textHeight;
    return itemWidth / itemHeight;
  }
}

// =============================================================================
// Menu icon — token-driven leading container in bottom-sheet menus.
// =============================================================================

class _MenuIcon extends StatelessWidget {
  const _MenuIcon({required this.icon, required this.colors});

  final IconData icon;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.paperElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderQuiet),
      ),
      child: Icon(icon, color: colors.ink),
    );
  }
}
