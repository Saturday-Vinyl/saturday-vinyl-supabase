import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/activity_update.dart';
import 'package:saturday_consumer_app/models/album.dart';

/// Activity ID for the flip timer Live Activity.
const String _flipTimerActivityId = 'flip_timer';

/// Callback type for registering an ActivityKit push token with the server.
typedef ActivityPushTokenCallback = Future<void> Function(
    String pushToken, String sessionId);

/// Service for managing iOS Live Activities (Dynamic Island & Lock Screen).
///
/// Displays flip timer information in the Dynamic Island and Lock Screen
/// when a record is playing. Only works on iOS 16.1+.
class LiveActivityService {
  LiveActivityService._();

  static final LiveActivityService _instance = LiveActivityService._();
  static LiveActivityService get instance => _instance;

  final LiveActivities _liveActivities = LiveActivities();

  /// Whether Live Activities are supported on this device.
  bool _areActivitiesEnabled = false;

  /// Stream subscription for activity state updates.
  StreamSubscription<ActivityUpdate>? _activityUpdateSubscription;

  /// Whether the service has been initialized.
  bool _initialized = false;

  /// Whether there is currently an active Live Activity.
  bool _hasActiveActivity = false;

  /// The current activity ID returned by the system.
  String? _currentActivityId;

  /// The current session ID associated with the Live Activity.
  String? _currentSessionId;

  /// Holds the most recent ActivityKit push token if it arrives before
  /// [_currentSessionId] is known. Registered as soon as both the token
  /// and the session id are available, and cleared after registration so
  /// we don't double-register the same value.
  String? _pendingActivityToken;

  /// Callback for registering push tokens with the server.
  ActivityPushTokenCallback? _onPushTokenReceived;

  /// Returns whether Live Activities are supported and enabled.
  bool get areActivitiesEnabled => _areActivitiesEnabled;

  /// Returns whether there is currently an active Live Activity.
  bool get hasActiveActivity => _hasActiveActivity;

  /// Initialize the Live Activity service.
  ///
  /// Call this early in app startup.
  Future<void> initialize() async {
    if (_initialized) return;

    // Live Activities only work on iOS
    if (!Platform.isIOS) {
      _initialized = true;
      return;
    }

    try {
      // Check if Live Activities are enabled
      _areActivitiesEnabled = await _liveActivities.areActivitiesEnabled();

      if (_areActivitiesEnabled) {
        // Initialize with the app group
        await _liveActivities.init(
            appGroupId: 'group.com.saturdayvinyl.consumer');

        // Listen for activity state changes
        _activityUpdateSubscription =
            _liveActivities.activityUpdateStream.listen(_handleActivityUpdate);
      }

      _initialized = true;

      if (kDebugMode) {
        print(
            'LiveActivityService: Initialized, enabled: $_areActivitiesEnabled');
      }
    } catch (e) {
      _initialized = true;
      if (kDebugMode) {
        print('LiveActivityService: Failed to initialize: $e');
      }
    }
  }

  /// Handle activity update events.
  void _handleActivityUpdate(ActivityUpdate update) {
    if (kDebugMode) {
      print('LiveActivityService: Activity update: $update');
    }

    update.mapOrNull(
      active: (activeState) {
        _hasActiveActivity = true;
        _pendingActivityToken = activeState.activityToken;
        _tryRegisterPendingToken();
      },
      ended: (endedState) {
        if (endedState.activityId == _flipTimerActivityId) {
          _hasActiveActivity = false;
          _currentSessionId = null;
          _pendingActivityToken = null;
        }
      },
      stale: (staleState) {
        // Activity became stale, we might want to update it
      },
    );
  }

  /// Start a flip timer Live Activity.
  ///
  /// [album] - The album being played.
  /// [startedAt] - When playback started.
  /// [sideDurationSeconds] - Total duration of the current side in seconds.
  /// [currentSide] - Current side being played ('A' or 'B').
  /// Set the callback for when an ActivityKit push token is received.
  void setOnPushTokenReceived(ActivityPushTokenCallback? callback) {
    _onPushTokenReceived = callback;
    // If the token + session arrived before the provider wired up the
    // callback, register now.
    _tryRegisterPendingToken();
  }

  /// Attach a cloud session id to the currently-running activity. Called when
  /// the cloud session is confirmed *after* the activity has already started
  /// — common for the local-first startup path where the Live Activity is
  /// created before Supabase round-trips the session_queued event back.
  void attachSessionId(String sessionId) {
    if (!_hasActiveActivity) return;
    if (_currentSessionId == sessionId) return;
    _currentSessionId = sessionId;
    _tryRegisterPendingToken();
  }

  Future<void> startFlipTimerActivity({
    required Album album,
    required DateTime startedAt,
    required int sideDurationSeconds,
    required String currentSide,
    String? currentTrackTitle,
    String? currentTrackPosition,
    int currentTrackIndex = -1,
    int totalTracks = 0,
    String? sessionId,
  }) async {
    if (kDebugMode) {
      print('LiveActivityService: startFlipTimerActivity called');
      print('LiveActivityService: Platform.isIOS=$Platform.isIOS, _areActivitiesEnabled=$_areActivitiesEnabled');
    }

    if (!Platform.isIOS || !_areActivitiesEnabled) {
      if (kDebugMode) {
        print('LiveActivityService: Skipping - not iOS or activities not enabled');
      }
      return;
    }

    try {
      // End any existing activity first
      await stopFlipTimerActivity();

      final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
      final isOvertime = elapsedSeconds > sideDurationSeconds;

      final data = <String, dynamic>{
        'albumTitle': album.title,
        'artist': album.artist,
        'currentSide': currentSide,
        'totalDurationSeconds': sideDurationSeconds,
        'isOvertime': isOvertime,
        'startedAtTimestamp': startedAt.millisecondsSinceEpoch,
        'currentTrackTitle': currentTrackTitle ?? '',
        'currentTrackPosition': currentTrackPosition ?? '',
        'currentTrackIndex': currentTrackIndex,
        'totalTracks': totalTracks,
      };

      if (kDebugMode) {
        print('LiveActivityService: Creating activity with data: $data');
      }

      final activityId = await _liveActivities.createActivity(
        _flipTimerActivityId,
        data,
        removeWhenAppIsKilled: false,
      );

      _currentActivityId = activityId;
      _hasActiveActivity = true;
      _currentSessionId = sessionId;

      if (kDebugMode) {
        print('LiveActivityService: Started flip timer activity, id: $activityId');
      }

      // If iOS already delivered the activity token while sessionId was
      // unknown (common race when starting playback before the cloud
      // session is confirmed), register it now.
      _tryRegisterPendingToken();

      // Also try the explicit pull — covers the case where the activity
      // is started AFTER sessionId is known and the update stream hasn't
      // fired yet.
      if (activityId != null && sessionId != null) {
        _retrieveAndRegisterPushToken(activityId, sessionId);
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('LiveActivityService: Failed to start activity: $e');
        print('LiveActivityService: Stack trace: $stackTrace');
      }
    }
  }

  /// Update the flip timer Live Activity.
  ///
  /// Call this periodically (e.g., every 30 seconds) to update the display.
  Future<void> updateFlipTimerActivity({
    required DateTime startedAt,
    required int sideDurationSeconds,
    required String currentSide,
    String? currentTrackTitle,
    String? currentTrackPosition,
    int currentTrackIndex = -1,
    int totalTracks = 0,
  }) async {
    if (!Platform.isIOS ||
        !_areActivitiesEnabled ||
        !_hasActiveActivity ||
        _currentActivityId == null) {
      return;
    }

    try {
      final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
      final isOvertime = elapsedSeconds > sideDurationSeconds;

      final data = <String, dynamic>{
        'currentSide': currentSide,
        'isOvertime': isOvertime,
        'currentTrackTitle': currentTrackTitle ?? '',
        'currentTrackPosition': currentTrackPosition ?? '',
        'currentTrackIndex': currentTrackIndex,
        'totalTracks': totalTracks,
      };

      await _liveActivities.updateActivity(_currentActivityId!, data);

      if (kDebugMode) {
        print('LiveActivityService: Updated flip timer');
      }
    } catch (e) {
      if (kDebugMode) {
        print('LiveActivityService: Failed to update activity: $e');
      }
    }
  }

  /// Stop the flip timer Live Activity.
  Future<void> stopFlipTimerActivity() async {
    if (!Platform.isIOS) return;

    final activityId = _currentActivityId;
    if (activityId == null) {
      _hasActiveActivity = false;
      if (kDebugMode) {
        print('LiveActivityService: No activity to stop');
      }
      return;
    }

    try {
      await _liveActivities.endActivity(activityId);
      _currentActivityId = null;
      _hasActiveActivity = false;

      if (kDebugMode) {
        print('LiveActivityService: Stopped flip timer activity');
      }
    } catch (e) {
      _currentActivityId = null;
      _hasActiveActivity = false;
      if (kDebugMode) {
        print('LiveActivityService: Failed to stop activity: $e');
      }
    }
  }

  /// End all Live Activities.
  Future<void> endAllActivities() async {
    if (!Platform.isIOS) return;

    try {
      await _liveActivities.endAllActivities();
      _currentActivityId = null;
      _hasActiveActivity = false;

      if (kDebugMode) {
        print('LiveActivityService: Ended all activities');
      }
    } catch (e) {
      _currentActivityId = null;
      _hasActiveActivity = false;
      if (kDebugMode) {
        print('LiveActivityService: Failed to end all activities: $e');
      }
    }
  }

  /// Register the buffered ActivityKit token with the server, if both the
  /// token and the session id are known. iOS often delivers the token via
  /// the update stream a few hundred ms after the activity is created —
  /// sometimes before the cloud session_id is back from Supabase, sometimes
  /// after. Either order resolves here.
  void _tryRegisterPendingToken() {
    final token = _pendingActivityToken;
    final sessionId = _currentSessionId;
    final callback = _onPushTokenReceived;
    if (token == null || sessionId == null || callback == null) return;

    if (kDebugMode) {
      print(
          'LiveActivityService: Registering activity push token: ${token.substring(0, 20)}... session=$sessionId');
    }
    callback(token, sessionId);
    _pendingActivityToken = null;
  }

  /// Attempt to get the ActivityKit push token and register it.
  Future<void> _retrieveAndRegisterPushToken(
    String activityId,
    String sessionId,
  ) async {
    if (_onPushTokenReceived == null) return;

    try {
      final pushToken = await _liveActivities.getPushToken(activityId);
      if (pushToken != null && pushToken.isNotEmpty) {
        if (kDebugMode) {
          print(
              'LiveActivityService: Retrieved push token: ${pushToken.substring(0, 20)}...');
        }
        await _onPushTokenReceived!(pushToken, sessionId);
      }
    } catch (e) {
      if (kDebugMode) {
        print('LiveActivityService: Failed to get push token: $e');
      }
      // Not critical — the activityUpdateStream callback will also try
    }
  }

  /// Dispose of resources.
  void dispose() {
    _activityUpdateSubscription?.cancel();
    _activityUpdateSubscription = null;
  }
}
