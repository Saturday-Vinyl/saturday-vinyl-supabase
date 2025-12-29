import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/track.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

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

  const NowPlayingState({
    this.isLoading = false,
    this.currentAlbum,
    this.startedAt,
    this.currentSide = 'A',
    this.error,
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

  /// Creates a copy of this state with optional new values.
  NowPlayingState copyWith({
    bool? isLoading,
    LibraryAlbum? currentAlbum,
    DateTime? startedAt,
    String? currentSide,
    String? error,
    bool clearAlbum = false,
  }) {
    return NowPlayingState(
      isLoading: isLoading ?? this.isLoading,
      currentAlbum: clearAlbum ? null : (currentAlbum ?? this.currentAlbum),
      startedAt: clearAlbum ? null : (startedAt ?? this.startedAt),
      currentSide: currentSide ?? this.currentSide,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        currentAlbum,
        startedAt,
        currentSide,
        error,
      ];
}

/// StateNotifier for managing Now Playing state.
class NowPlayingNotifier extends StateNotifier<NowPlayingState> {
  NowPlayingNotifier(this._ref) : super(const NowPlayingState());

  final Ref _ref;

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
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to set now playing: $e',
      );
    }
  }

  /// Clear the now playing state.
  void clearNowPlaying() {
    state = state.copyWith(clearAlbum: true);
  }

  /// Switch the current side (A to B or B to A).
  void toggleSide() {
    final newSide = state.currentSide == 'A' ? 'B' : 'A';
    state = state.copyWith(
      currentSide: newSide,
      startedAt: DateTime.now(), // Reset timer when switching sides
    );
  }

  /// Set the current side explicitly.
  void setSide(String side) {
    if (side == 'A' || side == 'B') {
      state = state.copyWith(
        currentSide: side,
        startedAt: DateTime.now(),
      );
    }
  }

  /// Clear any error state.
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Provider for the Now Playing state notifier.
final nowPlayingProvider =
    StateNotifierProvider<NowPlayingNotifier, NowPlayingState>((ref) {
  return NowPlayingNotifier(ref);
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
