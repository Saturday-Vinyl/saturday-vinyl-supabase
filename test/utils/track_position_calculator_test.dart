import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_consumer_app/models/track.dart';
import 'package:saturday_consumer_app/utils/track_position_calculator.dart';

void main() {
  group('TrackPositionCalculator.calculate', () {
    test('returns null for empty track list', () {
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 0,
        tracks: [],
      );
      expect(result, isNull);
    });

    test('returns null when all durations are null', () {
      final tracks = [
        const Track(position: 'A1', title: 'Track 1'),
        const Track(position: 'A2', title: 'Track 2'),
      ];
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 60,
        tracks: tracks,
      );
      expect(result, isNull);
    });

    test('returns first track at elapsed=0', () {
      final tracks = [
        const Track(position: 'A1', title: 'Track 1', durationSeconds: 180),
        const Track(position: 'A2', title: 'Track 2', durationSeconds: 240),
        const Track(position: 'A3', title: 'Track 3', durationSeconds: 300),
      ];
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 0,
        tracks: tracks,
      );
      expect(result, isNotNull);
      expect(result!.trackIndex, 0);
      expect(result.track.title, 'Track 1');
      expect(result.trackElapsedSeconds, 0);
      expect(result.trackDurationSeconds, 180);
      expect(result.isEstimated, false);
      expect(result.isOvertime, false);
    });

    test('returns correct track when elapsed is in middle of track 2', () {
      final tracks = [
        const Track(position: 'A1', title: 'Track 1', durationSeconds: 180),
        const Track(position: 'A2', title: 'Track 2', durationSeconds: 240),
        const Track(position: 'A3', title: 'Track 3', durationSeconds: 300),
      ];
      // 180 (track 1) + 60 = 240 elapsed → 60 seconds into track 2
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 240,
        tracks: tracks,
      );
      expect(result, isNotNull);
      expect(result!.trackIndex, 1);
      expect(result.track.title, 'Track 2');
      expect(result.trackElapsedSeconds, 60);
      expect(result.trackDurationSeconds, 240);
      expect(result.isOvertime, false);
    });

    test('returns next track at exact track boundary', () {
      final tracks = [
        const Track(position: 'A1', title: 'Track 1', durationSeconds: 180),
        const Track(position: 'A2', title: 'Track 2', durationSeconds: 240),
      ];
      // Exactly at 180 seconds → start of track 2
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 180,
        tracks: tracks,
      );
      expect(result, isNotNull);
      expect(result!.trackIndex, 1);
      expect(result.track.title, 'Track 2');
      expect(result.trackElapsedSeconds, 0);
    });

    test('returns last track with overtime when past total duration', () {
      final tracks = [
        const Track(position: 'A1', title: 'Track 1', durationSeconds: 180),
        const Track(position: 'A2', title: 'Track 2', durationSeconds: 240),
      ];
      // Total = 420, elapsed = 500 → 80 seconds overtime into last track
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 500,
        tracks: tracks,
      );
      expect(result, isNotNull);
      expect(result!.trackIndex, 1);
      expect(result.track.title, 'Track 2');
      expect(result.trackElapsedSeconds, 320); // 500 - 180 = 320
      expect(result.isOvertime, true);
    });

    test('estimates durations when some are null', () {
      final tracks = [
        const Track(position: 'A1', title: 'Track 1', durationSeconds: 180),
        const Track(position: 'A2', title: 'Track 2'), // null duration
        const Track(position: 'A3', title: 'Track 3', durationSeconds: 240),
      ];
      // Average of known = (180 + 240) / 2 = 210
      // Track 2 estimated at 210
      // Elapsed = 200 → still in track 2 (180 + 20)
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 200,
        tracks: tracks,
      );
      expect(result, isNotNull);
      expect(result!.trackIndex, 1);
      expect(result.track.title, 'Track 2');
      expect(result.trackElapsedSeconds, 20); // 200 - 180
      expect(result.isEstimated, true);
    });

    test('returns single track with duration at elapsed=0', () {
      final tracks = [
        const Track(position: 'A1', title: 'Only Track', durationSeconds: 300),
      ];
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 0,
        tracks: tracks,
      );
      expect(result, isNotNull);
      expect(result!.trackIndex, 0);
      expect(result.trackElapsedSeconds, 0);
      expect(result.trackDurationSeconds, 300);
    });

    test('returns null for single track without duration', () {
      final tracks = [
        const Track(position: 'A1', title: 'Only Track'),
      ];
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 60,
        tracks: tracks,
      );
      expect(result, isNull);
    });

    test('handles negative elapsed seconds gracefully', () {
      final tracks = [
        const Track(position: 'A1', title: 'Track 1', durationSeconds: 180),
      ];
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: -10,
        tracks: tracks,
      );
      expect(result, isNotNull);
      expect(result!.trackIndex, 0);
      expect(result.trackElapsedSeconds, 0);
    });

    test('returns last track overtime when elapsed equals total duration', () {
      final tracks = [
        const Track(position: 'A1', title: 'Track 1', durationSeconds: 180),
        const Track(position: 'A2', title: 'Track 2', durationSeconds: 240),
      ];
      // Exactly at total (420) → overtime
      final result = TrackPositionCalculator.calculate(
        elapsedSeconds: 420,
        tracks: tracks,
      );
      expect(result, isNotNull);
      expect(result!.trackIndex, 1);
      expect(result.isOvertime, true);
      expect(result.trackElapsedSeconds, 240);
    });
  });

  group('TrackPositionCalculator.effectiveDurations', () {
    test('returns durations as-is when all are known', () {
      final tracks = [
        const Track(position: 'A1', title: 'T1', durationSeconds: 180),
        const Track(position: 'A2', title: 'T2', durationSeconds: 240),
      ];
      expect(
        TrackPositionCalculator.effectiveDurations(tracks),
        [180, 240],
      );
    });

    test('fills null durations with average of known', () {
      final tracks = [
        const Track(position: 'A1', title: 'T1', durationSeconds: 180),
        const Track(position: 'A2', title: 'T2'),
        const Track(position: 'A3', title: 'T3', durationSeconds: 240),
      ];
      // Average = (180 + 240) / 2 = 210
      expect(
        TrackPositionCalculator.effectiveDurations(tracks),
        [180, 210, 240],
      );
    });

    test('returns empty list when all durations are null', () {
      final tracks = [
        const Track(position: 'A1', title: 'T1'),
        const Track(position: 'A2', title: 'T2'),
      ];
      expect(TrackPositionCalculator.effectiveDurations(tracks), isEmpty);
    });

    test('returns empty list for empty track list', () {
      expect(TrackPositionCalculator.effectiveDurations([]), isEmpty);
    });
  });

  group('TrackPosition formatting', () {
    test('formats elapsed and duration without prefix when not estimated', () {
      const position = TrackPosition(
        trackIndex: 0,
        track: Track(position: 'A1', title: 'Test', durationSeconds: 300),
        trackElapsedSeconds: 134,
        trackDurationSeconds: 300,
      );
      expect(position.formattedElapsed, '02:14');
      expect(position.formattedDuration, '05:00');
    });

    test('formats with ~ prefix when estimated', () {
      const position = TrackPosition(
        trackIndex: 0,
        track: Track(position: 'A1', title: 'Test', durationSeconds: 300),
        trackElapsedSeconds: 134,
        trackDurationSeconds: 300,
        isEstimated: true,
      );
      expect(position.formattedElapsed, '~02:14');
      expect(position.formattedDuration, '~05:00');
    });
  });
}
