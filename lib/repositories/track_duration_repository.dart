import 'package:saturday_consumer_app/models/album.dart';
import 'package:saturday_consumer_app/models/track.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for contributing community track durations.
class TrackDurationRepository extends BaseRepository {
  /// Contribute track durations for an album side.
  ///
  /// Calls the `contribute_track_durations` RPC which atomically:
  /// 1. Records the contribution in `album_track_duration_contributions`
  /// 2. Updates the canonical album tracks JSONB (only fills null durations)
  ///
  /// Returns the updated list of tracks with merged durations.
  Future<List<Track>> contributeTrackDurations({
    required String albumId,
    required String userId,
    required List<TrackDuration> durations,
    String? side,
  }) async {
    final trackDurationsJson = durations
        .map((d) => {
              'position': d.position,
              'duration_seconds': d.durationSeconds,
            })
        .toList();

    final response = await client.rpc('contribute_track_durations', params: {
      'p_album_id': albumId,
      'p_contributed_by': userId,
      'p_track_durations': trackDurationsJson,
      'p_side': side,
    });

    // The RPC returns the updated tracks JSONB array
    final tracksList = response as List<dynamic>;
    return tracksList
        .map((t) => Track.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// Re-fetches the canonical album to get updated track data.
  Future<Album?> getUpdatedAlbum(String albumId) async {
    final response = await client
        .from('albums')
        .select()
        .eq('id', albumId)
        .maybeSingle();

    if (response == null) return null;
    return Album.fromJson(response);
  }
}

/// A recorded track duration from a timing session.
class TrackDuration {
  final String position;
  final int durationSeconds;

  const TrackDuration({
    required this.position,
    required this.durationSeconds,
  });
}
