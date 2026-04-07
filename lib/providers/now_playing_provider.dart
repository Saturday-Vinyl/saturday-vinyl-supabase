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
  }

  final Ref _ref;
  final SharedPreferences _prefs;

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
      // Record the play in listening history
      final userId = _ref.read(currentUserIdProvider);
      if (userId != null) {
        final historyRepo = _ref.read(listeningHistoryRepositoryProvider);
        await historyRepo.recordPlay(
          userId: userId,
          libraryAlbumId: album.id,
          deviceId: null, // Manual selection, no device
        );
      }

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

        final started = await repo.startSession(
          sessionId: session.id,
          userId: userId,
        );

        if (mounted) {
          state = state.copyWith(cloudSessionId: started.id);
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

  /// Clear the now playing state.
  Future<void> clearNowPlaying() async {
    final sessionId = state.cloudSessionId;
    final wasPlaying = state.isPlaying;

    state = state.copyWith(clearAlbum: true);
    await _clearPersistedState();

    if (sessionId != null) {
      _syncToCloud(() async {
        final userId = _ref.read(currentUserIdProvider);
        if (userId == null) return;
        final repo = _ref.read(playbackSessionRepositoryProvider);

        if (wasPlaying) {
          await repo.stopSession(sessionId: sessionId, userId: userId);
        } else {
          await repo.cancelSession(sessionId: sessionId, userId: userId);
        }
      });
    }
  }

  /// Advance to the next side in the album's side sequence.
  ///
  /// Cycles through all available sides (A → B → C → ... → A).
  Future<void> toggleSide() async {
    final sides = state.availableSides;
    if (sides.length < 2) return;
    final currentIndex = sides.indexOf(state.currentSide);
    final newSide = sides[(currentIndex + 1) % sides.length];
    state = state.copyWith(
      currentSide: newSide,
      // Only reset timer if currently playing
      startedAt: state.isPlaying ? DateTime.now() : state.startedAt,
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
          side: newSide,
        );
      });
    }
  }

  /// Set the current side explicitly.
  Future<void> setSide(String side) async {
    final sides = state.availableSides;
    if (sides.isNotEmpty && !sides.contains(side.toUpperCase())) return;

    state = state.copyWith(
      currentSide: side,
      // Only reset timer if currently playing
      startedAt: state.isPlaying ? DateTime.now() : state.startedAt,
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

    // Record listening history when playback actually starts
    final album = state.currentAlbum;
    if (album != null) {
      final userId = _ref.read(currentUserIdProvider);
      if (userId != null) {
        final historyRepo = _ref.read(listeningHistoryRepositoryProvider);
        historyRepo
            .recordPlay(userId: userId, libraryAlbumId: album.id)
            .then((_) {}, onError: (e) {
          debugPrint('[NowPlaying] Failed to record listening history: $e');
        });
      }
    }

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

  /// Apply a side change from cloud.
  Future<void> applyCloudSideChange(
      String side, DateTime? sideStartedAt) async {
    state = state.copyWith(
      currentSide: side,
      startedAt: sideStartedAt,
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
