import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/providers/notification_preferences_provider.dart';
import 'package:saturday_consumer_app/services/notification_service.dart';

/// State for notification permission status.
///
/// Note: Notification preference toggles (flip reminders, device alerts, etc.)
/// are managed by [NotificationPreferencesState] which syncs with the server.
/// This state only tracks OS-level permission status.
class NotificationState {
  const NotificationState({
    this.hasPermission = false,
    this.permissionRequested = false,
  });

  /// Whether the user has granted notification permissions.
  final bool hasPermission;

  /// Whether we've requested permissions this session.
  final bool permissionRequested;

  NotificationState copyWith({
    bool? hasPermission,
    bool? permissionRequested,
  }) {
    return NotificationState(
      hasPermission: hasPermission ?? this.hasPermission,
      permissionRequested: permissionRequested ?? this.permissionRequested,
    );
  }
}

/// Provider for managing notification permission state.
///
/// Note: Notification preference toggles are managed by [notificationPreferencesProvider]
/// which syncs with the server. This provider handles OS-level permission state.
class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier() : super(const NotificationState()) {
    _checkPermissions();
  }

  /// Check current permission status.
  Future<void> _checkPermissions() async {
    final hasPermission =
        await NotificationService.instance.checkPermissions();

    state = state.copyWith(hasPermission: hasPermission);
  }

  /// Request notification permissions from the user.
  Future<bool> requestPermissions() async {
    final granted = await NotificationService.instance.requestPermissions();

    state = state.copyWith(
      hasPermission: granted,
      permissionRequested: true,
    );

    return granted;
  }

  /// Schedule a flip reminder for the current now playing album.
  ///
  /// Note: This checks the permission state but the enabled state should be
  /// checked by the caller using [notificationPreferencesProvider].
  Future<void> scheduleFlipReminder({
    required String albumTitle,
    required String nextSide,
    required Duration delay,
    required bool flipRemindersEnabled,
  }) async {
    if (!state.hasPermission || !flipRemindersEnabled) return;

    await NotificationService.instance.scheduleFlipReminder(
      albumTitle: albumTitle,
      side: nextSide,
      delay: delay,
    );
  }

  /// Cancel the current flip reminder.
  Future<void> cancelFlipReminder() async {
    await NotificationService.instance.cancelFlipReminder();
  }

  /// Show a battery low alert for a device.
  ///
  /// Note: This checks the permission state but the enabled state should be
  /// checked by the caller using [notificationPreferencesProvider].
  Future<void> showBatteryLowAlert({
    required String deviceId,
    required String deviceName,
    required int batteryLevel,
    required bool batteryAlertsEnabled,
  }) async {
    if (!state.hasPermission || !batteryAlertsEnabled) return;

    await NotificationService.instance.showDeviceAlert(
      deviceId: deviceId,
      deviceName: deviceName,
      alertType: 'low_battery',
      message: 'Battery is low ($batteryLevel%). Charge soon.',
    );
  }

  /// Show a device offline alert.
  ///
  /// Note: This checks the permission state but the enabled state should be
  /// checked by the caller using [notificationPreferencesProvider].
  Future<void> showDeviceOfflineAlert({
    required String deviceId,
    required String deviceName,
    required bool deviceAlertsEnabled,
  }) async {
    if (!state.hasPermission || !deviceAlertsEnabled) return;

    await NotificationService.instance.showDeviceAlert(
      deviceId: deviceId,
      deviceName: deviceName,
      alertType: 'offline',
      message: 'Device is offline. Check the connection.',
    );
  }
}

/// Provider for notification state and preferences.
final notificationProvider =
    StateNotifierProvider<NotificationNotifier, NotificationState>((ref) {
  return NotificationNotifier();
});

/// Calculate remaining side duration and schedule flip reminder.
///
/// This is a helper function that can be called when playing state changes.
/// The flip timer UI handles the countdown display, and this function
/// schedules the notification.
///
/// [albumTitle] - The album title for the notification.
/// [sideDurationSeconds] - Total duration of the side in seconds.
/// [startedAt] - When the side started playing.
/// [nextSide] - The side to flip to (e.g., "B").
/// [ref] - Riverpod ref to access providers.
void scheduleFlipReminderIfNeeded({
  required String albumTitle,
  required int sideDurationSeconds,
  required DateTime startedAt,
  required String nextSide,
  required Ref ref,
}) {
  final notificationState = ref.read(notificationProvider);
  final prefsState = ref.read(notificationPreferencesProvider);

  // Check if notifications are enabled (permission + preference).
  if (!notificationState.hasPermission || !prefsState.flipRemindersEnabled) {
    return;
  }

  // Calculate remaining time.
  final elapsed = DateTime.now().difference(startedAt);
  final remaining = Duration(seconds: sideDurationSeconds) - elapsed;

  // Only schedule if there's time remaining.
  if (remaining.inSeconds <= 0) {
    return;
  }

  // Schedule the reminder.
  ref.read(notificationProvider.notifier).scheduleFlipReminder(
    albumTitle: albumTitle,
    nextSide: nextSide,
    delay: remaining,
    flipRemindersEnabled: prefsState.flipRemindersEnabled,
  );
}

/// Cancel flip reminder when playback stops.
void cancelFlipReminderOnStop(Ref ref) {
  ref.read(notificationProvider.notifier).cancelFlipReminder();
}

/// Provider to get the notification service instance.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});
