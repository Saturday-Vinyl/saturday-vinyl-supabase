import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/services/live_activity_service.dart';

/// Provider that manages Live Activities based on Now Playing state.
///
/// Automatically starts, updates, and stops Live Activities when
/// the Now Playing state changes.
class LiveActivityNotifier extends StateNotifier<bool> {
  LiveActivityNotifier(this._ref) : super(false) {
    _initialize();
  }

  final Ref _ref;
  Timer? _updateTimer;

  /// Initialize the Live Activity manager.
  Future<void> _initialize() async {
    if (!Platform.isIOS) return;

    // Initialize the service
    await LiveActivityService.instance.initialize();
    state = LiveActivityService.instance.areActivitiesEnabled;

    // Listen for Now Playing state changes
    _ref.listen<NowPlayingState>(nowPlayingProvider, (previous, next) {
      _handleNowPlayingChange(previous, next);
    });

    // Check initial state
    final nowPlaying = _ref.read(nowPlayingProvider);
    if (nowPlaying.isPlaying) {
      _startActivity(nowPlaying);
    }
  }

  /// Handle changes to Now Playing state.
  void _handleNowPlayingChange(
    NowPlayingState? previous,
    NowPlayingState next,
  ) {
    // Started playing
    if (next.isPlaying && (previous == null || !previous.isPlaying)) {
      _startActivity(next);
      return;
    }

    // Stopped playing
    if (!next.isPlaying && previous != null && previous.isPlaying) {
      _stopActivity();
      return;
    }

    // Album changed
    if (next.isPlaying &&
        previous?.currentAlbum?.id != next.currentAlbum?.id) {
      _startActivity(next);
      return;
    }

    // Side changed
    if (next.isPlaying && previous?.currentSide != next.currentSide) {
      _startActivity(next);
      return;
    }
  }

  /// Start a Live Activity for the current album.
  Future<void> _startActivity(NowPlayingState nowPlaying) async {
    if (!Platform.isIOS) return;

    final album = nowPlaying.currentAlbum?.album;
    if (album == null || nowPlaying.startedAt == null) return;

    await LiveActivityService.instance.startFlipTimerActivity(
      album: album,
      startedAt: nowPlaying.startedAt!,
      sideDurationSeconds: nowPlaying.currentSideDurationSeconds,
      currentSide: nowPlaying.currentSide,
    );

    // Start periodic updates
    _startUpdateTimer(nowPlaying);
  }

  /// Stop the current Live Activity.
  Future<void> _stopActivity() async {
    _updateTimer?.cancel();
    _updateTimer = null;

    await LiveActivityService.instance.stopFlipTimerActivity();
  }

  /// Start a timer to periodically update the Live Activity.
  void _startUpdateTimer(NowPlayingState initialState) {
    _updateTimer?.cancel();

    // Update every 30 seconds
    _updateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      final nowPlaying = _ref.read(nowPlayingProvider);

      if (!nowPlaying.isPlaying || nowPlaying.startedAt == null) {
        timer.cancel();
        return;
      }

      LiveActivityService.instance.updateFlipTimerActivity(
        startedAt: nowPlaying.startedAt!,
        sideDurationSeconds: nowPlaying.currentSideDurationSeconds,
        currentSide: nowPlaying.currentSide,
      );
    });
  }

  /// Manually refresh the Live Activity.
  Future<void> refresh() async {
    final nowPlaying = _ref.read(nowPlayingProvider);
    if (nowPlaying.isPlaying) {
      await _startActivity(nowPlaying);
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }
}

/// Provider for Live Activity state.
///
/// The boolean state indicates whether Live Activities are enabled on this device.
final liveActivityProvider =
    StateNotifierProvider<LiveActivityNotifier, bool>((ref) {
  return LiveActivityNotifier(ref);
});

/// Provider for whether Live Activities are available.
final liveActivitiesAvailableProvider = Provider<bool>((ref) {
  if (!Platform.isIOS) return false;
  return ref.watch(liveActivityProvider);
});
