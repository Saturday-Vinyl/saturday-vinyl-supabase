import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/activity_update.dart';
import 'package:saturday_consumer_app/models/album.dart';

/// Activity ID for the flip timer Live Activity.
const String _flipTimerActivityId = 'flip_timer';

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
        // Note: For dev builds use 'group.com.dlatham.saturdayconsumer.dev'
        // For production use 'group.com.saturdayvinyl.consumer'
        await _liveActivities.init(
            appGroupId: 'group.com.dlatham.saturdayconsumer.dev');

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
      active: (state) {
        _hasActiveActivity = true;
      },
      ended: (state) {
        if (state.activityId == _flipTimerActivityId) {
          _hasActiveActivity = false;
        }
      },
      stale: (state) {
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
  Future<void> startFlipTimerActivity({
    required Album album,
    required DateTime startedAt,
    required int sideDurationSeconds,
    required String currentSide,
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
      final remainingSeconds = (sideDurationSeconds - elapsedSeconds).clamp(0, sideDurationSeconds);
      final isNearFlip = remainingSeconds < 120; // Less than 2 minutes
      final isOvertime = elapsedSeconds > sideDurationSeconds;

      final data = <String, dynamic>{
        'albumTitle': album.title,
        'artist': album.artist,
        'albumArtUrl': album.coverImageUrl ?? '',
        'currentSide': currentSide,
        'totalDurationSeconds': sideDurationSeconds,
        'elapsedSeconds': elapsedSeconds,
        'remainingSeconds': remainingSeconds,
        'isNearFlip': isNearFlip,
        'isOvertime': isOvertime,
        'startedAtTimestamp': startedAt.millisecondsSinceEpoch,
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

      if (kDebugMode) {
        print('LiveActivityService: Started flip timer activity, id: $activityId');
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
  }) async {
    if (!Platform.isIOS ||
        !_areActivitiesEnabled ||
        !_hasActiveActivity ||
        _currentActivityId == null) {
      return;
    }

    try {
      final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
      final remainingSeconds =
          (sideDurationSeconds - elapsedSeconds).clamp(0, sideDurationSeconds);
      final isNearFlip = remainingSeconds < 120 && remainingSeconds > 0;
      final isOvertime = elapsedSeconds > sideDurationSeconds;

      final data = <String, dynamic>{
        'currentSide': currentSide,
        'elapsedSeconds': elapsedSeconds,
        'remainingSeconds': remainingSeconds,
        'isNearFlip': isNearFlip,
        'isOvertime': isOvertime,
      };

      await _liveActivities.updateActivity(_currentActivityId!, data);

      if (kDebugMode) {
        print(
            'LiveActivityService: Updated flip timer, remaining: ${remainingSeconds}s');
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

  /// Dispose of resources.
  void dispose() {
    _activityUpdateSubscription?.cancel();
    _activityUpdateSubscription = null;
  }
}
