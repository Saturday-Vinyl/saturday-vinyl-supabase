/// A single, observational line surfaced by the listening room — the
/// witness-register echo described in `docs/ROOM_OBSERVATIONS.md`.
///
/// Returned by the `mobile_room_observation()` RPC. Fields vary by [kind]
/// (see the sealed-class subclasses below); the server returns structured
/// data and the client composes the sentence so album titles can render
/// in serif italic.
sealed class RoomObservation {
  const RoomObservation();

  /// Decodes a row from the RPC. Returns null if the row's `kind` is
  /// unknown — older clients should silently skip categories they don't
  /// understand rather than crash the room.
  static RoomObservation? fromJson(Map<String, dynamic> json) {
    final kind = json['kind'] as String?;
    switch (kind) {
      case 'temporal_echo':
        return TemporalEchoObservation(
          libraryAlbumId: json['library_album_id'] as String?,
          albumTitle: json['album_title'] as String? ?? 'Untitled record',
          albumArtist: json['album_artist'] as String? ?? '',
          daysAgo: (json['days_ago'] as num?)?.toInt() ?? 0,
        );
      case 'cratelist_quiet':
        return CratelistQuietObservation(
          cratelistId: json['cratelist_id'] as String?,
          cratelistName: json['cratelist_name'] as String? ?? '',
          daysSinceLastPlay:
              (json['days_since_last_play'] as num?)?.toInt(),
        );
      case 'recurring_record':
        return RecurringRecordObservation(
          libraryAlbumId: json['library_album_id'] as String?,
          albumTitle: json['album_title'] as String? ?? 'Untitled record',
          albumArtist: json['album_artist'] as String? ?? '',
          playCount: (json['play_count'] as num?)?.toInt() ?? 0,
        );
      default:
        return null;
    }
  }
}

class TemporalEchoObservation extends RoomObservation {
  const TemporalEchoObservation({
    required this.libraryAlbumId,
    required this.albumTitle,
    required this.albumArtist,
    required this.daysAgo,
  });

  final String? libraryAlbumId;
  final String albumTitle;
  final String albumArtist;
  final int daysAgo;
}

class CratelistQuietObservation extends RoomObservation {
  const CratelistQuietObservation({
    required this.cratelistId,
    required this.cratelistName,
    required this.daysSinceLastPlay,
  });

  final String? cratelistId;
  final String cratelistName;
  final int? daysSinceLastPlay;
}

class RecurringRecordObservation extends RoomObservation {
  const RecurringRecordObservation({
    required this.libraryAlbumId,
    required this.albumTitle,
    required this.albumArtist,
    required this.playCount,
  });

  final String? libraryAlbumId;
  final String albumTitle;
  final String albumArtist;
  final int playCount;
}
