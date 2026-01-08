import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for notification preferences in SharedPreferences.
class _NotificationPrefKeys {
  static const flipRemindersEnabled = 'notifications.flip_reminders_enabled';
  static const deviceAlertsEnabled = 'notifications.device_alerts_enabled';
  static const batteryAlertsEnabled = 'notifications.battery_alerts_enabled';
}

/// State for notification preferences and permissions.
class NotificationState {
  const NotificationState({
    this.hasPermission = false,
    this.permissionRequested = false,
    this.flipRemindersEnabled = true,
    this.deviceAlertsEnabled = true,
    this.batteryAlertsEnabled = true,
  });

  /// Whether the user has granted notification permissions.
  final bool hasPermission;

  /// Whether we've requested permissions this session.
  final bool permissionRequested;

  /// Whether flip reminders are enabled.
  final bool flipRemindersEnabled;

  /// Whether device status alerts are enabled.
  final bool deviceAlertsEnabled;

  /// Whether battery low alerts are enabled.
  final bool batteryAlertsEnabled;

  /// Whether any notifications are effectively enabled.
  bool get anyEnabled =>
      hasPermission &&
      (flipRemindersEnabled || deviceAlertsEnabled || batteryAlertsEnabled);

  NotificationState copyWith({
    bool? hasPermission,
    bool? permissionRequested,
    bool? flipRemindersEnabled,
    bool? deviceAlertsEnabled,
    bool? batteryAlertsEnabled,
  }) {
    return NotificationState(
      hasPermission: hasPermission ?? this.hasPermission,
      permissionRequested: permissionRequested ?? this.permissionRequested,
      flipRemindersEnabled: flipRemindersEnabled ?? this.flipRemindersEnabled,
      deviceAlertsEnabled: deviceAlertsEnabled ?? this.deviceAlertsEnabled,
      batteryAlertsEnabled: batteryAlertsEnabled ?? this.batteryAlertsEnabled,
    );
  }
}

/// Provider for managing notification state and preferences.
class NotificationNotifier extends StateNotifier<NotificationState> {
  NotificationNotifier() : super(const NotificationState()) {
    _loadPreferences();
  }

  SharedPreferences? _prefs;

  /// Initialize and load preferences.
  Future<void> _loadPreferences() async {
    _prefs = await SharedPreferences.getInstance();

    // Check current permission status.
    final hasPermission =
        await NotificationService.instance.checkPermissions();

    state = state.copyWith(
      hasPermission: hasPermission,
      flipRemindersEnabled:
          _prefs?.getBool(_NotificationPrefKeys.flipRemindersEnabled) ?? true,
      deviceAlertsEnabled:
          _prefs?.getBool(_NotificationPrefKeys.deviceAlertsEnabled) ?? true,
      batteryAlertsEnabled:
          _prefs?.getBool(_NotificationPrefKeys.batteryAlertsEnabled) ?? true,
    );
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

  /// Toggle flip reminders.
  Future<void> setFlipRemindersEnabled(bool enabled) async {
    state = state.copyWith(flipRemindersEnabled: enabled);
    await _prefs?.setBool(_NotificationPrefKeys.flipRemindersEnabled, enabled);

    // Cancel any pending flip reminders if disabled.
    if (!enabled) {
      await NotificationService.instance.cancelFlipReminder();
    }
  }

  /// Toggle device alerts.
  Future<void> setDeviceAlertsEnabled(bool enabled) async {
    state = state.copyWith(deviceAlertsEnabled: enabled);
    await _prefs?.setBool(_NotificationPrefKeys.deviceAlertsEnabled, enabled);
  }

  /// Toggle battery alerts.
  Future<void> setBatteryAlertsEnabled(bool enabled) async {
    state = state.copyWith(batteryAlertsEnabled: enabled);
    await _prefs?.setBool(_NotificationPrefKeys.batteryAlertsEnabled, enabled);
  }

  /// Schedule a flip reminder for the current now playing album.
  Future<void> scheduleFlipReminder({
    required String albumTitle,
    required String nextSide,
    required Duration delay,
  }) async {
    if (!state.hasPermission || !state.flipRemindersEnabled) return;

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
  Future<void> showBatteryLowAlert({
    required String deviceId,
    required String deviceName,
    required int batteryLevel,
  }) async {
    if (!state.hasPermission || !state.batteryAlertsEnabled) return;

    await NotificationService.instance.showDeviceAlert(
      deviceId: deviceId,
      deviceName: deviceName,
      alertType: 'low_battery',
      message: 'Battery is low ($batteryLevel%). Charge soon.',
    );
  }

  /// Show a device offline alert.
  Future<void> showDeviceOfflineAlert({
    required String deviceId,
    required String deviceName,
  }) async {
    if (!state.hasPermission || !state.deviceAlertsEnabled) return;

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

  // Check if notifications are enabled.
  if (!notificationState.hasPermission ||
      !notificationState.flipRemindersEnabled) {
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
