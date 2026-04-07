import 'package:saturday_consumer_app/models/playback_session.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for cloud playback session operations.
///
/// Each mutation writes to `playback_sessions` AND inserts
/// a corresponding `playback_event` for the event log.
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
  /// Auto-cancels any existing queued session for this user.
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
    // Cancel any existing queued session
    await _cancelExistingQueued(userId, sourceType, sourceDeviceId);

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

  /// Start playback on a queued session.
  ///
  /// Auto-stops any existing playing session for this user.
  Future<PlaybackSession> startSession({
    required String sessionId,
    required String userId,
    String sourceType = 'app',
    String? sourceDeviceId,
  }) async {
    // Stop any existing playing session
    await _stopExistingPlaying(userId, sourceType, sourceDeviceId);

    final now = DateTime.now().toUtc().toIso8601String();
    final response = await client
        .from(_sessionsTable)
        .update({
          'status': 'playing',
          'side_started_at': now,
          'started_at': now,
          'started_by_source': sourceType,
          'started_by_device_id': sourceDeviceId,
        })
        .eq('id', sessionId)
        .select()
        .single();

    final session = PlaybackSession.fromJson(response);

    await _insertEvent(
      sessionId: sessionId,
      userId: userId,
      eventType: 'playback_started',
      sourceType: sourceType,
      sourceDeviceId: sourceDeviceId,
    );

    return session;
  }

  /// Stop a playing session.
  Future<void> stopSession({
    required String sessionId,
    required String userId,
    String sourceType = 'app',
    String? sourceDeviceId,
  }) async {
    await client
        .from(_sessionsTable)
        .update({
          'status': 'stopped',
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', sessionId);

    await _insertEvent(
      sessionId: sessionId,
      userId: userId,
      eventType: 'playback_stopped',
      sourceType: sourceType,
      sourceDeviceId: sourceDeviceId,
    );
  }

  /// Cancel a queued session.
  Future<void> cancelSession({
    required String sessionId,
    required String userId,
    String sourceType = 'app',
    String? sourceDeviceId,
  }) async {
    await client
        .from(_sessionsTable)
        .update({
          'status': 'cancelled',
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', sessionId);

    await _insertEvent(
      sessionId: sessionId,
      userId: userId,
      eventType: 'session_cancelled',
      sourceType: sourceType,
      sourceDeviceId: sourceDeviceId,
    );
  }

  /// Change the current side on a playing session.
  ///
  /// Only sets [sideStartedAt] if the session is currently playing.
  Future<void> changeSide({
    required String sessionId,
    required String userId,
    required String side,
    String sourceType = 'app',
    String? sourceDeviceId,
  }) async {
    // Query current status to decide whether to set side_started_at
    final current = await client
        .from(_sessionsTable)
        .select('status')
        .eq('id', sessionId)
        .single();

    final updateData = <String, dynamic>{
      'current_side': side,
    };

    if (current['status'] == 'playing') {
      updateData['side_started_at'] = DateTime.now().toUtc().toIso8601String();
    }

    await client
        .from(_sessionsTable)
        .update(updateData)
        .eq('id', sessionId);

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

  Future<void> _cancelExistingQueued(
    String userId,
    String sourceType,
    String? sourceDeviceId,
  ) async {
    final existing = await getQueuedSession(userId);
    if (existing != null) {
      await cancelSession(
        sessionId: existing.id,
        userId: userId,
        sourceType: sourceType,
        sourceDeviceId: sourceDeviceId,
      );
    }
  }

  Future<void> _stopExistingPlaying(
    String userId,
    String sourceType,
    String? sourceDeviceId,
  ) async {
    final existing = await getPlayingSession(userId);
    if (existing != null) {
      await stopSession(
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
