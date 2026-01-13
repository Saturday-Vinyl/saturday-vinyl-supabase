import 'package:equatable/equatable.dart';

/// Represents a Now Playing detection from a Saturday Hub.
///
/// When a record jacket is placed on the hub, the hub reads the RFID tag
/// and sends the EPC to the cloud. This model represents that detection event.
class NowPlayingDetection extends Equatable {
  /// Unique identifier for this detection record.
  final String id;

  /// The user who owns this hub.
  final String userId;

  /// The device (hub) that detected the record.
  final String deviceId;

  /// The EPC identifier read from the RFID tag.
  final String epcIdentifier;

  /// The library album ID if the EPC was resolved, null if unresolved.
  final String? libraryAlbumId;

  /// When the detection occurred.
  final DateTime detectedAt;

  /// When the record was removed (null if still present).
  final DateTime? removedAt;

  const NowPlayingDetection({
    required this.id,
    required this.userId,
    required this.deviceId,
    required this.epcIdentifier,
    this.libraryAlbumId,
    required this.detectedAt,
    this.removedAt,
  });

  factory NowPlayingDetection.fromJson(Map<String, dynamic> json) {
    return NowPlayingDetection(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      deviceId: json['device_id'] as String,
      epcIdentifier: json['epc_identifier'] as String,
      libraryAlbumId: json['library_album_id'] as String?,
      detectedAt: DateTime.parse(json['detected_at'] as String),
      removedAt: json['removed_at'] != null
          ? DateTime.parse(json['removed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'device_id': deviceId,
      'epc_identifier': epcIdentifier,
      'library_album_id': libraryAlbumId,
      'detected_at': detectedAt.toIso8601String(),
      'removed_at': removedAt?.toIso8601String(),
    };
  }

  NowPlayingDetection copyWith({
    String? id,
    String? userId,
    String? deviceId,
    String? epcIdentifier,
    String? libraryAlbumId,
    DateTime? detectedAt,
    DateTime? removedAt,
    bool clearLibraryAlbumId = false,
    bool clearRemovedAt = false,
  }) {
    return NowPlayingDetection(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      epcIdentifier: epcIdentifier ?? this.epcIdentifier,
      libraryAlbumId:
          clearLibraryAlbumId ? null : (libraryAlbumId ?? this.libraryAlbumId),
      detectedAt: detectedAt ?? this.detectedAt,
      removedAt: clearRemovedAt ? null : (removedAt ?? this.removedAt),
    );
  }

  /// Whether this detection is currently active (record still on hub).
  bool get isActive => removedAt == null;

  /// Whether the EPC was successfully resolved to a library album.
  bool get isResolved => libraryAlbumId != null;

  @override
  List<Object?> get props => [
        id,
        userId,
        deviceId,
        epcIdentifier,
        libraryAlbumId,
        detectedAt,
        removedAt,
      ];
}
