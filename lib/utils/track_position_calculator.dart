import 'package:equatable/equatable.dart';
import 'package:saturday_consumer_app/models/track.dart';

/// Represents the current track position within a playing side.
class TrackPosition extends Equatable {
  /// 0-based index into the side's track list.
  final int trackIndex;

  /// The track currently playing.
  final Track track;

  /// Seconds elapsed within this track.
  final int trackElapsedSeconds;

  /// Total duration of this track in seconds (may be estimated).
  final int trackDurationSeconds;

  /// True if any track durations were estimated from averages.
  final bool isEstimated;

  /// True if elapsed time exceeds the total side duration.
  final bool isOvertime;

  const TrackPosition({
    required this.trackIndex,
    required this.track,
    required this.trackElapsedSeconds,
    required this.trackDurationSeconds,
    this.isEstimated = false,
    this.isOvertime = false,
  });

  /// Formats the elapsed time as MM:SS.
  String get formattedElapsed {
    final prefix = isEstimated ? '~' : '';
    final mins = trackElapsedSeconds ~/ 60;
    final secs = trackElapsedSeconds % 60;
    return '$prefix${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// Formats the track duration as MM:SS.
  String get formattedDuration {
    final prefix = isEstimated ? '~' : '';
    final mins = trackDurationSeconds ~/ 60;
    final secs = trackDurationSeconds % 60;
    return '$prefix${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [
        trackIndex,
        track,
        trackElapsedSeconds,
        trackDurationSeconds,
        isEstimated,
        isOvertime,
      ];
}

/// Calculates which track is currently playing based on elapsed time
/// and track durations.
class TrackPositionCalculator {
  TrackPositionCalculator._();

  /// Given elapsed seconds and a list of tracks for the current side,
  /// returns which track is likely playing.
  ///
  /// Returns `null` if the track list is empty or no durations are known.
  static TrackPosition? calculate({
    required int elapsedSeconds,
    required List<Track> tracks,
  }) {
    if (tracks.isEmpty) return null;
    if (elapsedSeconds < 0) elapsedSeconds = 0;

    final durations = effectiveDurations(tracks);
    if (durations.isEmpty) return null;

    final hasEstimated =
        tracks.any((t) => t.durationSeconds == null);
    final totalDuration = durations.fold<int>(0, (sum, d) => sum + d);

    // Past the end — overtime on the last track
    if (elapsedSeconds >= totalDuration) {
      final lastIndex = tracks.length - 1;
      final lastTrackStart = totalDuration - durations[lastIndex];
      return TrackPosition(
        trackIndex: lastIndex,
        track: tracks[lastIndex],
        trackElapsedSeconds: elapsedSeconds - lastTrackStart,
        trackDurationSeconds: durations[lastIndex],
        isEstimated: hasEstimated,
        isOvertime: true,
      );
    }

    // Walk through tracks to find the current one
    var cumulative = 0;
    for (var i = 0; i < tracks.length; i++) {
      final trackEnd = cumulative + durations[i];
      if (elapsedSeconds < trackEnd) {
        return TrackPosition(
          trackIndex: i,
          track: tracks[i],
          trackElapsedSeconds: elapsedSeconds - cumulative,
          trackDurationSeconds: durations[i],
          isEstimated: hasEstimated,
          isOvertime: false,
        );
      }
      cumulative = trackEnd;
    }

    // Should not reach here, but return last track as fallback
    final lastIndex = tracks.length - 1;
    return TrackPosition(
      trackIndex: lastIndex,
      track: tracks[lastIndex],
      trackElapsedSeconds: elapsedSeconds - (totalDuration - durations[lastIndex]),
      trackDurationSeconds: durations[lastIndex],
      isEstimated: hasEstimated,
      isOvertime: true,
    );
  }

  /// Returns effective durations for each track, filling null durations
  /// with the average of known durations.
  ///
  /// Returns an empty list if no tracks have known durations.
  static List<int> effectiveDurations(List<Track> tracks) {
    if (tracks.isEmpty) return [];

    final knownDurations = tracks
        .where((t) => t.durationSeconds != null)
        .map((t) => t.durationSeconds!)
        .toList();

    if (knownDurations.isEmpty) return [];

    final average =
        knownDurations.fold<int>(0, (sum, d) => sum + d) ~/ knownDurations.length;

    return tracks
        .map((t) => t.durationSeconds ?? average)
        .toList();
  }
}
