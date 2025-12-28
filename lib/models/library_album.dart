import 'package:equatable/equatable.dart';
import 'package:saturday_consumer_app/models/album.dart';

/// Represents an album's association with a specific library.
///
/// Links canonical albums to libraries with library-specific data
/// like notes, favorites status, and who added it.
class LibraryAlbum extends Equatable {
  final String id;
  final String libraryId;
  final String albumId;
  final DateTime addedAt;
  final String addedBy;
  final String? notes;
  final bool isFavorite;

  /// The canonical album data, populated when fetched with joins.
  final Album? album;

  const LibraryAlbum({
    required this.id,
    required this.libraryId,
    required this.albumId,
    required this.addedAt,
    required this.addedBy,
    this.notes,
    this.isFavorite = false,
    this.album,
  });

  factory LibraryAlbum.fromJson(Map<String, dynamic> json) {
    return LibraryAlbum(
      id: json['id'] as String,
      libraryId: json['library_id'] as String,
      albumId: json['album_id'] as String,
      addedAt: DateTime.parse(json['added_at'] as String),
      addedBy: json['added_by'] as String,
      notes: json['notes'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      album: json['album'] != null
          ? Album.fromJson(json['album'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'library_id': libraryId,
      'album_id': albumId,
      'added_at': addedAt.toIso8601String(),
      'added_by': addedBy,
      'notes': notes,
      'is_favorite': isFavorite,
      if (album != null) 'album': album!.toJson(),
    };
  }

  LibraryAlbum copyWith({
    String? id,
    String? libraryId,
    String? albumId,
    DateTime? addedAt,
    String? addedBy,
    String? notes,
    bool? isFavorite,
    Album? album,
  }) {
    return LibraryAlbum(
      id: id ?? this.id,
      libraryId: libraryId ?? this.libraryId,
      albumId: albumId ?? this.albumId,
      addedAt: addedAt ?? this.addedAt,
      addedBy: addedBy ?? this.addedBy,
      notes: notes ?? this.notes,
      isFavorite: isFavorite ?? this.isFavorite,
      album: album ?? this.album,
    );
  }

  @override
  List<Object?> get props => [
        id,
        libraryId,
        albumId,
        addedAt,
        addedBy,
        notes,
        isFavorite,
        album,
      ];
}
