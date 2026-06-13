import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/playback_session.dart';
import 'package:saturday_consumer_app/models/track.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/library_view_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for persisting Now Playing state.
const String _nowPlayingAlbumIdKey = 'now_playing_album_id';
const String _nowPlayingStartedAtKey = 'now_playing_started_at';
const String _nowPlayingCurrentSideKey = 'now_playing_current_side';
const String _nowPlayingSessionIdKey = 'now_playing_session_id';
const String _nowPlayingStatusKey = 'now_playing_status';

/// Source of the Now Playing album.
enum NowPlayingSource {
  /// Album was manually selected by the user.
  manual,

  /// Album was auto-detected by a Saturday Hub.
  autoDetected,
}

/// Status of the Now Playing session.
enum NowPlayingStatus {
  /// No album selected.
  idle,

  /// Album detected/selected but playback not yet started.
  queued,

  /// Album is actively playing with timer running.
  playing,
}

/// Represents the current state of Now Playing.
class NowPlayingState extends Equatable {
  /// Whether the state is currently loading.
  final bool isLoading;

  /// The currently playing album.
  final LibraryAlbum? currentAlbum;

  /// When the current side started playing.
  final DateTime? startedAt;

  /// The current side being played (A or B).
  final String currentSide;

  /// Error message if something went wrong.
  final String? error;

  /// The source of this now playing (manual selection or auto-detected).
  final NowPlayingSource source;

  /// The name of the device that detected the album (if auto-detected).
  final String? detectedByDevice;

  /// The playback session status.
  final NowPlayingStatus status;

  /// The ID of the cloud playback session, if synced.
  final String? cloudSessionId;

  const NowPlayingState({
    this.isLoading = false,
    this.currentAlbum,
    this.startedAt,
    this.currentSide = 'A',
    this.error,
    this.source = NowPlayingSource.manual,
    this.detectedByDevice,
    this.status = NowPlayingStatus.idle,
    this.cloudSessionId,
  });

  /// Whether there is something currently playing (timer running).
  bool get isPlaying => status == NowPlayingStatus.playing;

  /// Whether an album is queued but not yet playing.
  bool get isQueued => status == NowPlayingStatus.queued;

  /// Whether there is an active session (queued or playing).
  bool get isActive => isPlaying || isQueued;

  /// All unique side letters present in the album's tracks, sorted.
  ///
  /// Extracts the leading letter from each track position (e.g. "A1" → "A",
  /// "C3" → "C") and returns them in alphabetical order.
  List<String> get availableSides {
    final album = currentAlbum?.album;
    if (album == null) return [];

    final sides = <String>{};
    for (final track in album.tracks) {
      final pos = track.position.trim().toUpperCase();
      if (pos.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(pos)) {
        sides.add(pos[0]);
      }
    }
    final sorted = sides.toList()..sort();
    return sorted;
  }

  /// Get tracks for a specific side letter.
  List<Track> tracksForSide(String side) {
    final album = currentAlbum?.album;
    if (album == null) return [];

    return album.tracks.where((track) {
      final pos = track.position.trim().toUpperCase();
      return pos.startsWith(side.toUpperCase());
    }).toList();
  }

  /// Get tracks for the current side.
  List<Track> get currentSideTracks => tracksForSide(currentSide);

  /// Total duration of a specific side in seconds.
  int durationForSide(String side) {
    return tracksForSide(side).fold<int>(
      0,
      (sum, track) => sum + (track.durationSeconds ?? 0),
    );
  }

  /// Total duration of the current side in seconds.
  int get currentSideDurationSeconds => durationForSide(currentSide);

  /// Map of side letter → duration in seconds, for all available sides.
  Map<String, int> get sideDurations {
    return {for (final side in availableSides) side: durationForSide(side)};
  }

  /// Whether the album has side-based track structure.
  bool get hasSides => availableSides.length > 1;

  /// Whether the current side has tracks with missing durations.
  bool get currentSideHasMissingDurations {
    final tracks = currentSideTracks;
    if (tracks.isEmpty) return false;
    return tracks.any((track) => track.durationSeconds == null);
  }

  /// Whether this was auto-detected by a hub.
  bool get isAutoDetected => source == NowPlayingSource.autoDetected;

  /// Creates a copy of this state with optional new values.
  NowPlayingState copyWith({
    bool? isLoading,
    LibraryAlbum? currentAlbum,
    DateTime? startedAt,
    String? currentSide,
    String? error,
    NowPlayingSource? source,
    String? detectedByDevice,
    NowPlayingStatus? status,
    String? cloudSessionId,
    bool clearAlbum = false,
    bool clearDetectedByDevice = false,
    bool clearStartedAt = false,
    bool clearCloudSessionId = false,
  }) {
    return NowPlayingState(
      isLoading: isLoading ?? this.isLoading,
      currentAlbum: clearAlbum ? null : (currentAlbum ?? this.currentAlbum),
      startedAt: clearAlbum || clearStartedAt
          ? null
          : (startedAt ?? this.startedAt),
      currentSide: currentSide ?? this.currentSide,
      error: error,
      source: clearAlbum ? NowPlayingSource.manual : (source ?? this.source),
      detectedByDevice: clearAlbum || clearDetectedByDevice
          ? null
          : (detectedByDevice ?? this.detectedByDevice),
      status: clearAlbum
          ? NowPlayingStatus.idle
          : (status ?? this.status),
      cloudSessionId: clearAlbum || clearCloudSessionId
          ? null
          : (cloudSessionId ?? this.cloudSessionId),
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        currentAlbum,
        startedAt,
        currentSide,
        error,
        source,
        detectedByDevice,
        status,
        cloudSessionId,
      ];
}

/// StateNotifier for managing Now Playing state.
class NowPlayingNotifier extends StateNotifier<NowPlayingState> {
  NowPlayingNotifier(this._ref, this._prefs) : super(const NowPlayingState()) {
    _restoreState();
    // Whenever state changes, recompute when (if ever) the current side
    // should end on its own. The listener fires synchronously after the
    // state assignment, so reading `state` here returns the new value.
    addListener((_) => _scheduleSideEnd());
  }

  final Ref _ref;
  final SharedPreferences _prefs;

  /// One-shot timer that fires when the current side's elapsed time
  /// reaches its total duration. Cancelled and re-scheduled whenever
  /// state changes; null when the side has no known duration, when
  /// not playing, or when the side has already ended.
  Timer? _sideEndTimer;

  /// Restore persisted state on initialization.
  Future<void> _restoreState() async {
    final albumId = _prefs.getString(_nowPlayingAlbumIdKey);
    final startedAtMillis = _prefs.getInt(_nowPlayingStartedAtKey);
    final currentSide = _prefs.getString(_nowPlayingCurrentSideKey) ?? 'A';
    final sessionId = _prefs.getString(_nowPlayingSessionIdKey);
    final statusStr = _prefs.getString(_nowPlayingStatusKey);

    if (albumId == null) {
      return; // No persisted state
    }

    state = state.copyWith(isLoading: true);

    try {
      // Fetch the album from the repository
      final albumRepo = _ref.read(albumRepositoryProvider);
      final album = await albumRepo.getLibraryAlbum(albumId);

      if (album != null) {
        final startedAt = startedAtMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(startedAtMillis)
            : null;

        // Determine status from persisted value
        NowPlayingStatus restoredStatus;
        if (statusStr == 'playing' && startedAt != null) {
          restoredStatus = NowPlayingStatus.playing;
        } else if (statusStr == 'queued') {
          restoredStatus = NowPlayingStatus.queued;
        } else if (startedAt != null) {
          // Legacy: no status persisted but has startedAt → playing
          restoredStatus = NowPlayingStatus.playing;
        } else {
          restoredStatus = NowPlayingStatus.idle;
        }

        state = state.copyWith(
          isLoading: false,
          currentAlbum: album,
          startedAt: startedAt,
          currentSide: currentSide,
          status: restoredStatus,
          cloudSessionId: sessionId,
        );
      } else {
        // Album no longer exists, clear persisted state
        await _clearPersistedState();
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      // Failed to restore, clear state
      await _clearPersistedState();
      state = state.copyWith(isLoading: false);
    }
  }

  /// Persist the current state to SharedPreferences.
  Future<void> _persistState() async {
    final album = state.currentAlbum;

    if (album != null && state.status != NowPlayingStatus.idle) {
      await _prefs.setString(_nowPlayingAlbumIdKey, album.id);
      final startedAt = state.startedAt;
      if (startedAt != null) {
        await _prefs.setInt(
            _nowPlayingStartedAtKey, startedAt.millisecondsSinceEpoch);
      } else {
        await _prefs.remove(_nowPlayingStartedAtKey);
      }
      await _prefs.setString(_nowPlayingCurrentSideKey, state.currentSide);
      await _prefs.setString(_nowPlayingStatusKey, state.status.name);
      final sessionId = state.cloudSessionId;
      if (sessionId != null) {
        await _prefs.setString(_nowPlayingSessionIdKey, sessionId);
      }
    } else {
      await _clearPersistedState();
    }
  }

  /// Clear persisted state from SharedPreferences.
  Future<void> _clearPersistedState() async {
    await _prefs.remove(_nowPlayingAlbumIdKey);
    await _prefs.remove(_nowPlayingStartedAtKey);
    await _prefs.remove(_nowPlayingCurrentSideKey);
    await _prefs.remove(_nowPlayingSessionIdKey);
    await _prefs.remove(_nowPlayingStatusKey);
  }

  /// Fire-and-forget cloud sync wrapper.
  void _syncToCloud(Future<void> Function() action) {
    action().catchError((e) {
      debugPrint('[NowPlaying] Cloud sync error (non-blocking): $e');
    });
  }

  /// Build a tracks snapshot for the cloud session.
  List<Map<String, dynamic>>? _buildTracksSnapshot(LibraryAlbum album) {
    final tracks = album.album?.tracks;
    if (tracks == null || tracks.isEmpty) return null;
    return tracks
        .map((t) => {
              'position': t.position,
              'title': t.title,
              'duration_seconds': t.durationSeconds,
            })
        .toList();
  }

  /// Calculate total duration for a side.
  int? _calculateSideDuration(LibraryAlbum album, String side) {
    final tracks = album.album?.tracks;
    if (tracks == null) return null;
    final sideTracks = tracks
        .where((t) => t.position.trim().toUpperCase().startsWith(side));
    final total =
        sideTracks.fold<int>(0, (sum, t) => sum + (t.durationSeconds ?? 0));
    return total > 0 ? total : null;
  }


  /// Set an album as now playing (app-initiated, immediate playback).
  Future<void> setNowPlaying(LibraryAlbum album) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
    );

    try {
      state = state.copyWith(
        isLoading: false,
        currentAlbum: album,
        startedAt: DateTime.now(),
        currentSide: 'A',
        status: NowPlayingStatus.playing,
        source: NowPlayingSource.manual,
        clearDetectedByDevice: true,
      );

      // Persist the state so timer survives app restarts
      await _persistState();

      // Fire-and-forget cloud sync: queue + immediately start
      _syncToCloud(() async {
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = _ref.read(playbackSessionRepositoryProvider);

        final session = await repo.queueSession(
          userId: userId,
          libraryAlbumId: album.id,
          albumTitle: album.album?.title,
          albumArtist: album.album?.artist,
          coverImageUrl: album.album?.coverImageUrl,
          tracks: _buildTracksSnapshot(album),
          sideADurationSeconds: _calculateSideDuration(album, 'A'),
          sideBDurationSeconds: _calculateSideDuration(album, 'B'),
        );

        await repo.startSession(
          sessionId: session.id,
          userId: userId,
        );

        if (mounted) {
          state = state.copyWith(cloudSessionId: session.id);
          await _persistState();
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to set now playing: $e',
      );
    }
  }

  /// Place an album on the stand in queued state, without starting playback.
  ///
  /// Mirrors the physical ritual: placing a record on the stand doesn't
  /// start it — the listener still has to drop the needle. The room
  /// transitions to playing when [startPlaying] is called from the stand.
  Future<void> queueOnStand(LibraryAlbum album) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      state = state.copyWith(
        isLoading: false,
        currentAlbum: album,
        currentSide: 'A',
        status: NowPlayingStatus.queued,
        source: NowPlayingSource.manual,
        clearStartedAt: true,
        clearDetectedByDevice: true,
      );

      await _persistState();

      _syncToCloud(() async {
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = _ref.read(playbackSessionRepositoryProvider);

        final session = await repo.queueSession(
          userId: userId,
          libraryAlbumId: album.id,
          albumTitle: album.album?.title,
          albumArtist: album.album?.artist,
          coverImageUrl: album.album?.coverImageUrl,
          tracks: _buildTracksSnapshot(album),
          sideADurationSeconds: _calculateSideDuration(album, 'A'),
          sideBDurationSeconds: _calculateSideDuration(album, 'B'),
        );

        if (mounted) {
          state = state.copyWith(cloudSessionId: session.id);
          await _persistState();
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to queue on stand: $e',
      );
    }
  }

  /// Clear the now playing state.
  ///
  /// Emits `session_cancelled` regardless of prior local status. Under
  /// the v2 protocol this is the only terminal event; the trigger
  /// gracefully accumulates any open play window into
  /// `play_seconds_total` before terminating, so the producer doesn't
  /// need to chain a `playback_stopped` first.
  Future<void> clearNowPlaying() async {
    final sessionId = state.cloudSessionId;

    state = state.copyWith(clearAlbum: true);
    await _clearPersistedState();

    if (sessionId != null) {
      _syncToCloud(() async {
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = _ref.read(playbackSessionRepositoryProvider);
        await repo.cancelSession(sessionId: sessionId, userId: userId);
      });
    }
  }

  /// Advance to the next side in the album's side sequence.
  ///
  /// Cycles through all available sides (A → B → C → ... → A). Under
  /// the v2 protocol a `side_changed` always lands the session in
  /// `queued` — the listener resumes via [startPlaying].
  Future<void> toggleSide() async {
    final sides = state.availableSides;
    if (sides.length < 2) return;
    final currentIndex = sides.indexOf(state.currentSide);
    final newSide = sides[(currentIndex + 1) % sides.length];
    await setSide(newSide);
  }

  /// Set the current side explicitly.
  ///
  /// Always lands locally in [NowPlayingStatus.queued]; if the session
  /// was playing, `startedAt` is cleared. Emits `side_changed` to the
  /// cloud — the v2 trigger accumulates the open play window into
  /// `play_seconds_total` and transitions the session to queued.
  Future<void> setSide(String side) async {
    final sides = state.availableSides;
    if (sides.isNotEmpty && !sides.contains(side.toUpperCase())) return;
    if (state.currentAlbum == null) return;

    state = state.copyWith(
      currentSide: side,
      status: NowPlayingStatus.queued,
      clearStartedAt: true,
    );
    await _persistState();

    final sessionId = state.cloudSessionId;
    if (sessionId != null) {
      _syncToCloud(() async {
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = _ref.read(playbackSessionRepositoryProvider);
        await repo.changeSide(
          sessionId: sessionId,
          userId: userId,
          side: side,
        );
      });
    }
  }

  /// Refresh the album data in the current state.
  ///
  /// Called after track durations are contributed to update the UI
  /// with the newly recorded durations.
  void refreshAlbum(LibraryAlbum updatedAlbum) {
    if (state.currentAlbum?.id == updatedAlbum.id) {
      state = state.copyWith(currentAlbum: updatedAlbum);
    }
  }

  /// Clear any error state.
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Set an album as now playing from auto-detection (hub).
  ///
  /// Hub-detected albums are set to **queued** status.
  /// The user must call [startPlaying] to begin playback.
  Future<void> setAutoDetected(
    LibraryAlbum album, {
    required String deviceName,
    DateTime? detectedAt,
  }) async {
    state = state.copyWith(
      isLoading: true,
      error: null,
    );

    try {
      // Set as QUEUED — do NOT record listening history yet
      state = state.copyWith(
        isLoading: false,
        currentAlbum: album,
        currentSide: 'A',
        source: NowPlayingSource.autoDetected,
        detectedByDevice: deviceName,
        status: NowPlayingStatus.queued,
        clearStartedAt: true,
      );

      await _persistState();

      // Fire-and-forget: create queued cloud session
      _syncToCloud(() async {
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = _ref.read(playbackSessionRepositoryProvider);

        final session = await repo.queueSession(
          userId: userId,
          libraryAlbumId: album.id,
          albumTitle: album.album?.title,
          albumArtist: album.album?.artist,
          coverImageUrl: album.album?.coverImageUrl,
          tracks: _buildTracksSnapshot(album),
          sideADurationSeconds: _calculateSideDuration(album, 'A'),
          sideBDurationSeconds: _calculateSideDuration(album, 'B'),
          sourceType: 'hub',
        );

        if (mounted) {
          state = state.copyWith(cloudSessionId: session.id);
          await _persistState();
        }
      });
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to set now playing: $e',
      );
    }
  }

  /// Stop active playback without lifting the record off the stand.
  ///
  /// Transitions from [NowPlayingStatus.playing] back to
  /// [NowPlayingStatus.queued]: the album, current side, and cloud
  /// session id are preserved so the listener can drop the needle again
  /// (on the same side or a different one) without having to re-queue
  /// the record. To actually clear the stand, use [clearNowPlaying].
  ///
  /// Emits the canonical `playback_stopped` event under the v2
  /// playback-event protocol — non-terminal: the trigger transitions
  /// the cloud session to `queued`, clears `side_started_at`, and
  /// accumulates the open play window into `play_seconds_total`.
  Future<void> stopPlaying() async {
    if (state.status != NowPlayingStatus.playing) return;

    state = state.copyWith(
      status: NowPlayingStatus.queued,
      clearStartedAt: true,
    );
    await _persistState();

    final sessionId = state.cloudSessionId;
    if (sessionId != null) {
      _syncToCloud(() async {
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = _ref.read(playbackSessionRepositoryProvider);
        await repo.stopPlayback(sessionId: sessionId, userId: userId);
      });
    }
  }

  /// Start playback on a queued album.
  ///
  /// Transitions from [NowPlayingStatus.queued] to [NowPlayingStatus.playing].
  Future<void> startPlaying() async {
    if (state.status != NowPlayingStatus.queued) return;

    state = state.copyWith(
      status: NowPlayingStatus.playing,
      startedAt: DateTime.now(),
    );
    await _persistState();

    final sessionId = state.cloudSessionId;
    if (sessionId != null) {
      _syncToCloud(() async {
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = _ref.read(playbackSessionRepositoryProvider);
        await repo.startSession(
          sessionId: sessionId,
          userId: userId,
        );
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud sync entry points (called by PlaybackSyncProvider)
  // ---------------------------------------------------------------------------

  /// Apply a full cloud session. Cloud always wins.
  ///
  /// Called by [PlaybackSyncProvider] when a remote event indicates state
  /// that differs from local. The [album] must be pre-fetched by the caller.
  Future<void> applyCloudSession({
    required PlaybackSession session,
    required LibraryAlbum album,
  }) async {
    final newStatus = session.isPlaying
        ? NowPlayingStatus.playing
        : session.isQueued
            ? NowPlayingStatus.queued
            : NowPlayingStatus.idle;

    if (newStatus == NowPlayingStatus.idle) {
      await applyCloudClear();
      return;
    }

    state = state.copyWith(
      isLoading: false,
      currentAlbum: album,
      startedAt: session.sideStartedAt,
      currentSide: session.currentSide,
      status: newStatus,
      cloudSessionId: session.id,
      source: session.queuedBySource == 'hub'
          ? NowPlayingSource.autoDetected
          : NowPlayingSource.manual,
      clearDetectedByDevice: session.queuedBySource != 'hub',
    );
    await _persistState();
  }

  /// Clear local state in response to a cloud stop/cancel event.
  Future<void> applyCloudClear() async {
    state = state.copyWith(clearAlbum: true);
    await _clearPersistedState();
  }

  /// Apply a `side_changed` event from cloud.
  ///
  /// Under the v2 protocol this always lands the session in
  /// [NowPlayingStatus.queued] with the new side selected. Local
  /// `startedAt` is cleared so the side-end timer doesn't fire stale.
  Future<void> applyCloudSideChange(String side) async {
    state = state.copyWith(
      currentSide: side,
      status: NowPlayingStatus.queued,
      clearStartedAt: true,
    );
    await _persistState();
  }

  /// Apply a `playback_stopped` event from cloud.
  ///
  /// Under the v2 protocol this is the no-side-change pause — session
  /// goes to [NowPlayingStatus.queued], same side, `startedAt` cleared.
  /// The album stays on the local stand.
  Future<void> applyCloudPlaybackStopped() async {
    state = state.copyWith(
      status: NowPlayingStatus.queued,
      clearStartedAt: true,
    );
    await _persistState();
  }

  /// Apply playback_started from cloud (queued → playing).
  Future<void> applyCloudPlaybackStarted(DateTime? sideStartedAt) async {
    state = state.copyWith(
      status: NowPlayingStatus.playing,
      startedAt: sideStartedAt,
    );
    await _persistState();
  }

  // ---------------------------------------------------------------------------
  // Side-end auto-transition
  // ---------------------------------------------------------------------------

  /// Recompute the side-end timer based on the current state.
  ///
  /// Cancels any pending timer and, if the current state is playing with a
  /// known side duration, schedules a one-shot fire at the moment elapsed
  /// reaches the side's total. If the side has already ended (e.g. timer
  /// missed while the app was backgrounded), fires synchronously on the
  /// next event loop turn.
  void _scheduleSideEnd() {
    _sideEndTimer?.cancel();
    _sideEndTimer = null;

    if (state.status != NowPlayingStatus.playing) return;
    final startedAt = state.startedAt;
    final durationSeconds = state.currentSideDurationSeconds;
    if (startedAt == null || durationSeconds <= 0) return;

    final endsAt = startedAt.add(Duration(seconds: durationSeconds));
    final remaining = endsAt.difference(DateTime.now());

    if (remaining.isNegative || remaining == Duration.zero) {
      // Already past — fire on the next tick to avoid mutating state
      // mid-listener.
      _sideEndTimer = Timer(Duration.zero, _onSideEnded);
    } else {
      _sideEndTimer = Timer(remaining, _onSideEnded);
    }
  }

  void _onSideEnded() {
    // Re-check at fire time: state may have changed since scheduling.
    if (state.status != NowPlayingStatus.playing) return;
    endCurrentSide();
  }

  /// Called when the current side has finished playing.
  ///
  /// Always transitions the session to [NowPlayingStatus.queued]. If
  /// there's another iterable side, the next side is pre-selected and
  /// `side_changed` is emitted; otherwise the current side stays
  /// selected and `playback_stopped` is emitted. Either way the record
  /// stays on the stand, awaiting another drop of the needle or a
  /// manual clear.
  ///
  /// The cloud session is preserved across this transition under the v2
  /// protocol — both events are non-terminal and accumulate the open
  /// play window into `play_seconds_total`.
  Future<void> endCurrentSide() async {
    if (state.status != NowPlayingStatus.playing) return;

    final sides = state.availableSides;
    final currentIndex = sides.indexOf(state.currentSide);
    final hasNextSide = sides.length > 1 && currentIndex < sides.length - 1;
    final nextSide = hasNextSide ? sides[currentIndex + 1] : state.currentSide;

    state = state.copyWith(
      status: NowPlayingStatus.queued,
      currentSide: nextSide,
      clearStartedAt: true,
    );
    await _persistState();

    final sessionId = state.cloudSessionId;
    if (sessionId == null) return;

    _syncToCloud(() async {
      final userId = _ref.read(currentUserIdProvider);
      if (userId == null) return;
      final repo = _ref.read(playbackSessionRepositoryProvider);
      if (hasNextSide) {
        await repo.changeSide(
          sessionId: sessionId,
          userId: userId,
          side: nextSide,
        );
      } else {
        await repo.stopPlayback(sessionId: sessionId, userId: userId);
      }
    });
  }

  // ---------------------------------------------------------------------------

  /// Clear the now playing state from auto-detection.
  ///
  /// Called when a record is removed from the hub.
  /// Only cancels if currently **queued** — does NOT stop active playback.
  Future<void> clearAutoDetected() async {
    if (state.source != NowPlayingSource.autoDetected) return;
    if (state.status != NowPlayingStatus.queued) return;

    final sessionId = state.cloudSessionId;

    state = state.copyWith(clearAlbum: true);
    await _clearPersistedState();

    if (sessionId != null) {
      _syncToCloud(() async {
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = _ref.read(playbackSessionRepositoryProvider);
        await repo.cancelSession(sessionId: sessionId, userId: userId);
      });
    }
  }

  @override
  void dispose() {
    _sideEndTimer?.cancel();
    super.dispose();
  }
}

/// Provider for the Now Playing state notifier.
final nowPlayingProvider =
    StateNotifierProvider<NowPlayingNotifier, NowPlayingState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return NowPlayingNotifier(ref, prefs);
});

/// Provider for just the currently playing album.
final currentPlayingAlbumProvider = Provider<LibraryAlbum?>((ref) {
  return ref.watch(nowPlayingProvider).currentAlbum;
});

/// Provider for whether something is currently playing.
final isPlayingProvider = Provider<bool>((ref) {
  return ref.watch(nowPlayingProvider).isPlaying;
});

/// Provider for recently played albums.
///
/// Returns unique albums from the user's listening history,
/// ordered by most recent play time.
final recentlyPlayedProvider =
    FutureProvider<List<LibraryAlbum>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final historyRepo = ref.watch(listeningHistoryRepositoryProvider);
  return historyRepo.getRecentlyPlayed(userId, limit: 10);
});
