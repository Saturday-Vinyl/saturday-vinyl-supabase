import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/repositories/album_repository.dart';

/// A horizontal scrolling bar with filter and sort chips.
///
/// Displays active filters and sort as chips, and provides a unified button
/// to open the sort & filter sheet.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.selectedGenres,
    required this.selectedDecades,
    required this.favoritesOnly,
    required this.currentSort,
    required this.isSortNonDefault,
    required this.onGenreRemoved,
    required this.onDecadeRemoved,
    required this.onFavoritesToggled,
    required this.onSortReset,
    required this.onClearAll,
    required this.onFilterTap,
    this.totalActiveCount = 0,
  });

  /// Currently selected genres.
  final Set<String> selectedGenres;

  /// Currently selected decades.
  final Set<String> selectedDecades;

  /// Whether favorites only filter is active.
  final bool favoritesOnly;

  /// The current sort option.
  final AlbumSortOption currentSort;

  /// Whether the sort differs from the default.
  final bool isSortNonDefault;

  /// Callback when a genre chip is removed.
  final void Function(String genre) onGenreRemoved;

  /// Callback when a decade chip is removed.
  final void Function(String decade) onDecadeRemoved;

  /// Callback when favorites filter is toggled.
  final VoidCallback onFavoritesToggled;

  /// Callback when sort is reset to default.
  final VoidCallback onSortReset;

  /// Callback to clear all filters and reset sort.
  final VoidCallback onClearAll;

  /// Callback when the filter button is tapped.
  final VoidCallback onFilterTap;

  /// Total count of active settings (filters + sort if non-default).
  final int totalActiveCount;

  @override
  Widget build(BuildContext context) {
    final hasActiveItems = selectedGenres.isNotEmpty ||
        selectedDecades.isNotEmpty ||
        favoritesOnly ||
        isSortNonDefault;

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // Sort & Filter button (icon only with badge)
          Padding(
            padding: const EdgeInsets.only(left: Spacing.md),
            child: _SortFilterButton(
              onTap: onFilterTap,
              activeCount: totalActiveCount,
            ),
          ),

          // Divider
          if (hasActiveItems)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Container(
                width: 1,
                height: 24,
                color: SaturdayColors.secondary.withValues(alpha: 0.3),
              ),
            ),

          // Sort and filter chips
          Expanded(
            child: hasActiveItems
                ? _buildChips(context)
                : const SizedBox.shrink(),
          ),

          // Clear all button
          if (hasActiveItems)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.md),
              child: TextButton(
                onPressed: onClearAll,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Clear'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChips(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      children: [
        // Sort chip (shown when non-default)
        if (isSortNonDefault)
          Padding(
            padding: const EdgeInsets.only(right: Spacing.sm),
            child: _SortChip(
              sortOption: currentSort,
              onDeleted: onSortReset,
            ),
          ),

        // Favorites chip
        if (favoritesOnly)
          Padding(
            padding: const EdgeInsets.only(right: Spacing.sm),
            child: _FilterChip(
              label: 'Favorites',
              icon: Icons.favorite,
              onDeleted: onFavoritesToggled,
            ),
          ),

        // Genre chips
        ...selectedGenres.map((genre) => Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: _FilterChip(
                label: genre,
                onDeleted: () => onGenreRemoved(genre),
              ),
            )),

        // Decade chips
        ...selectedDecades.map((decade) => Padding(
              padding: const EdgeInsets.only(right: Spacing.sm),
              child: _FilterChip(
                label: '${decade}s',
                onDeleted: () => onDecadeRemoved(decade),
              ),
            )),
      ],
    );
  }
}

/// A unified sort & filter button with badge showing active count.
class _SortFilterButton extends StatelessWidget {
  const _SortFilterButton({
    required this.onTap,
    required this.activeCount,
  });

  final VoidCallback onTap;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smallRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          child: Badge(
            isLabelVisible: activeCount > 0,
            label: Text(activeCount.toString()),
            child: const Icon(Icons.tune, size: 22),
          ),
        ),
      ),
    );
  }
}

/// A chip displaying the current sort option with delete capability.
class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.sortOption,
    required this.onDeleted,
  });

  final AlbumSortOption sortOption;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        _isAscending(sortOption) ? Icons.arrow_upward : Icons.arrow_downward,
        size: 16,
        color: SaturdayColors.primaryDark,
      ),
      label: Text(_getSortLabel(sortOption)),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onDeleted,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.only(left: 2, right: 4),
      backgroundColor: SaturdayColors.primaryDark.withValues(alpha: 0.1),
    );
  }

  /// Get the display label for a sort option.
  String _getSortLabel(AlbumSortOption sort) {
    switch (sort) {
      case AlbumSortOption.artistAsc:
        return 'Artist A-Z';
      case AlbumSortOption.artistDesc:
        return 'Artist Z-A';
      case AlbumSortOption.titleAsc:
        return 'Title A-Z';
      case AlbumSortOption.titleDesc:
        return 'Title Z-A';
      case AlbumSortOption.dateAddedAsc:
        return 'Oldest Added';
      case AlbumSortOption.dateAddedDesc:
        return 'Recently Added';
      case AlbumSortOption.yearAsc:
        return 'Oldest Release';
      case AlbumSortOption.yearDesc:
        return 'Newest Release';
    }
  }

  /// Check if the sort option is ascending.
  bool _isAscending(AlbumSortOption sort) {
    switch (sort) {
      case AlbumSortOption.artistAsc:
      case AlbumSortOption.titleAsc:
      case AlbumSortOption.dateAddedAsc:
      case AlbumSortOption.yearAsc:
        return true;
      case AlbumSortOption.artistDesc:
      case AlbumSortOption.titleDesc:
      case AlbumSortOption.dateAddedDesc:
      case AlbumSortOption.yearDesc:
        return false;
    }
  }
}

/// A chip displaying an active filter with delete capability.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.onDeleted,
    this.icon,
  });

  final String label;
  final VoidCallback onDeleted;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: onDeleted,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      labelPadding: const EdgeInsets.only(left: 4),
    );
  }
}

/// A compact filter indicator showing active filter count.
///
/// Use this when space is limited and you just need to show that filters are active.
class FilterIndicator extends StatelessWidget {
  const FilterIndicator({
    super.key,
    required this.activeCount,
    required this.onTap,
  });

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: activeCount > 0,
        label: Text(activeCount.toString()),
        child: const Icon(Icons.filter_list),
      ),
      tooltip: activeCount > 0
          ? '$activeCount filter${activeCount == 1 ? '' : 's'} active'
          : 'Filter',
    );
  }
}
