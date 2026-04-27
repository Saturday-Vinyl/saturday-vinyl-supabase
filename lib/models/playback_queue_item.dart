import 'package:equatable/equatable.dart';
import 'package:saturday_consumer_app/models/library_album.dart';

/// One album in the user's playback queue, with its position in the
/// ordered queue. The queue spans devices via Supabase realtime so the
/// same user's app on phone and tablet stay in sync. Duplicates are
/// allowed (the same album may appear more than once).
class PlaybackQueueItem extends Equatable {
  final String id;
  final String userId;
  final String libraryAlbumId;
  final int position;
  final DateTime addedAt;
  final String? addedBy;

  /// Joined library_album metadata when fetched with the embed.
  final LibraryAlbum? libraryAlbum;

  const PlaybackQueueItem({
    required this.id,
    required this.userId,
    required this.libraryAlbumId,
    required this.position,
    required this.addedAt,
    this.addedBy,
    this.libraryAlbum,
  });

  factory PlaybackQueueItem.fromJson(Map<String, dynamic> json) {
    return PlaybackQueueItem(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      libraryAlbumId: json['library_album_id'] as String,
      position: json['position'] as int,
      addedAt: DateTime.parse(json['added_at'] as String),
      addedBy: json['added_by'] as String?,
      libraryAlbum: json['library_album'] != null
          ? LibraryAlbum.fromJson(json['library_album'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'library_album_id': libraryAlbumId,
      'position': position,
      'added_at': addedAt.toIso8601String(),
      'added_by': addedBy,
      if (libraryAlbum != null) 'library_album': libraryAlbum!.toJson(),
    };
  }

  PlaybackQueueItem copyWith({
    String? id,
    String? userId,
    String? libraryAlbumId,
    int? position,
    DateTime? addedAt,
    String? addedBy,
    LibraryAlbum? libraryAlbum,
  }) {
    return PlaybackQueueItem(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      libraryAlbumId: libraryAlbumId ?? this.libraryAlbumId,
      position: position ?? this.position,
      addedAt: addedAt ?? this.addedAt,
      addedBy: addedBy ?? this.addedBy,
      libraryAlbum: libraryAlbum ?? this.libraryAlbum,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        libraryAlbumId,
        position,
        addedAt,
        addedBy,
        libraryAlbum,
      ];
}
