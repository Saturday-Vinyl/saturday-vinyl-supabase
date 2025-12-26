import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/activity_log_entry.dart';

/// Maximum number of entries to keep in the log
const int _maxLogEntries = 100;

/// State notifier for managing activity log entries
class ActivityLogNotifier extends StateNotifier<List<ActivityLogEntry>> {
  ActivityLogNotifier() : super([]);

  /// Add a new entry to the log
  void addEntry(String message, LogLevel level, {String? relatedEpc}) {
    final entry = ActivityLogEntry(
      message: message,
      level: level,
      relatedEpc: relatedEpc,
    );

    // Add to the beginning of the list (newest first internally, but displayed oldest first)
    final newState = [entry, ...state];

    // Trim to max entries if exceeded
    if (newState.length > _maxLogEntries) {
      state = newState.sublist(0, _maxLogEntries);
    } else {
      state = newState;
    }
  }

  /// Add an info level entry
  void info(String message, {String? relatedEpc}) {
    addEntry(message, LogLevel.info, relatedEpc: relatedEpc);
  }

  /// Add a success level entry
  void success(String message, {String? relatedEpc}) {
    addEntry(message, LogLevel.success, relatedEpc: relatedEpc);
  }

  /// Add a warning level entry
  void warning(String message, {String? relatedEpc}) {
    addEntry(message, LogLevel.warning, relatedEpc: relatedEpc);
  }

  /// Add an error level entry
  void error(String message, {String? relatedEpc}) {
    addEntry(message, LogLevel.error, relatedEpc: relatedEpc);
  }

  /// Clear all entries
  void clear() {
    state = [];
  }

  /// Get entries in display order (oldest first for chronological display)
  List<ActivityLogEntry> get entriesInDisplayOrder => state.reversed.toList();
}

/// Provider for the activity log
final activityLogProvider =
    StateNotifierProvider<ActivityLogNotifier, List<ActivityLogEntry>>((ref) {
  return ActivityLogNotifier();
});

/// Provider for entries in display order (oldest first)
final activityLogDisplayProvider = Provider<List<ActivityLogEntry>>((ref) {
  final entries = ref.watch(activityLogProvider);
  return entries.reversed.toList();
});
