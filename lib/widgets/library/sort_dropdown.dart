import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/repositories/album_repository.dart';

/// A dropdown button for selecting album sort options.
///
/// Displays the current sort option and opens a menu with all available options.
class SortDropdown extends StatelessWidget {
  const SortDropdown({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
  });

  /// The currently selected sort option.
  final AlbumSortOption currentSort;

  /// Callback when a new sort option is selected.
  final void Function(AlbumSortOption) onSortChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<AlbumSortOption>(
      initialValue: currentSort,
      onSelected: onSortChanged,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mediumRadius,
      ),
      itemBuilder: (context) => _buildMenuItems(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sort, size: 20),
            const SizedBox(width: Spacing.xs),
            Text(
              _getSortLabel(currentSort),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(width: Spacing.xs),
            Icon(
              _isAscending(currentSort) ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
              color: SaturdayColors.secondary,
            ),
          ],
        ),
      ),
    );
  }

  List<PopupMenuEntry<AlbumSortOption>> _buildMenuItems(BuildContext context) {
    return [
      _buildSectionHeader(context, 'Artist'),
      _buildMenuItem(context, AlbumSortOption.artistAsc, 'A → Z'),
      _buildMenuItem(context, AlbumSortOption.artistDesc, 'Z → A'),
      const PopupMenuDivider(),
      _buildSectionHeader(context, 'Title'),
      _buildMenuItem(context, AlbumSortOption.titleAsc, 'A → Z'),
      _buildMenuItem(context, AlbumSortOption.titleDesc, 'Z → A'),
      const PopupMenuDivider(),
      _buildSectionHeader(context, 'Date Added'),
      _buildMenuItem(context, AlbumSortOption.dateAddedDesc, 'Newest First'),
      _buildMenuItem(context, AlbumSortOption.dateAddedAsc, 'Oldest First'),
      const PopupMenuDivider(),
      _buildSectionHeader(context, 'Release Year'),
      _buildMenuItem(context, AlbumSortOption.yearDesc, 'Newest First'),
      _buildMenuItem(context, AlbumSortOption.yearAsc, 'Oldest First'),
    ];
  }

  PopupMenuItem<AlbumSortOption> _buildSectionHeader(
    BuildContext context,
    String title,
  ) {
    return PopupMenuItem<AlbumSortOption>(
      enabled: false,
      height: 32,
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: SaturdayColors.secondary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  PopupMenuItem<AlbumSortOption> _buildMenuItem(
    BuildContext context,
    AlbumSortOption option,
    String label,
  ) {
    final isSelected = currentSort == option;

    return PopupMenuItem<AlbumSortOption>(
      value: option,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: isSelected
                ? Icon(
                    Icons.check,
                    size: 18,
                    color: SaturdayColors.primaryDark,
                  )
                : null,
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  /// Get the display label for a sort option.
  String _getSortLabel(AlbumSortOption sort) {
    switch (sort) {
      case AlbumSortOption.artistAsc:
      case AlbumSortOption.artistDesc:
        return 'Artist';
      case AlbumSortOption.titleAsc:
      case AlbumSortOption.titleDesc:
        return 'Title';
      case AlbumSortOption.dateAddedAsc:
      case AlbumSortOption.dateAddedDesc:
        return 'Date Added';
      case AlbumSortOption.yearAsc:
      case AlbumSortOption.yearDesc:
        return 'Year';
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

/// A compact sort button that shows current sort and direction.
///
/// Use this in tight spaces like app bars.
class SortButton extends StatelessWidget {
  const SortButton({
    super.key,
    required this.currentSort,
    required this.onTap,
  });

  /// The currently selected sort option.
  final AlbumSortOption currentSort;

  /// Callback when the button is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.sort, size: 20),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_getSortLabel(currentSort)),
          const SizedBox(width: 2),
          Icon(
            _isAscending(currentSort) ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14,
          ),
        ],
      ),
    );
  }

  String _getSortLabel(AlbumSortOption sort) {
    switch (sort) {
      case AlbumSortOption.artistAsc:
      case AlbumSortOption.artistDesc:
        return 'Artist';
      case AlbumSortOption.titleAsc:
      case AlbumSortOption.titleDesc:
        return 'Title';
      case AlbumSortOption.dateAddedAsc:
      case AlbumSortOption.dateAddedDesc:
        return 'Date Added';
      case AlbumSortOption.yearAsc:
      case AlbumSortOption.yearDesc:
        return 'Year';
    }
  }

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
