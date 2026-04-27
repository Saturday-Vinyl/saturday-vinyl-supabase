import 'package:equatable/equatable.dart';
import 'package:saturday_consumer_app/models/library_album.dart';

/// One album in a cratelist, with its position within the ordered list.
///
/// References a library_album rather than a canonical album so the album
/// is grounded in some library's collection. The joined [libraryAlbum] is
/// populated when the row is fetched with the embed query.
class CratelistItem extends Equatable {
  final String id;
  final String cratelistId;
  final String libraryAlbumId;
  final int position;
  final DateTime addedAt;
  final String? addedBy;
  final LibraryAlbum? libraryAlbum;

  const CratelistItem({
    required this.id,
    required this.cratelistId,
    required this.libraryAlbumId,
    required this.position,
    required this.addedAt,
    this.addedBy,
    this.libraryAlbum,
  });

  factory CratelistItem.fromJson(Map<String, dynamic> json) {
    return CratelistItem(
      id: json['id'] as String,
      cratelistId: json['cratelist_id'] as String,
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
      'cratelist_id': cratelistId,
      'library_album_id': libraryAlbumId,
      'position': position,
      'added_at': addedAt.toIso8601String(),
      'added_by': addedBy,
      if (libraryAlbum != null) 'library_album': libraryAlbum!.toJson(),
    };
  }

  CratelistItem copyWith({
    String? id,
    String? cratelistId,
    String? libraryAlbumId,
    int? position,
    DateTime? addedAt,
    String? addedBy,
    LibraryAlbum? libraryAlbum,
  }) {
    return CratelistItem(
      id: id ?? this.id,
      cratelistId: cratelistId ?? this.cratelistId,
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
        cratelistId,
        libraryAlbumId,
        position,
        addedAt,
        addedBy,
        libraryAlbum,
      ];
}
