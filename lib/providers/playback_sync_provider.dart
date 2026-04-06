import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/playback_event.dart';
import 'package:saturday_consumer_app/models/playback_session.dart';
import 'package:saturday_consumer_app/providers/auth_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// State for the playback sync provider.
class PlaybackSyncState {
  final bool isInitialized;
  final String? error;

  const PlaybackSyncState({
    this.isInitialized = false,
    this.error,
  });

  PlaybackSyncState copyWith({
    bool? isInitialized,
    String? error,
    bool clearError = false,
  }) {
    return PlaybackSyncState(
      isInitialized: isInitialized ?? this.isInitialized,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Syncs cloud playback sessions with local NowPlaying state.
///
/// On initialization, fetches the user's active cloud session and
/// populates [NowPlayingNotifier]. Then subscribes to [playback_events]
/// via Supabase Realtime to keep all devices in sync.
///
/// Self-echo is handled via idempotent state checks: since local state
/// updates immediately before the fire-and-forget cloud write, the
/// Realtime echo arrives when local state already reflects the change.
class PlaybackSyncNotifier extends StateNotifier<PlaybackSyncState> {
  PlaybackSyncNotifier(this._ref) : super(const PlaybackSyncState()) {
    _ref.listen<String?>(currentUserIdProvider, (previous, next) {
      if (next != null && previous != next) {
        _initialize();
      } else if (next == null && previous != null) {
        _cleanup();
      }
    });
    _initialize();
  }

  final Ref _ref;
  RealtimeChannel? _channel;
  bool _isInitialized = false;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> _initialize() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    await _cleanup();

    try {
      await _fetchAndApplyActiveSession(userId);
      _subscribeToPlaybackEvents(userId);
      _isInitialized = true;
      state = state.copyWith(isInitialized: true, clearError: true);
    } catch (e) {
      debugPrint('[PlaybackSync] Init error: $e');
      state = state.copyWith(error: 'Failed to initialize sync: $e');
    }
  }

  Future<void> _cleanup() async {
    await _channel?.unsubscribe();
    _channel = null;
    _isInitialized = false;
    state = const PlaybackSyncState();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Foreground recovery
  // ---------------------------------------------------------------------------

  /// Called when the app returns to foreground to catch missed events.
  Future<void> onAppResumed() async {
    if (!_isInitialized) return;
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    try {
      await _fetchAndApplyActiveSession(userId);
    } catch (e) {
      debugPrint('[PlaybackSync] Foreground recovery error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Fetch active session on startup / foreground
  // ---------------------------------------------------------------------------

  Future<void> _fetchAndApplyActiveSession(String userId) async {
    final repo = _ref.read(playbackSessionRepositoryProvider);
    final sessions = await repo.getActiveSessions(userId);

    if (sessions.isEmpty) {
      // No active cloud sessions — if local state thinks it has one, clear it
      final localState = _ref.read(nowPlayingProvider);
      if (localState.cloudSessionId != null && localState.isActive) {
        debugPrint(
            '[PlaybackSync] No active cloud sessions but local is active — clearing');
        _ref.read(nowPlayingProvider.notifier).applyCloudClear();
      }
      return;
    }

    // Prefer playing over queued
    final playing = sessions.where((s) => s.isPlaying).firstOrNull;
    final queued = sessions.where((s) => s.isQueued).firstOrNull;
    final session = playing ?? queued;

    if (session == null) return;

    // Check if local state already matches
    final localState = _ref.read(nowPlayingProvider);
    if (localState.cloudSessionId == session.id &&
        localState.currentSide == session.currentSide &&
        ((session.isPlaying && localState.isPlaying) ||
            (session.isQueued && localState.isQueued))) {
      return; // Already in sync
    }

    final album = await _resolveAlbumForSession(session);
    if (album == null) {
      debugPrint(
          '[PlaybackSync] Could not resolve album for session ${session.id}');
      return;
    }

    await _ref
        .read(nowPlayingProvider.notifier)
        .applyCloudSession(session: session, album: album);
  }

  // ---------------------------------------------------------------------------
  // Realtime subscription
  // ---------------------------------------------------------------------------

  void _subscribeToPlaybackEvents(String userId) {
    final client = _ref.read(supabaseClientProvider);

    _channel = client
        .channel('playback_events_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'playback_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _handlePlaybackEvent(payload.newRecord);
          },
        )
        .subscribe((status, [error]) {
      debugPrint(
          '[PlaybackSync] Subscription status: $status, error: $error');
    });
  }

  // ---------------------------------------------------------------------------
  // Event handlers
  // ---------------------------------------------------------------------------

  Future<void> _handlePlaybackEvent(Map<String, dynamic> record) async {
    try {
      final event = PlaybackEvent.fromJson(record);
      debugPrint('[PlaybackSync] Received event: ${event.eventType}');

      switch (event.eventType) {
        case 'session_queued':
          await _handleSessionQueued(event);
        case 'playback_started':
          await _handlePlaybackStarted(event);
        case 'side_changed':
          await _handleSideChanged(event);
        case 'playback_stopped':
          await _handlePlaybackStopped(event);
        case 'session_cancelled':
          await _handleSessionCancelled(event);
        default:
          debugPrint(
              '[PlaybackSync] Unknown event type: ${event.eventType}');
      }
    } catch (e) {
      debugPrint('[PlaybackSync] Error handling event: $e');
    }
  }

  Future<void> _handleSessionQueued(PlaybackEvent event) async {
    final localState = _ref.read(nowPlayingProvider);

    // Self-echo: if local already has this session as queued, skip
    if (localState.cloudSessionId == event.sessionId &&
        localState.isQueued) {
      return;
    }

    // Another device queued a session — fetch and apply
    final repo = _ref.read(playbackSessionRepositoryProvider);
    final session = await repo.getSessionById(event.sessionId);
    if (session == null) return;

    final album = await _resolveAlbumForSession(session);
    if (album == null) return;

    if (mounted) {
      await _ref
          .read(nowPlayingProvider.notifier)
          .applyCloudSession(session: session, album: album);
    }
  }

  Future<void> _handlePlaybackStarted(PlaybackEvent event) async {
    final localState = _ref.read(nowPlayingProvider);

    // Self-echo: local already playing this session
    if (localState.cloudSessionId == event.sessionId &&
        localState.isPlaying) {
      return;
    }

    // Same session, transitioning from queued to playing
    if (localState.cloudSessionId == event.sessionId) {
      final repo = _ref.read(playbackSessionRepositoryProvider);
      final session = await repo.getSessionById(event.sessionId);
      if (session != null && mounted) {
        await _ref
            .read(nowPlayingProvider.notifier)
            .applyCloudPlaybackStarted(session.sideStartedAt);
      }
      return;
    }

    // Different session — fetch full session + album
    final repo = _ref.read(playbackSessionRepositoryProvider);
    final session = await repo.getSessionById(event.sessionId);
    if (session == null) return;

    final album = await _resolveAlbumForSession(session);
    if (album == null) return;

    if (mounted) {
      await _ref
          .read(nowPlayingProvider.notifier)
          .applyCloudSession(session: session, album: album);
    }
  }

  Future<void> _handleSideChanged(PlaybackEvent event) async {
    final localState = _ref.read(nowPlayingProvider);
    final side = event.payload['side'] as String?;

    if (side == null) return;

    // Self-echo: local already on this side for this session
    if (localState.cloudSessionId == event.sessionId &&
        localState.currentSide == side) {
      return;
    }

    // Fetch session for sideStartedAt
    final repo = _ref.read(playbackSessionRepositoryProvider);
    final session = await repo.getSessionById(event.sessionId);
    if (session == null) return;

    if (mounted) {
      await _ref
          .read(nowPlayingProvider.notifier)
          .applyCloudSideChange(side, session.sideStartedAt);
    }
  }

  Future<void> _handlePlaybackStopped(PlaybackEvent event) async {
    final localState = _ref.read(nowPlayingProvider);

    // Self-echo: already idle
    if (!localState.isActive) return;

    // Only clear if this event is for our current session
    if (localState.cloudSessionId == event.sessionId) {
      if (mounted) {
        await _ref.read(nowPlayingProvider.notifier).applyCloudClear();
      }
    }
  }

  Future<void> _handleSessionCancelled(PlaybackEvent event) async {
    final localState = _ref.read(nowPlayingProvider);

    // Self-echo: already idle
    if (!localState.isActive) return;

    // Only clear if this event is for our current session
    if (localState.cloudSessionId == event.sessionId) {
      if (mounted) {
        await _ref.read(nowPlayingProvider.notifier).applyCloudClear();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Album resolution
  // ---------------------------------------------------------------------------

  Future<LibraryAlbum?> _resolveAlbumForSession(
      PlaybackSession session) async {
    if (session.libraryAlbumId == null) return null;
    final albumRepo = _ref.read(albumRepositoryProvider);
    return albumRepo.getLibraryAlbum(session.libraryAlbumId!);
  }
}

/// Provider for multi-device playback sync.
///
/// Watches for cloud playback events via Supabase Realtime and
/// keeps local [NowPlayingNotifier] state in sync across devices.
final playbackSyncProvider =
    StateNotifierProvider<PlaybackSyncNotifier, PlaybackSyncState>((ref) {
  return PlaybackSyncNotifier(ref);
});
