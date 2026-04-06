import 'package:equatable/equatable.dart';

/// Represents a cloud-persisted playback session.
///
/// A session tracks the lifecycle of playing a record:
/// queued → playing → stopped (or cancelled).
class PlaybackSession extends Equatable {
  final String id;
  final String userId;
  final String? libraryAlbumId;

  /// Denormalized album metadata for widgets/notifications/hubs.
  final String? albumTitle;
  final String? albumArtist;
  final String? coverImageUrl;

  /// Session status: queued, playing, stopped, or cancelled.
  final String status;

  /// Current side being played (A, B, C, or D).
  final String currentSide;

  /// When the current side started playing. Null when queued.
  final DateTime? sideStartedAt;

  /// Current track fields (derived, updated periodically).
  final int? currentTrackIndex;
  final String? currentTrackPosition;
  final String? currentTrackTitle;

  /// Track data snapshot (JSONB array of tracks).
  final List<Map<String, dynamic>>? tracks;
  final int? sideADurationSeconds;
  final int? sideBDurationSeconds;

  /// Source tracking.
  final String queuedBySource;
  final String? queuedByDeviceId;
  final String? startedBySource;
  final String? startedByDeviceId;

  /// Timestamps.
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime updatedAt;
  final DateTime createdAt;

  const PlaybackSession({
    required this.id,
    required this.userId,
    this.libraryAlbumId,
    this.albumTitle,
    this.albumArtist,
    this.coverImageUrl,
    this.status = 'queued',
    this.currentSide = 'A',
    this.sideStartedAt,
    this.currentTrackIndex,
    this.currentTrackPosition,
    this.currentTrackTitle,
    this.tracks,
    this.sideADurationSeconds,
    this.sideBDurationSeconds,
    this.queuedBySource = 'app',
    this.queuedByDeviceId,
    this.startedBySource,
    this.startedByDeviceId,
    this.startedAt,
    this.endedAt,
    required this.updatedAt,
    required this.createdAt,
  });

  bool get isQueued => status == 'queued';
  bool get isPlaying => status == 'playing';
  bool get isStopped => status == 'stopped';
  bool get isCancelled => status == 'cancelled';
  bool get isActive => isQueued || isPlaying;

  factory PlaybackSession.fromJson(Map<String, dynamic> json) {
    return PlaybackSession(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      libraryAlbumId: json['library_album_id'] as String?,
      albumTitle: json['album_title'] as String?,
      albumArtist: json['album_artist'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      status: json['status'] as String? ?? 'queued',
      currentSide: json['current_side'] as String? ?? 'A',
      sideStartedAt: json['side_started_at'] != null
          ? DateTime.parse(json['side_started_at'] as String)
          : null,
      currentTrackIndex: json['current_track_index'] as int?,
      currentTrackPosition: json['current_track_position'] as String?,
      currentTrackTitle: json['current_track_title'] as String?,
      tracks: json['tracks'] != null
          ? (json['tracks'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : null,
      sideADurationSeconds: json['side_a_duration_seconds'] as int?,
      sideBDurationSeconds: json['side_b_duration_seconds'] as int?,
      queuedBySource: json['queued_by_source'] as String? ?? 'app',
      queuedByDeviceId: json['queued_by_device_id'] as String?,
      startedBySource: json['started_by_source'] as String?,
      startedByDeviceId: json['started_by_device_id'] as String?,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'library_album_id': libraryAlbumId,
      'album_title': albumTitle,
      'album_artist': albumArtist,
      'cover_image_url': coverImageUrl,
      'status': status,
      'current_side': currentSide,
      'side_started_at': sideStartedAt?.toIso8601String(),
      'current_track_index': currentTrackIndex,
      'current_track_position': currentTrackPosition,
      'current_track_title': currentTrackTitle,
      'tracks': tracks,
      'side_a_duration_seconds': sideADurationSeconds,
      'side_b_duration_seconds': sideBDurationSeconds,
      'queued_by_source': queuedBySource,
      'queued_by_device_id': queuedByDeviceId,
      'started_by_source': startedBySource,
      'started_by_device_id': startedByDeviceId,
      'started_at': startedAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  PlaybackSession copyWith({
    String? id,
    String? userId,
    String? libraryAlbumId,
    String? albumTitle,
    String? albumArtist,
    String? coverImageUrl,
    String? status,
    String? currentSide,
    DateTime? sideStartedAt,
    int? currentTrackIndex,
    String? currentTrackPosition,
    String? currentTrackTitle,
    List<Map<String, dynamic>>? tracks,
    int? sideADurationSeconds,
    int? sideBDurationSeconds,
    String? queuedBySource,
    String? queuedByDeviceId,
    String? startedBySource,
    String? startedByDeviceId,
    DateTime? startedAt,
    DateTime? endedAt,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) {
    return PlaybackSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      libraryAlbumId: libraryAlbumId ?? this.libraryAlbumId,
      albumTitle: albumTitle ?? this.albumTitle,
      albumArtist: albumArtist ?? this.albumArtist,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      status: status ?? this.status,
      currentSide: currentSide ?? this.currentSide,
      sideStartedAt: sideStartedAt ?? this.sideStartedAt,
      currentTrackIndex: currentTrackIndex ?? this.currentTrackIndex,
      currentTrackPosition: currentTrackPosition ?? this.currentTrackPosition,
      currentTrackTitle: currentTrackTitle ?? this.currentTrackTitle,
      tracks: tracks ?? this.tracks,
      sideADurationSeconds: sideADurationSeconds ?? this.sideADurationSeconds,
      sideBDurationSeconds: sideBDurationSeconds ?? this.sideBDurationSeconds,
      queuedBySource: queuedBySource ?? this.queuedBySource,
      queuedByDeviceId: queuedByDeviceId ?? this.queuedByDeviceId,
      startedBySource: startedBySource ?? this.startedBySource,
      startedByDeviceId: startedByDeviceId ?? this.startedByDeviceId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        libraryAlbumId,
        albumTitle,
        albumArtist,
        coverImageUrl,
        status,
        currentSide,
        sideStartedAt,
        currentTrackIndex,
        currentTrackPosition,
        currentTrackTitle,
        tracks,
        sideADurationSeconds,
        sideBDurationSeconds,
        queuedBySource,
        queuedByDeviceId,
        startedBySource,
        startedByDeviceId,
        startedAt,
        endedAt,
        updatedAt,
        createdAt,
      ];
}
