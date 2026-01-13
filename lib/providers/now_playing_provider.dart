import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/track.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/library_view_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for persisting Now Playing state.
const String _nowPlayingAlbumIdKey = 'now_playing_album_id';
const String _nowPlayingStartedAtKey = 'now_playing_started_at';
const String _nowPlayingCurrentSideKey = 'now_playing_current_side';

/// Source of the Now Playing album.
enum NowPlayingSource {
  /// Album was manually selected by the user.
  manual,

  /// Album was auto-detected by a Saturday Hub.
  autoDetected,
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

  const NowPlayingState({
    this.isLoading = false,
    this.currentAlbum,
    this.startedAt,
    this.currentSide = 'A',
    this.error,
    this.source = NowPlayingSource.manual,
    this.detectedByDevice,
  });

  /// Whether there is something currently playing.
  bool get isPlaying => currentAlbum != null;

  /// Get tracks for the current side.
  List<Track> get currentSideTracks {
    final album = currentAlbum?.album;
    if (album == null) return [];

    return album.tracks.where((track) {
      final pos = track.position.trim().toUpperCase();
      if (pos.isEmpty) return false;
      // Match tracks that start with the current side letter
      return pos.startsWith(currentSide);
    }).toList();
  }

  /// Get tracks for Side A.
  List<Track> get sideATracks {
    final album = currentAlbum?.album;
    if (album == null) return [];

    return album.tracks.where((track) {
      final pos = track.position.trim().toUpperCase();
      return pos.startsWith('A');
    }).toList();
  }

  /// Get tracks for Side B.
  List<Track> get sideBTracks {
    final album = currentAlbum?.album;
    if (album == null) return [];

    return album.tracks.where((track) {
      final pos = track.position.trim().toUpperCase();
      return pos.startsWith('B');
    }).toList();
  }

  /// Total duration of the current side in seconds.
  int get currentSideDurationSeconds {
    return currentSideTracks.fold<int>(
      0,
      (sum, track) => sum + (track.durationSeconds ?? 0),
    );
  }

  /// Total duration of Side A in seconds.
  int get sideADurationSeconds {
    return sideATracks.fold<int>(
      0,
      (sum, track) => sum + (track.durationSeconds ?? 0),
    );
  }

  /// Total duration of Side B in seconds.
  int get sideBDurationSeconds {
    return sideBTracks.fold<int>(
      0,
      (sum, track) => sum + (track.durationSeconds ?? 0),
    );
  }

  /// Whether the album has Side A/B track structure.
  bool get hasSides {
    final album = currentAlbum?.album;
    if (album == null) return false;

    // Check if any tracks have A or B prefixes
    return album.tracks.any((track) {
      final pos = track.position.trim().toUpperCase();
      return pos.startsWith('A') || pos.startsWith('B');
    });
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
    bool clearAlbum = false,
    bool clearDetectedByDevice = false,
  }) {
    return NowPlayingState(
      isLoading: isLoading ?? this.isLoading,
      currentAlbum: clearAlbum ? null : (currentAlbum ?? this.currentAlbum),
      startedAt: clearAlbum ? null : (startedAt ?? this.startedAt),
      currentSide: currentSide ?? this.currentSide,
      error: error,
      source: clearAlbum ? NowPlayingSource.manual : (source ?? this.source),
      detectedByDevice: clearAlbum || clearDetectedByDevice
          ? null
          : (detectedByDevice ?? this.detectedByDevice),
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

    if (albumId == null || startedAtMillis == null) {
      return; // No persisted state
    }

    state = state.copyWith(isLoading: true);

    try {
      // Fetch the album from the repository
      final albumRepo = _ref.read(albumRepositoryProvider);
      final album = await albumRepo.getLibraryAlbum(albumId);

      if (album != null) {
        final startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMillis);
        state = state.copyWith(
          isLoading: false,
          currentAlbum: album,
          startedAt: startedAt,
          currentSide: currentSide,
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
    final startedAt = state.startedAt;

    if (album != null && startedAt != null) {
      await _prefs.setString(_nowPlayingAlbumIdKey, album.id);
      await _prefs.setInt(
          _nowPlayingStartedAtKey, startedAt.millisecondsSinceEpoch);
      await _prefs.setString(_nowPlayingCurrentSideKey, state.currentSide);
    } else {
      await _clearPersistedState();
    }
  }

  /// Clear persisted state from SharedPreferences.
  Future<void> _clearPersistedState() async {
    await _prefs.remove(_nowPlayingAlbumIdKey);
    await _prefs.remove(_nowPlayingStartedAtKey);
    await _prefs.remove(_nowPlayingCurrentSideKey);
  }

  /// Set an album as now playing.
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
      );

      // Persist the state so timer survives app restarts
      await _persistState();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to set now playing: $e',
      );
    }
  }

  /// Clear the now playing state.
  Future<void> clearNowPlaying() async {
    state = state.copyWith(clearAlbum: true);
    await _clearPersistedState();
  }

  /// Switch the current side (A to B or B to A).
  Future<void> toggleSide() async {
    final newSide = state.currentSide == 'A' ? 'B' : 'A';
    state = state.copyWith(
      currentSide: newSide,
      startedAt: DateTime.now(), // Reset timer when switching sides
    );
    await _persistState();
  }

  /// Set the current side explicitly.
  Future<void> setSide(String side) async {
    if (side == 'A' || side == 'B') {
      state = state.copyWith(
        currentSide: side,
        startedAt: DateTime.now(),
      );
      await _persistState();
    }
  }

  /// Clear any error state.
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Set an album as now playing from auto-detection (hub).
  ///
  /// Auto-detected albums take priority over manual selections.
  /// This is called by the realtime provider when a hub detects a record.
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
      // Record the play in listening history
      final userId = _ref.read(currentUserIdProvider);
      if (userId != null) {
        final historyRepo = _ref.read(listeningHistoryRepositoryProvider);
        await historyRepo.recordPlay(
          userId: userId,
          libraryAlbumId: album.id,
          deviceId: null, // TODO: Pass actual device ID when available
        );
      }

      state = state.copyWith(
        isLoading: false,
        currentAlbum: album,
        startedAt: detectedAt ?? DateTime.now(),
        currentSide: 'A',
        source: NowPlayingSource.autoDetected,
        detectedByDevice: deviceName,
      );

      // Persist the state so timer survives app restarts
      await _persistState();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to set now playing: $e',
      );
    }
  }

  /// Clear the now playing state from auto-detection.
  ///
  /// Called when a record is removed from the hub.
  Future<void> clearAutoDetected() async {
    // Only clear if the current album was auto-detected
    if (state.source == NowPlayingSource.autoDetected) {
      state = state.copyWith(clearAlbum: true);
      await _clearPersistedState();
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
