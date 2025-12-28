import 'package:equatable/equatable.dart';
import 'package:saturday_consumer_app/models/track.dart';

/// Represents a canonical album in the Saturday system.
///
/// Albums are shared across all libraries to avoid duplicate metadata.
/// They contain the core Discogs-sourced information about the record.
class Album extends Equatable {
  final String id;
  final int? discogsId;
  final String title;
  final String artist;
  final int? year;
  final List<String> genres;
  final List<String> styles;
  final String? label;
  final String? coverImageUrl;
  final List<Track> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Album({
    required this.id,
    this.discogsId,
    required this.title,
    required this.artist,
    this.year,
    this.genres = const [],
    this.styles = const [],
    this.label,
    this.coverImageUrl,
    this.tracks = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      discogsId: json['discogs_id'] as int?,
      title: json['title'] as String,
      artist: json['artist'] as String,
      year: json['year'] as int?,
      genres: (json['genres'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      styles: (json['styles'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      label: json['label'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      tracks: (json['tracks'] as List<dynamic>?)
              ?.map((e) => Track.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'discogs_id': discogsId,
      'title': title,
      'artist': artist,
      'year': year,
      'genres': genres,
      'styles': styles,
      'label': label,
      'cover_image_url': coverImageUrl,
      'tracks': tracks.map((t) => t.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Album copyWith({
    String? id,
    int? discogsId,
    String? title,
    String? artist,
    int? year,
    List<String>? genres,
    List<String>? styles,
    String? label,
    String? coverImageUrl,
    List<Track>? tracks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Album(
      id: id ?? this.id,
      discogsId: discogsId ?? this.discogsId,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      year: year ?? this.year,
      genres: genres ?? this.genres,
      styles: styles ?? this.styles,
      label: label ?? this.label,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Returns the total duration of all tracks in seconds.
  int get totalDurationSeconds {
    return tracks.fold(0, (sum, track) => sum + (track.durationSeconds ?? 0));
  }

  /// Returns formatted total duration as HH:MM:SS or MM:SS.
  String get formattedTotalDuration {
    final total = totalDurationSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [
        id,
        discogsId,
        title,
        artist,
        year,
        genres,
        styles,
        label,
        coverImageUrl,
        tracks,
        createdAt,
        updatedAt,
      ];
}
