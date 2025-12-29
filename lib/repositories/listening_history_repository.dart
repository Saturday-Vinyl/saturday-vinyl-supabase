import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/listening_history.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for listening history database operations.
class ListeningHistoryRepository extends BaseRepository {
  static const _tableName = 'listening_history';

  /// Records a new play session.
  Future<ListeningHistory> recordPlay({
    required String userId,
    required String libraryAlbumId,
    String? deviceId,
  }) async {
    final response = await client
        .from(_tableName)
        .insert({
          'user_id': userId,
          'library_album_id': libraryAlbumId,
          'device_id': deviceId,
          'played_at': DateTime.now().toIso8601String(),
        })
        .select()
        .single();

    return ListeningHistory.fromJson(response);
  }

  /// Updates the duration and completed side for a play session.
  Future<ListeningHistory> updatePlayDuration(
    String historyId,
    int durationSeconds,
    RecordSide? completedSide,
  ) async {
    final response = await client
        .from(_tableName)
        .update({
          'play_duration_seconds': durationSeconds,
          'completed_side': completedSide?.toJsonString(),
        })
        .eq('id', historyId)
        .select()
        .single();

    return ListeningHistory.fromJson(response);
  }

  /// Gets a user's listening history.
  Future<List<ListeningHistory>> getUserHistory(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('user_id', userId)
        .order('played_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (response as List)
        .map((row) => ListeningHistory.fromJson(row))
        .toList();
  }

  /// Gets the total play count for an album.
  Future<int> getAlbumPlayCount(String libraryAlbumId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('library_album_id', libraryAlbumId)
        .count();

    return response.count;
  }

  /// Gets the most recently played history entries for a user.
  Future<List<ListeningHistory>> getRecentlyPlayedHistory(
    String userId, {
    int limit = 10,
  }) async {
    // Get unique library_album_ids with most recent play time
    final response = await client
        .from(_tableName)
        .select()
        .eq('user_id', userId)
        .order('played_at', ascending: false)
        .limit(limit * 2); // Fetch extra to account for duplicates

    // Deduplicate by library_album_id, keeping most recent
    final seen = <String>{};
    final unique = <ListeningHistory>[];

    for (final row in response as List) {
      final history = ListeningHistory.fromJson(row);
      if (!seen.contains(history.libraryAlbumId)) {
        seen.add(history.libraryAlbumId);
        unique.add(history);
        if (unique.length >= limit) break;
      }
    }

    return unique;
  }

  /// Gets recently played albums with full album data for a user.
  Future<List<LibraryAlbum>> getRecentlyPlayed(
    String userId, {
    int limit = 10,
  }) async {
    // Fetch listening history with joined library_albums and albums data
    final response = await client
        .from(_tableName)
        .select('''
          *,
          library_albums!inner (
            *,
            album:albums (*)
          )
        ''')
        .eq('user_id', userId)
        .order('played_at', ascending: false)
        .limit(limit * 2); // Fetch extra to account for duplicates

    // Deduplicate by library_album_id, keeping most recent
    final seen = <String>{};
    final unique = <LibraryAlbum>[];

    for (final row in response as List) {
      final libraryAlbumData = row['library_albums'] as Map<String, dynamic>;
      final libraryAlbum = LibraryAlbum.fromJson(libraryAlbumData);

      if (!seen.contains(libraryAlbum.id)) {
        seen.add(libraryAlbum.id);
        unique.add(libraryAlbum);
        if (unique.length >= limit) break;
      }
    }

    return unique;
  }

  /// Gets listening history for a specific album.
  Future<List<ListeningHistory>> getAlbumHistory(
    String libraryAlbumId, {
    int limit = 20,
  }) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('library_album_id', libraryAlbumId)
        .order('played_at', ascending: false)
        .limit(limit);

    return (response as List)
        .map((row) => ListeningHistory.fromJson(row))
        .toList();
  }

  /// Gets listening history for a specific date range.
  Future<List<ListeningHistory>> getHistoryForDateRange(
    String userId,
    DateTime start,
    DateTime end,
  ) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('user_id', userId)
        .gte('played_at', start.toIso8601String())
        .lte('played_at', end.toIso8601String())
        .order('played_at', ascending: false);

    return (response as List)
        .map((row) => ListeningHistory.fromJson(row))
        .toList();
  }

  /// Gets total listening time for a user (in seconds).
  Future<int> getTotalListeningTime(String userId) async {
    final response = await client
        .from(_tableName)
        .select('play_duration_seconds')
        .eq('user_id', userId);

    int total = 0;
    for (final row in response as List) {
      final duration = row['play_duration_seconds'] as int?;
      if (duration != null) {
        total += duration;
      }
    }
    return total;
  }
}
