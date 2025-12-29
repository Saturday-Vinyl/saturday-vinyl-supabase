import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// Enum for library view mode.
enum LibraryViewMode {
  grid,
  list,
}

/// A toggle button to switch between grid and list view modes.
///
/// Displays as a segmented button with grid and list icons.
class ViewToggle extends StatelessWidget {
  const ViewToggle({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  /// The current view mode.
  final LibraryViewMode currentMode;

  /// Callback when the view mode changes.
  final void Function(LibraryViewMode mode) onModeChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<LibraryViewMode>(
      segments: const [
        ButtonSegment<LibraryViewMode>(
          value: LibraryViewMode.grid,
          icon: Icon(Icons.grid_view, size: 20),
        ),
        ButtonSegment<LibraryViewMode>(
          value: LibraryViewMode.list,
          icon: Icon(Icons.view_list, size: 20),
        ),
      ],
      selected: {currentMode},
      onSelectionChanged: (Set<LibraryViewMode> newSelection) {
        if (newSelection.isNotEmpty) {
          onModeChanged(newSelection.first);
        }
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      showSelectedIcon: false,
    );
  }
}

/// A simpler icon button version of the view toggle.
///
/// Shows a single icon that toggles between grid and list views on tap.
class ViewToggleIconButton extends StatelessWidget {
  const ViewToggleIconButton({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  /// The current view mode.
  final LibraryViewMode currentMode;

  /// Callback when the view mode changes.
  final void Function(LibraryViewMode mode) onModeChanged;

  @override
  Widget build(BuildContext context) {
    final isGrid = currentMode == LibraryViewMode.grid;

    return IconButton(
      onPressed: () {
        onModeChanged(isGrid ? LibraryViewMode.list : LibraryViewMode.grid);
      },
      icon: Icon(
        isGrid ? Icons.view_list : Icons.grid_view,
      ),
      tooltip: isGrid ? 'Switch to list view' : 'Switch to grid view',
      style: IconButton.styleFrom(
        foregroundColor: SaturdayColors.primaryDark,
      ),
    );
  }
}
