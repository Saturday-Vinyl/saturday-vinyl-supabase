import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/add_album_provider.dart';
import 'package:saturday_consumer_app/services/discogs_service.dart';

/// Screen for searching Discogs to find albums.
class DiscogsSearchScreen extends ConsumerStatefulWidget {
  const DiscogsSearchScreen({super.key});

  @override
  ConsumerState<DiscogsSearchScreen> createState() =>
      _DiscogsSearchScreenState();
}

class _DiscogsSearchScreenState extends ConsumerState<DiscogsSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(addAlbumProvider.notifier).search(query);
    });
  }

  void _onResultTap(DiscogsSearchResult result) async {
    await ref.read(addAlbumProvider.notifier).selectFromSearchResult(result);
    if (mounted) {
      final selectedAlbum = ref.read(selectedAlbumProvider);
      if (selectedAlbum != null) {
        context.push('/library/add/confirm');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(addAlbumProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Discogs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(addAlbumProvider.notifier).reset();
            context.pop();
          },
        ),
      ),
      body: Column(
        children: [
          // Search field
          Padding(
            padding: Spacing.pagePadding,
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Search by artist, album, or catalog #',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref.read(addAlbumProvider.notifier).search('');
                        },
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (query) {
                _debounce?.cancel();
                ref.read(addAlbumProvider.notifier).search(query);
              },
            ),
          ),

          // Error message
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Container(
                padding: const EdgeInsets.all(Spacing.md),
                decoration: BoxDecoration(
                  color: SaturdayColors.error.withValues(alpha: 0.1),
                  borderRadius: AppRadius.mediumRadius,
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: SaturdayColors.error),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        state.error!,
                        style: TextStyle(color: SaturdayColors.error),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        ref.read(addAlbumProvider.notifier).clearError();
                      },
                    ),
                  ],
                ),
              ),
            ),

          // Results
          Expanded(
            child: _buildResults(state),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(AddAlbumState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.isEmpty) {
      return _buildEmptyState();
    }

    if (state.searchResults.isEmpty) {
      return _buildNoResults();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: Spacing.md),
      itemCount: state.searchResults.length,
      itemBuilder: (context, index) {
        final result = state.searchResults[index];
        return _SearchResultTile(
          result: result,
          onTap: () => _onResultTap(result),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Search for vinyl records',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Enter an artist name, album title, or catalog number to find records on Discogs',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.album_outlined,
              size: 64,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'No results found',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Try a different search term or check your spelling',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single search result tile.
class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.onTap,
  });

  final DiscogsSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      leading: ClipRRect(
        borderRadius: AppRadius.smallRadius,
        child: SizedBox(
          width: 56,
          height: 56,
          child: result.coverImageUrl != null
              ? CachedNetworkImage(
                  imageUrl: result.coverImageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => _buildPlaceholder(),
                  errorWidget: (context, url, error) => _buildPlaceholder(),
                )
              : _buildPlaceholder(),
        ),
      ),
      title: Text(
        result.albumTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: SaturdayColors.secondary),
          ),
          if (result.year != null || result.formats.isNotEmpty)
            Text(
              [
                if (result.year != null) result.year,
                if (result.formats.isNotEmpty) result.formats.first,
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
            ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Icon(
        Icons.album,
        color: SaturdayColors.secondary,
      ),
    );
  }
}
