import 'package:saturday_consumer_app/models/playback_queue_item.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for the user's persisted playback queue.
class PlaybackQueueRepository extends BaseRepository {
  static const _tableName = 'playback_queue';

  /// Returns all items in the user's queue, ordered by position, with
  /// joined library_album + album metadata.
  Future<List<PlaybackQueueItem>> getQueue(String userId) async {
    final response = await client
        .from(_tableName)
        .select('*, library_album:library_albums(*, album:albums(*))')
        .eq('user_id', userId)
        .order('position');

    return (response as List)
        .map((row) =>
            PlaybackQueueItem.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Appends a single library album to the end of the queue.
  Future<PlaybackQueueItem> addItem({
    required String userId,
    required String libraryAlbumId,
  }) async {
    final basePosition = await _maxPosition(userId);

    final response = await client
        .from(_tableName)
        .insert({
          'user_id': userId,
          'library_album_id': libraryAlbumId,
          'position': basePosition + 1,
          'added_by': userId,
        })
        .select('*, library_album:library_albums(*, album:albums(*))')
        .single();

    return PlaybackQueueItem.fromJson(response);
  }

  /// Appends multiple library albums to the queue in the order given.
  Future<List<PlaybackQueueItem>> addItems({
    required String userId,
    required List<String> libraryAlbumIds,
  }) async {
    if (libraryAlbumIds.isEmpty) return [];

    final basePosition = await _maxPosition(userId);

    final rows = [
      for (var i = 0; i < libraryAlbumIds.length; i++)
        {
          'user_id': userId,
          'library_album_id': libraryAlbumIds[i],
          'position': basePosition + i + 1,
          'added_by': userId,
        }
    ];

    final response = await client
        .from(_tableName)
        .insert(rows)
        .select('*, library_album:library_albums(*, album:albums(*))');

    return (response as List)
        .map((row) =>
            PlaybackQueueItem.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Replaces the queue with the given library albums in the order given.
  /// Used by the cratelist Play and Shuffle Play actions.
  Future<List<PlaybackQueueItem>> replaceQueue({
    required String userId,
    required List<String> libraryAlbumIds,
  }) async {
    await client.from(_tableName).delete().eq('user_id', userId);
    return addItems(userId: userId, libraryAlbumIds: libraryAlbumIds);
  }

  Future<void> removeItem(String itemId) async {
    await client.from(_tableName).delete().eq('id', itemId);
  }

  Future<void> clearQueue(String userId) async {
    await client.from(_tableName).delete().eq('user_id', userId);
  }

  /// Removes the lowest-position queue item that matches [libraryAlbumId].
  /// Used by auto-advance: when an RFID detection resolves to a queued
  /// album, that single item is consumed (option B — duplicates further
  /// down in the queue stay).
  ///
  /// Returns true if an item was removed, false if no match was found.
  Future<bool> consumeFirstMatch({
    required String userId,
    required String libraryAlbumId,
  }) async {
    final match = await client
        .from(_tableName)
        .select('id')
        .eq('user_id', userId)
        .eq('library_album_id', libraryAlbumId)
        .order('position')
        .limit(1)
        .maybeSingle();

    if (match == null) return false;

    await client.from(_tableName).delete().eq('id', match['id']);
    return true;
  }

  /// Sets the queue order via RPC. [orderedItemIds] must contain exactly
  /// the caller's current queue items.
  Future<void> reorder({required List<String> orderedItemIds}) async {
    await client.rpc(
      'reorder_playback_queue',
      params: {'p_item_ids': orderedItemIds},
    );
  }

  Future<int> _maxPosition(String userId) async {
    final response = await client
        .from(_tableName)
        .select('position')
        .eq('user_id', userId)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();
    return (response?['position'] as int?) ?? 0;
  }
}
