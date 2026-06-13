import 'package:saturday_consumer_app/models/playback_session.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for cloud playback session operations.
///
/// Under the v2 playback event protocol, producers do NOT UPDATE
/// `playback_sessions` for state transitions — they insert canonical
/// events into `playback_events` and the `apply_playback_event` trigger
/// derives status, side_started_at, started_at, ended_at, current_side,
/// and play_seconds_total from those events.
///
/// The one exception is [queueSession], which still INSERTs the session
/// row directly (the row must exist before any event can reference it).
class PlaybackSessionRepository extends BaseRepository {
  static const _sessionsTable = 'playback_sessions';
  static const _eventsTable = 'playback_events';

  /// Get the user's active sessions (queued and/or playing).
  Future<List<PlaybackSession>> getActiveSessions(String userId) async {
    final response = await client
        .from(_sessionsTable)
        .select()
        .eq('user_id', userId)
        .inFilter('status', ['queued', 'playing'])
        .order('created_at', ascending: false);

    return (response as List)
        .map((r) => PlaybackSession.fromJson(r))
        .toList();
  }

  /// Get the current playing session, if any.
  Future<PlaybackSession?> getPlayingSession(String userId) async {
    final response = await client
        .from(_sessionsTable)
        .select()
        .eq('user_id', userId)
        .eq('status', 'playing')
        .maybeSingle();

    return response != null ? PlaybackSession.fromJson(response) : null;
  }

  /// Get the current queued session, if any.
  Future<PlaybackSession?> getQueuedSession(String userId) async {
    final response = await client
        .from(_sessionsTable)
        .select()
        .eq('user_id', userId)
        .eq('status', 'queued')
        .maybeSingle();

    return response != null ? PlaybackSession.fromJson(response) : null;
  }

  /// Queue an album for playback.
  ///
  /// INSERTs the session row in `queued` status, then emits
  /// `session_queued`. Auto-cancels any same-user session that would
  /// violate the unique queued/playing partial indexes — the v2 trigger
  /// gracefully handles a cancel that arrives while a session is
  /// playing (it accumulates the open play window into
  /// `play_seconds_total` before terminating).
  Future<PlaybackSession> queueSession({
    required String userId,
    required String libraryAlbumId,
    String? albumTitle,
    String? albumArtist,
    String? coverImageUrl,
    String currentSide = 'A',
    List<Map<String, dynamic>>? tracks,
    int? sideADurationSeconds,
    int? sideBDurationSeconds,
    String sourceType = 'app',
    String? sourceDeviceId,
  }) async {
    await _cancelExistingActive(userId, sourceType, sourceDeviceId);

    final sessionData = {
      'user_id': userId,
      'library_album_id': libraryAlbumId,
      'album_title': albumTitle,
      'album_artist': albumArtist,
      'cover_image_url': coverImageUrl,
      'status': 'queued',
      'current_side': currentSide,
      'tracks': tracks,
      'side_a_duration_seconds': sideADurationSeconds,
      'side_b_duration_seconds': sideBDurationSeconds,
      'queued_by_source': sourceType,
      'queued_by_device_id': sourceDeviceId,
    };

    final response = await client
        .from(_sessionsTable)
        .insert(sessionData)
        .select()
        .single();

    final session = PlaybackSession.fromJson(response);

    await _insertEvent(
      sessionId: session.id,
      userId: userId,
      eventType: 'session_queued',
      sourceType: sourceType,
      sourceDeviceId: sourceDeviceId,
      payload: {
        'library_album_id': libraryAlbumId,
        'album_title': albumTitle,
        'album_artist': albumArtist,
        'current_side': currentSide,
      },
    );

    return session;
  }

  /// Drop the needle on a queued session.
  ///
  /// Emits `playback_started`. The trigger sets `status: playing`,
  /// preserves any existing `started_at` (so total session age is stable
  /// across resumes), and sets `side_started_at: now()`.
  Future<void> startSession({
    required String sessionId,
    required String userId,
    String sourceType = 'app',
    String? sourceDeviceId,
  }) async {
    await _insertEvent(
      sessionId: sessionId,
      userId: userId,
      eventType: 'playback_started',
      sourceType: sourceType,
      sourceDeviceId: sourceDeviceId,
    );
  }

  /// Pause playback on a playing session without ending it.
  ///
  /// Emits `playback_stopped`. Despite the legacy event name this is
  /// NOT a terminal action under v2: the trigger transitions
  /// `status: playing → queued`, clears `side_started_at`, accumulates
  /// the open play window into `play_seconds_total`, and leaves the
  /// session ready to resume on the same side via [startSession].
  ///
  /// To actually terminate a session, use [cancelSession].
  Future<void> stopPlayback({
    required String sessionId,
    required String userId,
    String sourceType = 'app',
    String? sourceDeviceId,
  }) async {
    await _insertEvent(
      sessionId: sessionId,
      userId: userId,
      eventType: 'playback_stopped',
      sourceType: sourceType,
      sourceDeviceId: sourceDeviceId,
    );
  }

  /// Terminate a session — works from any non-terminal state.
  ///
  /// Emits `session_cancelled`. The trigger handles the cleanup in one
  /// pass: if the session was `playing`, the open window is accumulated
  /// into `play_seconds_total` first. Final play duration and
  /// `completed_side` are written into the matching `listening_history`
  /// row by the listening-history trigger.
  Future<void> cancelSession({
    required String sessionId,
    required String userId,
    String sourceType = 'app',
    String? sourceDeviceId,
  }) async {
    await _insertEvent(
      sessionId: sessionId,
      userId: userId,
      eventType: 'session_cancelled',
      sourceType: sourceType,
      sourceDeviceId: sourceDeviceId,
    );
  }

  /// Set the current side on a session.
  ///
  /// Emits `side_changed` with the target side in payload. The trigger
  /// always lands the session in `queued` regardless of prior status
  /// (auto-advance after a side ended, listener flipping the record, or
  /// listener picking a different side while still queued). The
  /// just-elapsed play window — if any — is accumulated into
  /// `play_seconds_total` before the side flip.
  Future<void> changeSide({
    required String sessionId,
    required String userId,
    required String side,
    String sourceType = 'app',
    String? sourceDeviceId,
  }) async {
    await _insertEvent(
      sessionId: sessionId,
      userId: userId,
      eventType: 'side_changed',
      sourceType: sourceType,
      sourceDeviceId: sourceDeviceId,
      payload: {'side': side},
    );
  }

  /// Get a session by ID.
  Future<PlaybackSession?> getSessionById(String sessionId) async {
    final response = await client
        .from(_sessionsTable)
        .select()
        .eq('id', sessionId)
        .maybeSingle();

    return response != null ? PlaybackSession.fromJson(response) : null;
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Cancel every non-terminal session this user owns. Used before
  /// queueing a fresh session so the queued/playing unique indexes are
  /// satisfied. Under v2 the trigger handles the open-window
  /// accumulation regardless of whether the existing session is queued
  /// or playing.
  Future<void> _cancelExistingActive(
    String userId,
    String sourceType,
    String? sourceDeviceId,
  ) async {
    for (final existing in await getActiveSessions(userId)) {
      await cancelSession(
        sessionId: existing.id,
        userId: userId,
        sourceType: sourceType,
        sourceDeviceId: sourceDeviceId,
      );
    }
  }

  Future<void> _insertEvent({
    required String sessionId,
    required String userId,
    required String eventType,
    required String sourceType,
    String? sourceDeviceId,
    Map<String, dynamic>? payload,
  }) async {
    await client.from(_eventsTable).insert({
      'session_id': sessionId,
      'user_id': userId,
      'event_type': eventType,
      'source_type': sourceType,
      'source_device_id': sourceDeviceId,
      'payload': payload ?? {},
    });
  }
}
