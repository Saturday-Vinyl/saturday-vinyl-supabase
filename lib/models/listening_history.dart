import 'package:equatable/equatable.dart';

/// Which side of the record was completed.
/// Supports multi-disc albums: A, B, C, D, E, F, G, H (up to 4 discs).
enum RecordSide {
  a,
  b,
  c,
  d,
  e,
  f,
  g,
  h;

  static RecordSide? fromString(String? value) {
    if (value == null) return null;
    return RecordSide.values.cast<RecordSide?>().firstWhere(
          (side) => side?.name.toUpperCase() == value.toUpperCase(),
          orElse: () => null,
        );
  }

  String toJsonString() => name.toUpperCase();
}

/// Represents a user's listening history entry.
///
/// Tracks when and how long a user played a record,
/// enabling personalized recommendations.
class ListeningHistory extends Equatable {
  final String id;
  final String userId;
  final String libraryAlbumId;
  final DateTime playedAt;

  /// How long the record was played, in seconds.
  final int? playDurationSeconds;

  /// Which side was completed, if any.
  final RecordSide? completedSide;

  /// Which hub detected the record being played.
  final String? deviceId;

  const ListeningHistory({
    required this.id,
    required this.userId,
    required this.libraryAlbumId,
    required this.playedAt,
    this.playDurationSeconds,
    this.completedSide,
    this.deviceId,
  });

  factory ListeningHistory.fromJson(Map<String, dynamic> json) {
    return ListeningHistory(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      libraryAlbumId: json['library_album_id'] as String,
      playedAt: DateTime.parse(json['played_at'] as String),
      playDurationSeconds: json['play_duration_seconds'] as int?,
      completedSide: RecordSide.fromString(json['completed_side'] as String?),
      deviceId: json['device_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'library_album_id': libraryAlbumId,
      'played_at': playedAt.toIso8601String(),
      'play_duration_seconds': playDurationSeconds,
      'completed_side': completedSide?.toJsonString(),
      'device_id': deviceId,
    };
  }

  ListeningHistory copyWith({
    String? id,
    String? userId,
    String? libraryAlbumId,
    DateTime? playedAt,
    int? playDurationSeconds,
    RecordSide? completedSide,
    String? deviceId,
  }) {
    return ListeningHistory(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      libraryAlbumId: libraryAlbumId ?? this.libraryAlbumId,
      playedAt: playedAt ?? this.playedAt,
      playDurationSeconds: playDurationSeconds ?? this.playDurationSeconds,
      completedSide: completedSide ?? this.completedSide,
      deviceId: deviceId ?? this.deviceId,
    );
  }

  /// Returns formatted play duration as HH:MM:SS or MM:SS.
  String get formattedPlayDuration {
    if (playDurationSeconds == null) return '--:--';
    final total = playDurationSeconds!;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        libraryAlbumId,
        playedAt,
        playDurationSeconds,
        completedSide,
        deviceId,
      ];
}
