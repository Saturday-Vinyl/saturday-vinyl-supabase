import 'package:equatable/equatable.dart';

/// Represents the physical location of an album in a crate.
///
/// Tracks where albums are stored based on RFID detection.
/// A null [removedAt] indicates the album is currently present in the crate.
class AlbumLocation extends Equatable {
  final String id;
  final String libraryAlbumId;

  /// The device (crate) where the album was detected.
  final String deviceId;

  final DateTime detectedAt;

  /// When the album was removed from the crate, or null if still present.
  final DateTime? removedAt;

  const AlbumLocation({
    required this.id,
    required this.libraryAlbumId,
    required this.deviceId,
    required this.detectedAt,
    this.removedAt,
  });

  factory AlbumLocation.fromJson(Map<String, dynamic> json) {
    return AlbumLocation(
      id: json['id'] as String,
      libraryAlbumId: json['library_album_id'] as String,
      deviceId: json['device_id'] as String,
      detectedAt: DateTime.parse(json['detected_at'] as String),
      removedAt: json['removed_at'] != null
          ? DateTime.parse(json['removed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'library_album_id': libraryAlbumId,
      'device_id': deviceId,
      'detected_at': detectedAt.toIso8601String(),
      'removed_at': removedAt?.toIso8601String(),
    };
  }

  AlbumLocation copyWith({
    String? id,
    String? libraryAlbumId,
    String? deviceId,
    DateTime? detectedAt,
    DateTime? removedAt,
  }) {
    return AlbumLocation(
      id: id ?? this.id,
      libraryAlbumId: libraryAlbumId ?? this.libraryAlbumId,
      deviceId: deviceId ?? this.deviceId,
      detectedAt: detectedAt ?? this.detectedAt,
      removedAt: removedAt ?? this.removedAt,
    );
  }

  /// Whether the album is currently present in the crate.
  bool get isPresent => removedAt == null;

  @override
  List<Object?> get props => [
        id,
        libraryAlbumId,
        deviceId,
        detectedAt,
        removedAt,
      ];
}
