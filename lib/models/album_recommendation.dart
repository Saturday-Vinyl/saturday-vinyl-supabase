import 'package:equatable/equatable.dart';

/// Last-known physical location of a recommended album, returned by the
/// `recommend-albums` edge function.
class RecommendedAlbumLocation extends Equatable {
  final String deviceName;
  final String deviceId;
  final DateTime detectedAt;

  const RecommendedAlbumLocation({
    required this.deviceName,
    required this.deviceId,
    required this.detectedAt,
  });

  factory RecommendedAlbumLocation.fromJson(Map<String, dynamic> json) {
    return RecommendedAlbumLocation(
      deviceName: json['device_name'] as String,
      deviceId: json['device_id'] as String,
      detectedAt: DateTime.parse(json['detected_at'] as String),
    );
  }

  @override
  List<Object?> get props => [deviceName, deviceId, detectedAt];
}

/// One recommendation returned by the `recommend-albums` edge function.
class AlbumRecommendation extends Equatable {
  final String libraryAlbumId;
  final String albumId;
  final String title;
  final String artist;
  final String? coverImageUrl;
  final Map<String, dynamic>? colors;

  /// Short human-readable rationale (e.g. "Same artist", "Not played
  /// recently"). Surfaced in the recommendations carousel.
  final String reason;

  /// Most recent crate the album was detected in, if any.
  final RecommendedAlbumLocation? lastLocation;

  const AlbumRecommendation({
    required this.libraryAlbumId,
    required this.albumId,
    required this.title,
    required this.artist,
    this.coverImageUrl,
    this.colors,
    required this.reason,
    this.lastLocation,
  });

  factory AlbumRecommendation.fromJson(Map<String, dynamic> json) {
    return AlbumRecommendation(
      libraryAlbumId: json['library_album_id'] as String,
      albumId: json['album_id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      coverImageUrl: json['cover_image_url'] as String?,
      colors: json['colors'] as Map<String, dynamic>?,
      reason: json['reason'] as String? ?? '',
      lastLocation: json['last_location'] != null
          ? RecommendedAlbumLocation.fromJson(
              json['last_location'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  List<Object?> get props => [
        libraryAlbumId,
        albumId,
        title,
        artist,
        coverImageUrl,
        reason,
        lastLocation,
      ];
}
