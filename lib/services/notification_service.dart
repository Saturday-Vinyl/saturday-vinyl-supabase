import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Notification channels used in the app.
class NotificationChannels {
  NotificationChannels._();

  /// Flip reminder notifications.
  static const flipReminder = AndroidNotificationChannel(
    'flip_reminder',
    'Flip Reminders',
    description: 'Notifications to remind you to flip your vinyl record',
    importance: Importance.high,
  );

  /// Device alerts (battery, offline, etc.).
  static const deviceAlerts = AndroidNotificationChannel(
    'device_alerts',
    'Device Alerts',
    description: 'Notifications about your Saturday devices',
    importance: Importance.defaultImportance,
  );
}

/// Notification IDs for managing specific notifications.
class NotificationIds {
  NotificationIds._();

  /// Flip reminder notification ID.
  static const int flipReminder = 1;

  /// Base ID for device alerts (device-specific IDs offset from this).
  static const int deviceAlertBase = 100;

  /// Get device alert ID for a specific device.
  static int deviceAlert(String deviceId) {
    return deviceAlertBase + deviceId.hashCode.abs() % 1000;
  }
}

/// Service for managing local notifications.
///
/// Handles initialization, permission requests, scheduling, and
/// routing of notification taps to the appropriate screens.
class NotificationService {
  NotificationService._();

  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Callback for handling notification taps.
  ///
  /// Set this before initializing notifications.
  void Function(String? payload)? onNotificationTap;

  /// Whether notifications have been initialized.
  bool _initialized = false;

  /// Whether the user has granted notification permissions.
  bool _hasPermission = false;

  /// Returns whether notifications are initialized.
  bool get isInitialized => _initialized;

  /// Returns whether the user has granted notification permissions.
  bool get hasPermission => _hasPermission;

  /// Initialize the notification service.
  ///
  /// Call this early in app startup.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Create notification channels on Android.
    if (Platform.isAndroid) {
      await _createAndroidChannels();
    }

    _initialized = true;

    if (kDebugMode) {
      print('NotificationService: Initialized');
    }
  }

  /// Create Android notification channels.
  Future<void> _createAndroidChannels() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        NotificationChannels.flipReminder,
      );
      await androidPlugin.createNotificationChannel(
        NotificationChannels.deviceAlerts,
      );
    }
  }

  /// Request notification permissions from the user.
  ///
  /// Returns true if permissions were granted.
  Future<bool> requestPermissions() async {
    if (Platform.isIOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      final result = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      _hasPermission = result ?? false;
    } else if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      final result = await androidPlugin?.requestNotificationsPermission();
      _hasPermission = result ?? false;
    }

    if (kDebugMode) {
      print('NotificationService: Permission granted: $_hasPermission');
    }

    return _hasPermission;
  }

  /// Check if notifications are permitted.
  Future<bool> checkPermissions() async {
    if (Platform.isIOS) {
      final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      // On iOS, we need to check if we're allowed to show notifications
      // This will return nil if we've never requested permissions
      final result = await iosPlugin?.checkPermissions();
      _hasPermission = result?.isEnabled ?? false;
    } else if (Platform.isAndroid) {
      final androidPlugin =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      final result = await androidPlugin?.areNotificationsEnabled();
      _hasPermission = result ?? false;
    }

    return _hasPermission;
  }

  /// Handle notification tap response.
  void _onNotificationResponse(NotificationResponse response) {
    if (kDebugMode) {
      print(
          'NotificationService: Notification tapped with payload: ${response.payload}');
    }

    onNotificationTap?.call(response.payload);
  }

  /// Show a flip reminder notification.
  ///
  /// [albumTitle] - The album title to show in the notification.
  /// [side] - The side that needs to be flipped to (e.g., "B").
  Future<void> showFlipReminder({
    required String albumTitle,
    required String side,
  }) async {
    if (!_initialized || !_hasPermission) return;

    const androidDetails = AndroidNotificationDetails(
      'flip_reminder',
      'Flip Reminders',
      channelDescription: 'Notifications to remind you to flip your vinyl record',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Flip reminder',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      NotificationIds.flipReminder,
      'Time to flip!',
      'Flip "$albumTitle" to side $side',
      details,
      payload: 'flip_reminder',
    );

    if (kDebugMode) {
      print('NotificationService: Showed flip reminder for $albumTitle, side $side');
    }
  }

  /// Schedule a flip reminder notification.
  ///
  /// [albumTitle] - The album title to show in the notification.
  /// [side] - The side that needs to be flipped to.
  /// [delay] - How long until the notification should fire.
  Future<void> scheduleFlipReminder({
    required String albumTitle,
    required String side,
    required Duration delay,
  }) async {
    if (!_initialized || !_hasPermission) return;

    // Cancel any existing flip reminder.
    await cancelFlipReminder();

    const androidDetails = AndroidNotificationDetails(
      'flip_reminder',
      'Flip Reminders',
      channelDescription: 'Notifications to remind you to flip your vinyl record',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Flip reminder',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Schedule the notification
    final scheduledTime = DateTime.now().add(delay);

    await _plugin.zonedSchedule(
      NotificationIds.flipReminder,
      'Time to flip!',
      'Flip "$albumTitle" to side $side',
      _dateTimeToTZDateTime(scheduledTime),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: 'flip_reminder',
    );

    if (kDebugMode) {
      print('NotificationService: Scheduled flip reminder for $albumTitle in ${delay.inMinutes} minutes');
    }
  }

  /// Convert DateTime to TZDateTime for scheduling.
  tz.TZDateTime _dateTimeToTZDateTime(DateTime dateTime) {
    return tz.TZDateTime.from(dateTime, tz.local);
  }

  /// Cancel the flip reminder notification.
  Future<void> cancelFlipReminder() async {
    await _plugin.cancel(NotificationIds.flipReminder);

    if (kDebugMode) {
      print('NotificationService: Cancelled flip reminder');
    }
  }

  /// Show a device alert notification.
  ///
  /// [deviceId] - The device ID (used for notification ID).
  /// [deviceName] - The device name to show in the notification.
  /// [alertType] - The type of alert (e.g., "low_battery", "offline").
  /// [message] - The message to show.
  Future<void> showDeviceAlert({
    required String deviceId,
    required String deviceName,
    required String alertType,
    required String message,
  }) async {
    if (!_initialized || !_hasPermission) return;

    const androidDetails = AndroidNotificationDetails(
      'device_alerts',
      'Device Alerts',
      channelDescription: 'Notifications about your Saturday devices',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      NotificationIds.deviceAlert(deviceId),
      deviceName,
      message,
      details,
      payload: 'device_alert:$deviceId',
    );

    if (kDebugMode) {
      print('NotificationService: Showed device alert for $deviceName: $message');
    }
  }

  /// Cancel a device alert notification.
  Future<void> cancelDeviceAlert(String deviceId) async {
    await _plugin.cancel(NotificationIds.deviceAlert(deviceId));
  }

  /// Show a device offline notification.
  ///
  /// [deviceId] - The device ID.
  /// [deviceName] - The device name.
  Future<void> showDeviceOfflineNotification({
    required String deviceId,
    required String deviceName,
  }) async {
    await showDeviceAlert(
      deviceId: deviceId,
      deviceName: '$deviceName Offline',
      alertType: 'offline',
      message: '$deviceName is no longer connected.',
    );
  }

  /// Show a low battery notification.
  ///
  /// [deviceId] - The device ID.
  /// [deviceName] - The device name.
  /// [batteryLevel] - The current battery level (0-100).
  Future<void> showLowBatteryNotification({
    required String deviceId,
    required String deviceName,
    required int batteryLevel,
  }) async {
    await showDeviceAlert(
      deviceId: deviceId,
      deviceName: '$deviceName Battery Low',
      alertType: 'low_battery',
      message: '$deviceName battery is at $batteryLevel%. Please charge soon.',
    );
  }

  /// Cancel all notifications.
  Future<void> cancelAll() async {
    await _plugin.cancelAll();

    if (kDebugMode) {
      print('NotificationService: Cancelled all notifications');
    }
  }
}

/// Initialize timezone data.
///
/// Call this before scheduling any notifications.
Future<void> initializeTimezone() async {
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('America/New_York')); // Default, will be updated
}
