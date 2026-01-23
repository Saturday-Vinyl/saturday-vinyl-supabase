import 'package:equatable/equatable.dart';
import 'package:saturday_consumer_app/models/library.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/library_member_with_user.dart';

/// Extended library information with statistics and member list.
///
/// This model is used for the library details screen, combining:
/// - Basic library metadata
/// - Album count
/// - Member list with user info
/// - Most popular albums by play count
class LibraryDetails extends Equatable {
  final Library library;
  final int albumCount;
  final List<LibraryMemberWithUser> members;
  final List<PopularLibraryAlbum> popularAlbums;

  const LibraryDetails({
    required this.library,
    required this.albumCount,
    required this.members,
    required this.popularAlbums,
  });

  /// Number of members in the library.
  int get memberCount => members.length;

  /// The library owner (first member with owner role).
  LibraryMemberWithUser? get owner {
    try {
      return members.firstWhere((m) => m.isOwner);
    } catch (_) {
      return null;
    }
  }

  /// Members who are not the owner.
  List<LibraryMemberWithUser> get nonOwnerMembers =>
      members.where((m) => !m.isOwner).toList();

  @override
  List<Object?> get props => [library, albumCount, members, popularAlbums];
}

/// A library album with play count for display in popular albums list.
class PopularLibraryAlbum extends Equatable {
  final String id;
  final String libraryId;
  final String albumId;
  final DateTime addedAt;
  final String addedBy;
  final String? notes;
  final bool isFavorite;
  final int playCount;
  final String title;
  final String artist;
  final int? year;
  final String? coverImageUrl;

  const PopularLibraryAlbum({
    required this.id,
    required this.libraryId,
    required this.albumId,
    required this.addedAt,
    required this.addedBy,
    this.notes,
    required this.isFavorite,
    required this.playCount,
    required this.title,
    required this.artist,
    this.year,
    this.coverImageUrl,
  });

  /// Creates from the `get_popular_library_albums` function response.
  factory PopularLibraryAlbum.fromJson(Map<String, dynamic> json) {
    return PopularLibraryAlbum(
      id: json['id'] as String,
      libraryId: json['library_id'] as String,
      albumId: json['album_id'] as String,
      addedAt: DateTime.parse(json['added_at'] as String),
      addedBy: json['added_by'] as String,
      notes: json['notes'] as String?,
      isFavorite: json['is_favorite'] as bool? ?? false,
      playCount: (json['play_count'] as num?)?.toInt() ?? 0,
      title: json['title'] as String,
      artist: json['artist'] as String,
      year: json['year'] as int?,
      coverImageUrl: json['cover_image_url'] as String?,
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
      'play_count': playCount,
      'title': title,
      'artist': artist,
      'year': year,
      'cover_image_url': coverImageUrl,
    };
  }

  /// Convert to a regular LibraryAlbum for navigation purposes.
  LibraryAlbum toLibraryAlbum() {
    return LibraryAlbum(
      id: id,
      libraryId: libraryId,
      albumId: albumId,
      addedAt: addedAt,
      addedBy: addedBy,
      notes: notes,
      isFavorite: isFavorite,
    );
  }

  @override
  List<Object?> get props => [
        id,
        libraryId,
        albumId,
        playCount,
        title,
        artist,
      ];
}
