import 'package:equatable/equatable.dart';

/// A distinct artist credited on one or more albums in a library.
///
/// Produced by the `search_library_artists` RPC. Only includes artists
/// with a stable Discogs artist ID so we can route to a disambiguated
/// landing page.
class LibraryArtist extends Equatable {
  final int discogsArtistId;
  final String name;
  final int albumCount;

  const LibraryArtist({
    required this.discogsArtistId,
    required this.name,
    required this.albumCount,
  });

  factory LibraryArtist.fromJson(Map<String, dynamic> json) {
    return LibraryArtist(
      discogsArtistId: json['discogs_artist_id'] as int,
      name: json['name'] as String,
      albumCount: (json['album_count'] as num).toInt(),
    );
  }

  @override
  List<Object?> get props => [discogsArtistId, name, albumCount];
}
