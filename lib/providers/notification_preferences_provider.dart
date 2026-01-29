import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';

// Note: This provider uses currentUserIdProvider (internal users.id) not
// currentSupabaseUserProvider (auth.uid) because notification_preferences.user_id
// references the users table, not auth.users.

/// State for server-synced notification preferences.
///
/// These preferences are stored in the `notification_preferences` table in Supabase
/// and are checked by Edge Functions before sending push notifications.
class NotificationPreferencesState {
  const NotificationPreferencesState({
    this.nowPlayingEnabled = true,
    this.flipRemindersEnabled = true,
    this.deviceOfflineEnabled = true,
    this.deviceOnlineEnabled = true,
    this.batteryLowEnabled = true,
    this.isLoading = true,
    this.isSynced = false,
    this.error,
  });

  /// Whether Now Playing notifications are enabled.
  final bool nowPlayingEnabled;

  /// Whether flip reminder notifications are enabled.
  final bool flipRemindersEnabled;

  /// Whether device offline notifications are enabled.
  final bool deviceOfflineEnabled;

  /// Whether device online (recovery) notifications are enabled.
  final bool deviceOnlineEnabled;

  /// Whether battery low notifications are enabled.
  final bool batteryLowEnabled;

  /// Whether preferences are currently loading.
  final bool isLoading;

  /// Whether preferences have been synced from/to server.
  final bool isSynced;

  /// Error message if there was a sync error.
  final String? error;

  NotificationPreferencesState copyWith({
    bool? nowPlayingEnabled,
    bool? flipRemindersEnabled,
    bool? deviceOfflineEnabled,
    bool? deviceOnlineEnabled,
    bool? batteryLowEnabled,
    bool? isLoading,
    bool? isSynced,
    String? error,
  }) {
    return NotificationPreferencesState(
      nowPlayingEnabled: nowPlayingEnabled ?? this.nowPlayingEnabled,
      flipRemindersEnabled: flipRemindersEnabled ?? this.flipRemindersEnabled,
      deviceOfflineEnabled: deviceOfflineEnabled ?? this.deviceOfflineEnabled,
      deviceOnlineEnabled: deviceOnlineEnabled ?? this.deviceOnlineEnabled,
      batteryLowEnabled: batteryLowEnabled ?? this.batteryLowEnabled,
      isLoading: isLoading ?? this.isLoading,
      isSynced: isSynced ?? this.isSynced,
      error: error,
    );
  }
}

/// Notifier that manages server-synced notification preferences.
class NotificationPreferencesNotifier
    extends StateNotifier<NotificationPreferencesState> {
  NotificationPreferencesNotifier(this._ref)
      : super(const NotificationPreferencesState());

  final Ref _ref;

  static const _tableName = 'notification_preferences';

  /// Load preferences from server. Creates default row if none exists.
  Future<void> loadPreferences() async {
    // Use internal user ID (users.id), not auth UID (auth.uid)
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) {
      state = state.copyWith(
        isLoading: false,
        isSynced: false,
        error: 'Not signed in',
      );
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final client = _ref.read(supabaseClientProvider);

      // Try to get existing preferences
      final response = await client
          .from(_tableName)
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) {
        // No preferences exist, create default row
        await _createDefaultPreferences(userId);
        state = state.copyWith(
          isLoading: false,
          isSynced: true,
        );
      } else {
        // Parse existing preferences
        state = NotificationPreferencesState(
          nowPlayingEnabled: response['now_playing_enabled'] as bool? ?? true,
          flipRemindersEnabled:
              response['flip_reminders_enabled'] as bool? ?? true,
          deviceOfflineEnabled:
              response['device_offline_enabled'] as bool? ?? true,
          deviceOnlineEnabled:
              response['device_online_enabled'] as bool? ?? true,
          batteryLowEnabled: response['battery_low_enabled'] as bool? ?? true,
          isLoading: false,
          isSynced: true,
        );
      }
    } catch (e) {
      debugPrint('Error loading notification preferences: $e');
      state = state.copyWith(
        isLoading: false,
        isSynced: false,
        error: e.toString(),
      );
    }
  }

  /// Create default preferences row for a user.
  Future<void> _createDefaultPreferences(String userId) async {
    final client = _ref.read(supabaseClientProvider);

    await client.from(_tableName).insert({
      'user_id': userId,
      'now_playing_enabled': true,
      'flip_reminders_enabled': true,
      'device_offline_enabled': true,
      'device_online_enabled': true,
      'battery_low_enabled': true,
    });
  }

  /// Update a preference on the server.
  Future<void> _updatePreference(String column, bool value) async {
    // Use internal user ID (users.id), not auth UID (auth.uid)
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      final client = _ref.read(supabaseClientProvider);

      await client
          .from(_tableName)
          .update({column: value})
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Error updating notification preference $column: $e');
      // Note: We don't revert state on error since the UI is optimistically updated
      // and we want to avoid flickering. The setting will sync on next load.
    }
  }

  /// Toggle Now Playing notifications.
  Future<void> setNowPlayingEnabled(bool enabled) async {
    state = state.copyWith(nowPlayingEnabled: enabled);
    await _updatePreference('now_playing_enabled', enabled);
  }

  /// Toggle flip reminder notifications.
  Future<void> setFlipRemindersEnabled(bool enabled) async {
    state = state.copyWith(flipRemindersEnabled: enabled);
    await _updatePreference('flip_reminders_enabled', enabled);
  }

  /// Toggle device offline notifications.
  Future<void> setDeviceOfflineEnabled(bool enabled) async {
    state = state.copyWith(deviceOfflineEnabled: enabled);
    await _updatePreference('device_offline_enabled', enabled);
  }

  /// Toggle device online (recovery) notifications.
  Future<void> setDeviceOnlineEnabled(bool enabled) async {
    state = state.copyWith(deviceOnlineEnabled: enabled);
    await _updatePreference('device_online_enabled', enabled);
  }

  /// Toggle battery low notifications.
  Future<void> setBatteryLowEnabled(bool enabled) async {
    state = state.copyWith(batteryLowEnabled: enabled);
    await _updatePreference('battery_low_enabled', enabled);
  }
}

/// Provider for server-synced notification preferences.
final notificationPreferencesProvider = StateNotifierProvider<
    NotificationPreferencesNotifier, NotificationPreferencesState>((ref) {
  final notifier = NotificationPreferencesNotifier(ref);

  // Load preferences when the provider is first accessed
  // and when user ID changes (uses internal user ID, not auth UID)
  ref.listen(currentUserIdProvider, (previous, next) {
    if (previous != next) {
      notifier.loadPreferences();
    }
  }, fireImmediately: true);

  return notifier;
});
