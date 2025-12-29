import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A horizontal scrolling bar with filter chips.
///
/// Displays active filters as chips and provides a filter button to open
/// the full filter sheet.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.selectedGenres,
    required this.selectedDecades,
    required this.favoritesOnly,
    required this.onGenreRemoved,
    required this.onDecadeRemoved,
    required this.onFavoritesToggled,
    required this.onClearAll,
    required this.onFilterTap,
    this.activeFilterCount = 0,
  });

  /// Currently selected genres.
  final Set<String> selectedGenres;

  /// Currently selected decades.
  final Set<String> selectedDecades;

  /// Whether favorites only filter is active.
  final bool favoritesOnly;

  /// Callback when a genre chip is removed.
  final void Function(String genre) onGenreRemoved;

  /// Callback when a decade chip is removed.
  final void Function(String decade) onDecadeRemoved;

  /// Callback when favorites filter is toggled.
  final VoidCallback onFavoritesToggled;

  /// Callback to clear all filters.
  final VoidCallback onClearAll;

  /// Callback when the filter button is tapped.
  final VoidCallback onFilterTap;

  /// Count of active filters (for badge).
  final int activeFilterCount;

  @override
  Widget build(BuildContext context) {
    final hasFilters = selectedGenres.isNotEmpty ||
        selectedDecades.isNotEmpty ||
        favoritesOnly;

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          // Filter button
          Padding(
            padding: const EdgeInsets.only(left: Spacing.lg),
            child: _FilterButton(
              onTap: onFilterTap,
              activeCount: activeFilterCount,
            ),
          ),

          // Divider
          if (hasFilters)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
              child: Container(
                width: 1,
                height: 24,
                color: SaturdayColors.secondary.withValues(alpha: 0.3),
              ),
            ),

          // Filter chips
          Expanded(
            child: hasFilters
                ? _buildFilterChips(context)
                : const SizedBox.shrink(),
          ),

          // Clear all button
          if (hasFilters)
            Padding(
              padding: const EdgeInsets.only(right: Spacing.lg),
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

  Widget _buildFilterChips(BuildContext context) {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      children: [
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

/// A filter button with optional badge showing active filter count.
class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.onTap,
    required this.activeCount,
  });

  final VoidCallback onTap;
  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smallRadius,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: activeCount > 0,
              label: Text(activeCount.toString()),
              child: const Icon(Icons.filter_list, size: 22),
            ),
            const SizedBox(width: Spacing.xs),
            const Text('Filter'),
          ],
        ),
      ),
    );
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
