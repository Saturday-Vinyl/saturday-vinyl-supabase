import 'package:equatable/equatable.dart';

/// Represents a track on an album.
class Track extends Equatable {
  final String position;
  final String title;
  final int? durationSeconds;

  const Track({
    required this.position,
    required this.title,
    this.durationSeconds,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      position: json['position'] as String,
      title: json['title'] as String,
      durationSeconds: json['duration_seconds'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'position': position,
      'title': title,
      'duration_seconds': durationSeconds,
    };
  }

  Track copyWith({
    String? position,
    String? title,
    int? durationSeconds,
  }) {
    return Track(
      position: position ?? this.position,
      title: title ?? this.title,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  /// Formats duration as MM:SS string.
  String get formattedDuration {
    if (durationSeconds == null) return '--:--';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [position, title, durationSeconds];
}
