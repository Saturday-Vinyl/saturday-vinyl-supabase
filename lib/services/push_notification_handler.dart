import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';

/// Background message handler - must be a top-level function.
///
/// This is called when the app is in the background or terminated
/// and a push notification is received.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized
  await Firebase.initializeApp();

  debugPrint('[PushNotificationHandler] Background message: ${message.messageId}');
  debugPrint('[PushNotificationHandler] Data: ${message.data}');

  // Note: We don't need to show a notification here because FCM
  // automatically shows the notification when the app is in background.
  // This handler is for any additional processing we want to do.
}

/// Service for handling incoming Firebase Cloud Messaging push notifications.
///
/// This service handles:
/// - Foreground message display
/// - Background message handling
/// - Notification tap navigation
/// - Deep link extraction from notification data
class PushNotificationHandler {
  PushNotificationHandler._();

  static final PushNotificationHandler _instance = PushNotificationHandler._();
  static PushNotificationHandler get instance => _instance;

  /// Callback for navigating to a route when a notification is tapped.
  void Function(String route)? onNavigate;

  /// Reference to the ProviderContainer for updating state.
  ProviderContainer? _container;

  /// Whether the handler has been initialized.
  bool _initialized = false;

  /// Initialize the push notification handler.
  ///
  /// Call this after Firebase is initialized.
  Future<void> initialize({ProviderContainer? container}) async {
    if (_initialized) return;

    _container = container;

    // Set up foreground message handler
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Set up background message opened handler (when user taps notification)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check if app was launched from a notification
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[PushNotificationHandler] App launched from notification');
      // Delay handling to ensure app is fully initialized
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleNotificationTap(initialMessage);
      });
    }

    _initialized = true;
    debugPrint('[PushNotificationHandler] Initialized');
  }

  /// Handle foreground messages.
  ///
  /// When the app is in the foreground, FCM doesn't automatically show
  /// notifications. We need to decide what to do:
  /// - For now_playing, we already receive updates via realtime, so we
  ///   might just want to update state without showing a notification.
  /// - For other types, we might want to show a local notification.
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[PushNotificationHandler] Foreground message: ${message.messageId}');
    debugPrint('[PushNotificationHandler] Title: ${message.notification?.title}');
    debugPrint('[PushNotificationHandler] Body: ${message.notification?.body}');
    debugPrint('[PushNotificationHandler] Data: ${message.data}');

    final notificationType = message.data['type'] as String?;

    switch (notificationType) {
      case 'now_playing':
        // Now Playing updates are handled via realtime when app is open,
        // so we don't need to show a notification. Just log it.
        debugPrint('[PushNotificationHandler] Now Playing update received (handled by realtime)');
        break;

      case 'device_offline':
      case 'device_online':
      case 'battery_low':
        // For device alerts, show a local notification
        // even when the app is open (user might be on a different screen)
        _showLocalNotificationForMessage(message);
        break;

      default:
        // For unknown types, optionally show a local notification
        debugPrint('[PushNotificationHandler] Unknown notification type: $notificationType');
    }
  }

  /// Handle notification tap (user tapped on the notification).
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[PushNotificationHandler] Notification tapped: ${message.messageId}');
    debugPrint('[PushNotificationHandler] Data: ${message.data}');

    final notificationType = message.data['type'] as String?;

    switch (notificationType) {
      case 'now_playing':
        // Navigate to Now Playing screen
        final libraryAlbumId = message.data['library_album_id'] as String?;
        if (libraryAlbumId != null && libraryAlbumId.isNotEmpty) {
          // Could navigate to album detail, but Now Playing is more appropriate
          _navigateTo(RoutePaths.nowPlaying);
        } else {
          _navigateTo(RoutePaths.nowPlaying);
        }
        break;

      case 'device_offline':
      case 'battery_low':
        // Navigate to device detail screen
        final deviceId = message.data['device_id'] as String?;
        if (deviceId != null) {
          _navigateTo('/account/devices/$deviceId');
        } else {
          _navigateTo('/account');
        }
        break;

      case 'device_online':
        // Device came back online - just navigate to account/devices
        // since the device is working again, no urgent action needed
        _navigateTo('/account');
        break;

      case 'flip_reminder':
        // Navigate to Now Playing screen
        _navigateTo(RoutePaths.nowPlaying);
        break;

      default:
        // For unknown types, go to home
        debugPrint('[PushNotificationHandler] Unknown notification type: $notificationType');
        _navigateTo(RoutePaths.nowPlaying);
    }
  }

  /// Navigate to a route.
  void _navigateTo(String route) {
    debugPrint('[PushNotificationHandler] Navigating to: $route');
    onNavigate?.call(route);
  }

  /// Show a local notification for a foreground message.
  ///
  /// This is used when we want to show a notification even when the app
  /// is in the foreground.
  void _showLocalNotificationForMessage(RemoteMessage message) {
    // Import and use NotificationService to show local notification
    // This is optional - uncomment if needed
    /*
    final notification = message.notification;
    if (notification != null) {
      NotificationService.instance.showDeviceAlert(
        deviceId: message.data['device_id'] ?? 'unknown',
        deviceName: notification.title ?? 'Device Alert',
        alertType: message.data['type'] ?? 'unknown',
        message: notification.body ?? '',
      );
    }
    */
    debugPrint('[PushNotificationHandler] Would show local notification for foreground message');
  }

  /// Parse deep link data from notification.
  Map<String, dynamic>? parseDeepLinkData(RemoteMessage message) {
    try {
      final deepLinkJson = message.data['deep_link'] as String?;
      if (deepLinkJson != null) {
        return jsonDecode(deepLinkJson) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[PushNotificationHandler] Error parsing deep link: $e');
    }
    return null;
  }

  /// Dispose of resources.
  void dispose() {
    _initialized = false;
    _container = null;
    onNavigate = null;
  }
}

/// Extension on GoRouter for easy navigation from notification handler.
extension NotificationNavigation on GoRouter {
  /// Navigate to a route from a notification.
  void navigateFromNotification(String route) {
    // Use go() for root-level navigation
    go(route);
  }
}
