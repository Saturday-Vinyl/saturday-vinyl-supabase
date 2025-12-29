import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/repositories/album_repository.dart';

/// A bottom sheet for configuring library filters.
///
/// Provides full filter options including genres, decades, and favorites.
class FilterBottomSheet extends StatefulWidget {
  const FilterBottomSheet({
    super.key,
    required this.selectedGenres,
    required this.selectedDecades,
    required this.favoritesOnly,
    required this.availableGenres,
    required this.availableDecades,
    required this.currentSort,
    required this.onApply,
  });

  /// Currently selected genres.
  final Set<String> selectedGenres;

  /// Currently selected decades.
  final Set<String> selectedDecades;

  /// Whether favorites only filter is active.
  final bool favoritesOnly;

  /// Available genres to filter by.
  final List<String> availableGenres;

  /// Available decades to filter by.
  final List<String> availableDecades;

  /// Current sort option.
  final AlbumSortOption currentSort;

  /// Callback when filters are applied.
  final void Function({
    required Set<String> genres,
    required Set<String> decades,
    required bool favoritesOnly,
    required AlbumSortOption sort,
  }) onApply;

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late Set<String> _selectedGenres;
  late Set<String> _selectedDecades;
  late bool _favoritesOnly;
  late AlbumSortOption _currentSort;

  @override
  void initState() {
    super.initState();
    _selectedGenres = Set.from(widget.selectedGenres);
    _selectedDecades = Set.from(widget.selectedDecades);
    _favoritesOnly = widget.favoritesOnly;
    _currentSort = widget.currentSort;
  }

  bool get _hasFilters =>
      _selectedGenres.isNotEmpty ||
      _selectedDecades.isNotEmpty ||
      _favoritesOnly;

  void _clearFilters() {
    setState(() {
      _selectedGenres = {};
      _selectedDecades = {};
      _favoritesOnly = false;
    });
  }

  void _apply() {
    widget.onApply(
      genres: _selectedGenres,
      decades: _selectedDecades,
      favoritesOnly: _favoritesOnly,
      sort: _currentSort,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Header
            _buildHeader(context),
            const Divider(height: 1),

            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                children: [
                  // Sort section
                  _buildSortSection(context),
                  const SizedBox(height: Spacing.lg),
                  const Divider(),
                  const SizedBox(height: Spacing.lg),

                  // Favorites toggle
                  _buildFavoritesToggle(context),
                  const SizedBox(height: Spacing.lg),

                  // Genres section
                  if (widget.availableGenres.isNotEmpty) ...[
                    _buildGenresSection(context),
                    const SizedBox(height: Spacing.lg),
                  ],

                  // Decades section
                  if (widget.availableDecades.isNotEmpty) ...[
                    _buildDecadesSection(context),
                    const SizedBox(height: Spacing.lg),
                  ],
                ],
              ),
            ),

            // Footer
            _buildFooter(context),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.md,
      ),
      child: Row(
        children: [
          Text(
            'Sort & Filter',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          if (_hasFilters)
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear All'),
            ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildSortSection(BuildContext context) {
    return Padding(
      padding: Spacing.pageHorizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sort by',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              _SortChip(
                label: 'Artist A-Z',
                isSelected: _currentSort == AlbumSortOption.artistAsc,
                onSelected: () =>
                    setState(() => _currentSort = AlbumSortOption.artistAsc),
              ),
              _SortChip(
                label: 'Artist Z-A',
                isSelected: _currentSort == AlbumSortOption.artistDesc,
                onSelected: () =>
                    setState(() => _currentSort = AlbumSortOption.artistDesc),
              ),
              _SortChip(
                label: 'Title A-Z',
                isSelected: _currentSort == AlbumSortOption.titleAsc,
                onSelected: () =>
                    setState(() => _currentSort = AlbumSortOption.titleAsc),
              ),
              _SortChip(
                label: 'Title Z-A',
                isSelected: _currentSort == AlbumSortOption.titleDesc,
                onSelected: () =>
                    setState(() => _currentSort = AlbumSortOption.titleDesc),
              ),
              _SortChip(
                label: 'Recently Added',
                isSelected: _currentSort == AlbumSortOption.dateAddedDesc,
                onSelected: () =>
                    setState(() => _currentSort = AlbumSortOption.dateAddedDesc),
              ),
              _SortChip(
                label: 'Oldest Added',
                isSelected: _currentSort == AlbumSortOption.dateAddedAsc,
                onSelected: () =>
                    setState(() => _currentSort = AlbumSortOption.dateAddedAsc),
              ),
              _SortChip(
                label: 'Newest Release',
                isSelected: _currentSort == AlbumSortOption.yearDesc,
                onSelected: () =>
                    setState(() => _currentSort = AlbumSortOption.yearDesc),
              ),
              _SortChip(
                label: 'Oldest Release',
                isSelected: _currentSort == AlbumSortOption.yearAsc,
                onSelected: () =>
                    setState(() => _currentSort = AlbumSortOption.yearAsc),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritesToggle(BuildContext context) {
    return Padding(
      padding: Spacing.pageHorizontal,
      child: SwitchListTile(
        title: const Text('Favorites only'),
        subtitle: const Text('Show only albums marked as favorites'),
        secondary: Icon(
          _favoritesOnly ? Icons.favorite : Icons.favorite_border,
          color: _favoritesOnly ? SaturdayColors.error : null,
        ),
        value: _favoritesOnly,
        onChanged: (value) => setState(() => _favoritesOnly = value),
        contentPadding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildGenresSection(BuildContext context) {
    return Padding(
      padding: Spacing.pageHorizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Genres',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_selectedGenres.isNotEmpty) ...[
                const SizedBox(width: Spacing.sm),
                Text(
                  '(${_selectedGenres.length} selected)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: widget.availableGenres.map((genre) {
              final isSelected = _selectedGenres.contains(genre);
              return FilterChip(
                label: Text(genre),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedGenres.add(genre);
                    } else {
                      _selectedGenres.remove(genre);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDecadesSection(BuildContext context) {
    return Padding(
      padding: Spacing.pageHorizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Decades',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_selectedDecades.isNotEmpty) ...[
                const SizedBox(width: Spacing.sm),
                Text(
                  '(${_selectedDecades.length} selected)',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
          const SizedBox(height: Spacing.md),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: widget.availableDecades.map((decade) {
              final isSelected = _selectedDecades.contains(decade);
              return FilterChip(
                label: Text('${decade}s'),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedDecades.add(decade);
                    } else {
                      _selectedDecades.remove(decade);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        top: Spacing.md,
        bottom: Spacing.md + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: ElevatedButton(
              onPressed: _apply,
              child: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A chip for selecting sort options.
class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.isSelected,
    required this.onSelected,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
    );
  }
}

/// Shows the filter bottom sheet.
Future<void> showFilterBottomSheet({
  required BuildContext context,
  required Set<String> selectedGenres,
  required Set<String> selectedDecades,
  required bool favoritesOnly,
  required List<String> availableGenres,
  required List<String> availableDecades,
  required AlbumSortOption currentSort,
  required void Function({
    required Set<String> genres,
    required Set<String> decades,
    required bool favoritesOnly,
    required AlbumSortOption sort,
  }) onApply,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FilterBottomSheet(
      selectedGenres: selectedGenres,
      selectedDecades: selectedDecades,
      favoritesOnly: favoritesOnly,
      availableGenres: availableGenres,
      availableDecades: availableDecades,
      currentSort: currentSort,
      onApply: onApply,
    ),
  );
}
