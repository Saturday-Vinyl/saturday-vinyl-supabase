import 'package:equatable/equatable.dart';

/// Aggregated album analytics for a single user.
///
/// Returned in one shot by the `get_user_album_analytics` Postgres RPC.
class AlbumAnalytics extends Equatable {
  final AlbumAnalyticsTotals totals;
  final List<TopAlbum> topAlbums;
  final List<TopArtist> topArtists;
  final List<TopGenre> topGenres;
  final List<DecadeBucket> decades;
  final List<DailyPlayCount> dailyPlays;
  final DateTime generatedAt;

  const AlbumAnalytics({
    required this.totals,
    required this.topAlbums,
    required this.topArtists,
    required this.topGenres,
    required this.decades,
    required this.dailyPlays,
    required this.generatedAt,
  });

  factory AlbumAnalytics.fromJson(Map<String, dynamic> json) {
    return AlbumAnalytics(
      totals: AlbumAnalyticsTotals.fromJson(
        (json['totals'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      topAlbums: ((json['top_albums'] as List?) ?? const [])
          .map((e) => TopAlbum.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      topArtists: ((json['top_artists'] as List?) ?? const [])
          .map((e) => TopArtist.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      topGenres: ((json['top_genres'] as List?) ?? const [])
          .map((e) => TopGenre.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      decades: ((json['decades'] as List?) ?? const [])
          .map((e) => DecadeBucket.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      dailyPlays: ((json['daily_plays'] as List?) ?? const [])
          .map((e) =>
              DailyPlayCount.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  bool get hasAnyPlays => totals.totalPlays > 0;

  @override
  List<Object?> get props => [
        totals,
        topAlbums,
        topArtists,
        topGenres,
        decades,
        dailyPlays,
        generatedAt,
      ];
}

class AlbumAnalyticsTotals extends Equatable {
  final int totalPlays;
  final int totalSeconds;
  final int totalAlbums;
  final int totalFavorites;
  final int totalArtists;

  const AlbumAnalyticsTotals({
    required this.totalPlays,
    required this.totalSeconds,
    required this.totalAlbums,
    required this.totalFavorites,
    required this.totalArtists,
  });

  factory AlbumAnalyticsTotals.fromJson(Map<String, dynamic> json) {
    return AlbumAnalyticsTotals(
      totalPlays: _asInt(json['total_plays']),
      totalSeconds: _asInt(json['total_seconds']),
      totalAlbums: _asInt(json['total_albums']),
      totalFavorites: _asInt(json['total_favorites']),
      totalArtists: _asInt(json['total_artists']),
    );
  }

  /// Total listening time rounded to whole hours.
  int get totalHours => totalSeconds ~/ 3600;

  @override
  List<Object?> get props => [
        totalPlays,
        totalSeconds,
        totalAlbums,
        totalFavorites,
        totalArtists,
      ];
}

class TopAlbum extends Equatable {
  final String? libraryAlbumId;
  final String? albumId;
  final String title;
  final String artist;
  final int? year;
  final String? coverImageUrl;
  final int playCount;

  const TopAlbum({
    required this.libraryAlbumId,
    required this.albumId,
    required this.title,
    required this.artist,
    required this.year,
    required this.coverImageUrl,
    required this.playCount,
  });

  factory TopAlbum.fromJson(Map<String, dynamic> json) {
    return TopAlbum(
      libraryAlbumId: json['library_album_id'] as String?,
      albumId: json['album_id'] as String?,
      title: (json['title'] as String?) ?? 'Unknown Album',
      artist: (json['artist'] as String?) ?? 'Unknown Artist',
      year: json['year'] as int?,
      coverImageUrl: json['cover_image_url'] as String?,
      playCount: _asInt(json['play_count']),
    );
  }

  @override
  List<Object?> get props =>
      [libraryAlbumId, albumId, title, artist, year, coverImageUrl, playCount];
}

class TopArtist extends Equatable {
  final String artist;
  final int playCount;

  const TopArtist({required this.artist, required this.playCount});

  factory TopArtist.fromJson(Map<String, dynamic> json) {
    return TopArtist(
      artist: (json['artist'] as String?) ?? 'Unknown Artist',
      playCount: _asInt(json['play_count']),
    );
  }

  @override
  List<Object?> get props => [artist, playCount];
}

class TopGenre extends Equatable {
  final String genre;
  final int playCount;

  const TopGenre({required this.genre, required this.playCount});

  factory TopGenre.fromJson(Map<String, dynamic> json) {
    return TopGenre(
      genre: (json['genre'] as String?) ?? 'Unknown',
      playCount: _asInt(json['play_count']),
    );
  }

  @override
  List<Object?> get props => [genre, playCount];
}

class DecadeBucket extends Equatable {
  final int decade;
  final int albumCount;

  const DecadeBucket({required this.decade, required this.albumCount});

  factory DecadeBucket.fromJson(Map<String, dynamic> json) {
    return DecadeBucket(
      decade: _asInt(json['decade']),
      albumCount: _asInt(json['album_count']),
    );
  }

  String get label => "${decade}s";

  @override
  List<Object?> get props => [decade, albumCount];
}

class DailyPlayCount extends Equatable {
  final DateTime day;
  final int playCount;

  const DailyPlayCount({required this.day, required this.playCount});

  factory DailyPlayCount.fromJson(Map<String, dynamic> json) {
    final raw = json['day'];
    final parsed = raw is String
        ? DateTime.tryParse(raw) ?? DateTime.now()
        : DateTime.now();
    return DailyPlayCount(
      day: DateTime.utc(parsed.year, parsed.month, parsed.day),
      playCount: _asInt(json['play_count']),
    );
  }

  @override
  List<Object?> get props => [day, playCount];
}

int _asInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}
