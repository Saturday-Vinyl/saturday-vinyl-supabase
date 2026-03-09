import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/track.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/repositories/track_duration_repository.dart';

/// The phase of the track timing session.
enum TrackTimingPhase {
  /// No timing session active.
  idle,

  /// Actively timing tracks (stopwatch running).
  timing,

  /// Finished timing, reviewing results before saving.
  reviewing,

  /// Saving to the database.
  saving,
}

/// State for a track timing session.
class TrackTimingState extends Equatable {
  final TrackTimingPhase phase;
  final String side;
  final List<Track> tracks;
  final int currentTrackIndex;
  final int elapsedMs;
  final List<TrackDuration> recordedDurations;
  final String? error;

  const TrackTimingState({
    this.phase = TrackTimingPhase.idle,
    this.side = 'A',
    this.tracks = const [],
    this.currentTrackIndex = 0,
    this.elapsedMs = 0,
    this.recordedDurations = const [],
    this.error,
  });

  bool get isIdle => phase == TrackTimingPhase.idle;
  bool get isTiming => phase == TrackTimingPhase.timing;
  bool get isReviewing => phase == TrackTimingPhase.reviewing;
  bool get isSaving => phase == TrackTimingPhase.saving;
  bool get isActive => !isIdle;

  Track? get currentTrack =>
      currentTrackIndex < tracks.length ? tracks[currentTrackIndex] : null;

  bool get isLastTrack => currentTrackIndex >= tracks.length - 1;

  /// Elapsed time formatted as MM:SS.
  String get formattedElapsed {
    final totalSeconds = elapsedMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Elapsed time formatted as MM:SS.t (with tenths).
  String get formattedElapsedPrecise {
    final totalSeconds = elapsedMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final tenths = (elapsedMs % 1000) ~/ 100;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  TrackTimingState copyWith({
    TrackTimingPhase? phase,
    String? side,
    List<Track>? tracks,
    int? currentTrackIndex,
    int? elapsedMs,
    List<TrackDuration>? recordedDurations,
    String? error,
  }) {
    return TrackTimingState(
      phase: phase ?? this.phase,
      side: side ?? this.side,
      tracks: tracks ?? this.tracks,
      currentTrackIndex: currentTrackIndex ?? this.currentTrackIndex,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      recordedDurations: recordedDurations ?? this.recordedDurations,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        side,
        tracks,
        currentTrackIndex,
        elapsedMs,
        recordedDurations,
        error,
      ];
}

/// Manages a track timing session.
class TrackTimingNotifier extends StateNotifier<TrackTimingState> {
  TrackTimingNotifier(this._ref) : super(const TrackTimingState());

  final Ref _ref;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _displayTimer;

  /// Start a timing session for the given side's tracks.
  void start({required String side, required List<Track> tracks}) {
    _stopwatch.reset();
    _stopwatch.start();
    _startDisplayTimer();

    state = TrackTimingState(
      phase: TrackTimingPhase.timing,
      side: side,
      tracks: tracks,
      currentTrackIndex: 0,
      elapsedMs: 0,
      recordedDurations: [],
    );
  }

  /// Advance to the next track, recording the current track's duration.
  void nextTrack() {
    if (!state.isTiming) return;
    if (state.currentTrack == null) return;

    final durationSeconds = _stopwatch.elapsedMilliseconds ~/ 1000;
    final recorded = TrackDuration(
      position: state.currentTrack!.position,
      durationSeconds: durationSeconds,
    );

    final updatedDurations = [...state.recordedDurations, recorded];

    if (state.isLastTrack) {
      // Finished all tracks — move to review
      _stopwatch.stop();
      _displayTimer?.cancel();
      state = state.copyWith(
        phase: TrackTimingPhase.reviewing,
        recordedDurations: updatedDurations,
        elapsedMs: 0,
      );
    } else {
      // Move to next track, reset stopwatch
      _stopwatch.reset();
      _stopwatch.start();
      state = state.copyWith(
        currentTrackIndex: state.currentTrackIndex + 1,
        recordedDurations: updatedDurations,
        elapsedMs: 0,
      );
    }
  }

  /// Save the recorded durations to the database.
  Future<void> save() async {
    if (!state.isReviewing) return;

    state = state.copyWith(phase: TrackTimingPhase.saving);

    try {
      final nowPlaying = _ref.read(nowPlayingProvider);
      final albumId = nowPlaying.currentAlbum?.album?.id;
      final userId = _ref.read(currentUserIdProvider);

      if (albumId == null || userId == null) {
        state = state.copyWith(
          phase: TrackTimingPhase.reviewing,
          error: 'Missing album or user information',
        );
        return;
      }

      final trackDurationRepo = _ref.read(trackDurationRepositoryProvider);
      await trackDurationRepo.contributeTrackDurations(
        albumId: albumId,
        userId: userId,
        durations: state.recordedDurations,
        side: state.side,
      );

      // Re-fetch the album so the now playing state gets updated tracks
      final albumRepo = _ref.read(albumRepositoryProvider);
      final updatedLibraryAlbum =
          await albumRepo.getLibraryAlbum(nowPlaying.currentAlbum!.id);

      if (updatedLibraryAlbum != null) {
        // Refresh the now playing state with updated album data
        _ref
            .read(nowPlayingProvider.notifier)
            .refreshAlbum(updatedLibraryAlbum);
      }

      // Done — back to idle
      state = const TrackTimingState();
    } catch (e) {
      state = state.copyWith(
        phase: TrackTimingPhase.reviewing,
        error: 'Failed to save: $e',
      );
    }
  }

  /// Redo the timing session for the same side.
  void redo() {
    final tracks = state.tracks;
    final side = state.side;
    start(side: side, tracks: tracks);
  }

  /// Cancel the timing session.
  void cancel() {
    _stopwatch.stop();
    _stopwatch.reset();
    _displayTimer?.cancel();
    state = const TrackTimingState();
  }

  void _startDisplayTimer() {
    _displayTimer?.cancel();
    _displayTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && _stopwatch.isRunning) {
        state = state.copyWith(elapsedMs: _stopwatch.elapsedMilliseconds);
      }
    });
  }

  @override
  void dispose() {
    _stopwatch.stop();
    _displayTimer?.cancel();
    super.dispose();
  }
}

/// Provider for the track timing session.
final trackTimingProvider =
    StateNotifierProvider<TrackTimingNotifier, TrackTimingState>((ref) {
  return TrackTimingNotifier(ref);
});
