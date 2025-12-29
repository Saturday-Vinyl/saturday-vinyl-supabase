import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saturday_consumer_app/widgets/library/view_toggle.dart';

/// Key for storing view mode preference.
const String _viewModeKey = 'library_view_mode';

/// Provider for SharedPreferences instance.
///
/// Must be overridden in main.dart with the actual instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main.dart',
  );
});

/// StateNotifier for managing library view mode with persistence.
class LibraryViewNotifier extends StateNotifier<LibraryViewMode> {
  LibraryViewNotifier(this._prefs) : super(_loadInitialMode(_prefs));

  final SharedPreferences _prefs;

  /// Load the initial view mode from preferences.
  static LibraryViewMode _loadInitialMode(SharedPreferences prefs) {
    final storedValue = prefs.getString(_viewModeKey);
    if (storedValue == 'list') {
      return LibraryViewMode.list;
    }
    return LibraryViewMode.grid; // Default to grid
  }

  /// Set the view mode and persist it.
  Future<void> setViewMode(LibraryViewMode mode) async {
    state = mode;
    await _prefs.setString(_viewModeKey, mode.name);
  }

  /// Toggle between grid and list modes.
  Future<void> toggle() async {
    if (state == LibraryViewMode.grid) {
      await setViewMode(LibraryViewMode.list);
    } else {
      await setViewMode(LibraryViewMode.grid);
    }
  }
}

/// Provider for library view mode with persistence.
final libraryViewModeProvider =
    StateNotifierProvider<LibraryViewNotifier, LibraryViewMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return LibraryViewNotifier(prefs);
});

/// Provider that returns true if the current view mode is grid.
final isGridViewProvider = Provider<bool>((ref) {
  return ref.watch(libraryViewModeProvider) == LibraryViewMode.grid;
});
