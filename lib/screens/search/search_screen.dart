import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/add_album_provider.dart';
import 'package:saturday_consumer_app/providers/search_provider.dart';
import 'package:saturday_consumer_app/services/discogs_service.dart';
import 'package:saturday_consumer_app/widgets/common/empty_state.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
import 'package:saturday_consumer_app/widgets/search/search_result_item.dart';
import 'package:saturday_consumer_app/widgets/search/search_section.dart';

/// Global search screen accessible from any tab.
///
/// Searches across:
/// - User's library albums
/// - Discogs catalog (for adding new albums)
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _searchController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _focusNode = FocusNode();

    // Auto-focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final recentSearches = ref.watch(recentSearchesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: _buildSearchField(context),
        titleSpacing: 0,
        actions: [
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearSearch,
            ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(context, searchState, recentSearches),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return TextField(
      controller: _searchController,
      focusNode: _focusNode,
      decoration: InputDecoration(
        hintText: 'Search albums, artists...',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
      ),
      textInputAction: TextInputAction.search,
      onChanged: (query) {
        ref.read(searchProvider.notifier).setQuery(query);
      },
      onSubmitted: (query) {
        if (query.trim().isNotEmpty) {
          addToRecentSearches(ref, query);
        }
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    SearchState searchState,
    List<String> recentSearches,
  ) {
    // Show error
    if (searchState.error != null) {
      return ErrorDisplay.fullScreen(
        message: searchState.error!,
        onRetry: () {
          ref.read(searchProvider.notifier).setQuery(searchState.query);
        },
      );
    }

    // Show loading
    if (searchState.isSearching) {
      return const LoadingIndicator.medium(message: 'Searching...');
    }

    // Show empty state for no results
    if (searchState.isEmpty) {
      return EmptyState.noSearchResults(
        query: searchState.query,
        onClearSearch: _clearSearch,
      );
    }

    // Show results if we have them
    if (searchState.hasSearched && searchState.hasResults) {
      return _buildResults(context, searchState);
    }

    // Show initial state (recent searches or prompt)
    return _buildInitialState(context, recentSearches);
  }

  Widget _buildInitialState(BuildContext context, List<String> recentSearches) {
    return SingleChildScrollView(
      padding: Spacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent searches
          if (recentSearches.isNotEmpty) ...[
            Text(
              'Recent Searches',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.md),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: recentSearches
                  .map((search) => ActionChip(
                        label: Text(search),
                        onPressed: () {
                          _searchController.text = search;
                          ref.read(searchProvider.notifier).setQuery(search);
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: Spacing.xxl),
          ],

          // Search tips
          Text(
            'Search Tips',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.md),
          _buildSearchTip(
            context,
            icon: Icons.album,
            title: 'Search your library',
            description: 'Find albums by title, artist, or genre',
          ),
          const SizedBox(height: Spacing.md),
          _buildSearchTip(
            context,
            icon: Icons.add_circle_outline,
            title: 'Add from Discogs',
            description: 'Search millions of releases to add to your collection',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchTip(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
            borderRadius: AppRadius.smallRadius,
          ),
          child: Icon(
            icon,
            color: SaturdayColors.primaryDark,
            size: AppIconSizes.md,
          ),
        ),
        const SizedBox(width: Spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondary,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResults(BuildContext context, SearchState searchState) {
    return ListView(
      children: [
        // Library results
        if (searchState.libraryResults.isNotEmpty)
          SearchSection(
            title: 'In Your Library',
            icon: Icons.library_music,
            resultCount: searchState.libraryResults.length,
            maxItems: 5,
            children: searchState.libraryResults
                .map((album) => LibrarySearchResultItem(
                      libraryAlbum: album,
                      onTap: () => _openAlbumDetail(album.id),
                    ))
                .toList(),
          ),

        if (searchState.libraryResults.isNotEmpty &&
            searchState.discogsResults.isNotEmpty)
          const Divider(height: Spacing.xxl),

        // Discogs results
        if (searchState.discogsResults.isNotEmpty)
          SearchSection(
            title: 'Add from Discogs',
            icon: Icons.add_circle_outline,
            resultCount: searchState.discogsResults.length,
            children: searchState.discogsResults
                .map((result) => _DiscogsResultWithState(
                      result: result,
                      onTap: () => _viewDiscogsResult(result),
                      onAdd: () => _addDiscogsAlbum(result),
                    ))
                .toList(),
          ),

        const SizedBox(height: Spacing.xxl),
      ],
    );
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchProvider.notifier).clear();
    _focusNode.requestFocus();
  }

  void _openAlbumDetail(String albumId) {
    context.push('/library/album/$albumId');
  }

  void _viewDiscogsResult(DiscogsSearchResult result) {
    // Set as selected album and navigate to confirm screen
    ref.read(addAlbumProvider.notifier).selectFromSearchResult(result);
    context.push('/library/add/confirm');
  }

  void _addDiscogsAlbum(DiscogsSearchResult result) {
    // Set as selected album and navigate to confirm screen
    ref.read(addAlbumProvider.notifier).selectFromSearchResult(result);
    context.push('/library/add/confirm');
  }
}

/// Discogs result item with loading state for add action.
class _DiscogsResultWithState extends ConsumerWidget {
  const _DiscogsResultWithState({
    required this.result,
    required this.onTap,
    required this.onAdd,
  });

  final DiscogsSearchResult result;
  final VoidCallback onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addState = ref.watch(addAlbumProvider);
    // Check if we're loading this specific result
    final isAdding = addState.isLoading;

    return DiscogsSearchResultItem(
      result: result,
      onTap: onTap,
      onAdd: onAdd,
      isAdding: isAdding,
    );
  }
}
