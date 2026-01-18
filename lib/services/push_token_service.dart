import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for managing Firebase Cloud Messaging (FCM) push notification tokens.
///
/// Automatically registers for push notifications when the user logs in.
///
/// This service handles:
/// - Requesting notification permissions
/// - Retrieving and refreshing FCM tokens
/// - Registering tokens with the Supabase backend
/// - Updating presence status (last_used_at)
/// - Unregistering tokens on logout
class PushTokenService {
  PushTokenService._();

  static final PushTokenService _instance = PushTokenService._();
  static PushTokenService get instance => _instance;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;
  Timer? _presenceTimer;

  String? _currentToken;
  String? _deviceIdentifier;

  /// The current FCM token.
  String? get currentToken => _currentToken;

  /// Whether push notifications are enabled and registered.
  bool get isRegistered => _currentToken != null;

  /// Initialize the push token service.
  ///
  /// Call this after Firebase is initialized and user is authenticated.
  Future<void> initialize() async {
    debugPrint('[PushTokenService] Initializing...');

    // Get device identifier (unique per physical device)
    _deviceIdentifier = await _getDeviceIdentifier();
    debugPrint('[PushTokenService] Device identifier: $_deviceIdentifier');

    // Listen for token refresh events
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('[PushTokenService] Token refreshed: ${newToken.substring(0, 20)}...');
      _handleTokenRefresh(newToken);
    });

    // Listen for auth state changes to register/unregister on login/logout
    final supabase = Supabase.instance.client;
    _authStateSubscription = supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      debugPrint('[PushTokenService] Auth state changed: $event');

      if (event == AuthChangeEvent.signedIn) {
        // User just logged in, register for push notifications
        debugPrint('[PushTokenService] User signed in, requesting permissions...');
        requestPermissionsAndRegister();
      } else if (event == AuthChangeEvent.signedOut) {
        // User logged out, unregister token
        debugPrint('[PushTokenService] User signed out, unregistering token...');
        unregister();
      }
    });

    // If user is already logged in, request permissions and register token
    if (supabase.auth.currentUser != null) {
      debugPrint('[PushTokenService] User is logged in, requesting permissions...');
      await requestPermissionsAndRegister();
    } else {
      debugPrint('[PushTokenService] No user logged in, will register after login');
    }
  }

  /// Request notification permissions and register the FCM token.
  ///
  /// Returns true if permissions were granted and token was registered.
  Future<bool> requestPermissionsAndRegister() async {
    debugPrint('[PushTokenService] Requesting permissions...');

    // Request permissions
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('[PushTokenService] Permission status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      debugPrint('[PushTokenService] Push notifications not authorized');
      return false;
    }

    // Get the FCM token
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('[PushTokenService] Got FCM token: ${token.substring(0, 20)}...');
        await _registerToken(token);
        _startPresenceUpdates();
        return true;
      } else {
        debugPrint('[PushTokenService] Failed to get FCM token');
        return false;
      }
    } catch (e) {
      debugPrint('[PushTokenService] Error getting FCM token: $e');
      return false;
    }
  }

  /// Get a unique device identifier.
  Future<String> _getDeviceIdentifier() async {
    try {
      if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'unknown-ios';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.id;
      }
    } catch (e) {
      debugPrint('[PushTokenService] Error getting device ID: $e');
    }
    return 'unknown-device';
  }

  /// Register the FCM token with the backend.
  Future<void> _registerToken(String token) async {
    _currentToken = token;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      debugPrint('[PushTokenService] No user logged in, skipping registration');
      return;
    }

    try {
      // Call the Edge Function to register the token
      final response = await supabase.functions.invoke(
        'register-push-token',
        body: {
          'token': token,
          'platform': Platform.isIOS ? 'ios' : 'android',
          'device_identifier': _deviceIdentifier,
          'app_version': '1.0.0', // TODO: Get from package_info
        },
      );

      if (response.status == 200) {
        debugPrint('[PushTokenService] Token registered successfully');
      } else {
        debugPrint('[PushTokenService] Failed to register token: ${response.data}');
      }
    } catch (e) {
      debugPrint('[PushTokenService] Error registering token: $e');
    }
  }

  /// Handle token refresh events.
  Future<void> _handleTokenRefresh(String newToken) async {
    if (_currentToken != newToken) {
      await _registerToken(newToken);
    }
  }

  /// Start periodic presence updates.
  void _startPresenceUpdates() {
    _presenceTimer?.cancel();

    // Update presence every 2 minutes
    _presenceTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _updatePresence();
    });

    // Also update immediately
    _updatePresence();
  }

  /// Update presence to indicate the app is connected.
  ///
  /// This updates `last_used_at` in the push_notification_tokens table.
  /// The Edge Function uses this to decide whether to send push notifications
  /// (if the app is actively connected, we skip the push since realtime will handle it).
  Future<void> _updatePresence() async {
    if (_deviceIdentifier == null) return;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) return;

    try {
      // Update last_used_at directly (RLS allows users to update their own tokens)
      await supabase
          .from('push_notification_tokens')
          .update({'last_used_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', user.id)
          .eq('device_identifier', _deviceIdentifier!)
          .eq('is_active', true);

      debugPrint('[PushTokenService] Presence updated');
    } catch (e) {
      debugPrint('[PushTokenService] Error updating presence: $e');
    }
  }

  /// Unregister the current token (call on logout).
  Future<void> unregister() async {
    debugPrint('[PushTokenService] Unregistering token...');

    _presenceTimer?.cancel();
    _presenceTimer = null;

    if (_currentToken == null || _deviceIdentifier == null) return;

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      _currentToken = null;
      return;
    }

    try {
      // Mark the token as inactive
      await supabase
          .from('push_notification_tokens')
          .update({'is_active': false})
          .eq('user_id', user.id)
          .eq('device_identifier', _deviceIdentifier!);

      debugPrint('[PushTokenService] Token unregistered');
    } catch (e) {
      debugPrint('[PushTokenService] Error unregistering token: $e');
    }

    _currentToken = null;
  }

  /// Check if push notifications are authorized.
  Future<bool> isAuthorized() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Delete the FCM token from the device (for testing/debugging).
  Future<void> deleteToken() async {
    await _messaging.deleteToken();
    _currentToken = null;
    debugPrint('[PushTokenService] Token deleted');
  }

  /// Dispose of resources.
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _authStateSubscription?.cancel();
    _presenceTimer?.cancel();
  }
}
