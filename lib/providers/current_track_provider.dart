import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/track.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/utils/track_position_calculator.dart';

/// Provider that emits the current [TrackPosition] based on elapsed time
/// and the currently playing side's track durations.
///
/// Updates every second while an album is playing. Emits `null` when
/// no album is playing or track position cannot be calculated (e.g.,
/// all track durations are unknown).
final currentTrackProvider =
    StateNotifierProvider<CurrentTrackNotifier, TrackPosition?>((ref) {
  return CurrentTrackNotifier(ref);
});

/// Calculates the current track position every second based on
/// [NowPlayingState.startedAt] and track durations.
class CurrentTrackNotifier extends StateNotifier<TrackPosition?> {
  CurrentTrackNotifier(this._ref) : super(null) {
    _ref.listen<NowPlayingState>(nowPlayingProvider, (previous, next) {
      _onNowPlayingChanged(next);
    }, fireImmediately: true);
  }

  final Ref _ref;
  Timer? _timer;
  DateTime? _startedAt;
  List<Track>? _currentTracks;

  void _onNowPlayingChanged(NowPlayingState npState) {
    _timer?.cancel();

    if (!npState.isPlaying || npState.startedAt == null) {
      _startedAt = null;
      _currentTracks = null;
      state = null;
      return;
    }

    _startedAt = npState.startedAt;
    _currentTracks = npState.currentSideTracks;

    // Calculate immediately
    _calculate();

    // Then update every second
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _calculate();
    });
  }

  void _calculate() {
    final startedAt = _startedAt;
    final tracks = _currentTracks;

    if (startedAt == null || tracks == null || tracks.isEmpty) {
      state = null;
      return;
    }

    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    state = TrackPositionCalculator.calculate(
      elapsedSeconds: elapsed,
      tracks: tracks,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
