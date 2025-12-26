import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/activity_log_entry.dart';

void main() {
  group('ActivityLogEntry', () {
    test('creates entry with all properties', () {
      final timestamp = DateTime(2025, 1, 15, 10, 30);
      final entry = ActivityLogEntry(
        id: 'test-id',
        timestamp: timestamp,
        message: 'Test message',
        level: LogLevel.info,
        relatedEpc: '5356ABCD',
      );

      expect(entry.id, 'test-id');
      expect(entry.timestamp, timestamp);
      expect(entry.message, 'Test message');
      expect(entry.level, LogLevel.info);
      expect(entry.relatedEpc, '5356ABCD');
    });

    test('generates id if not provided', () {
      final entry = ActivityLogEntry(
        message: 'Test',
        level: LogLevel.info,
      );

      expect(entry.id, isNotEmpty);
    });

    test('uses current time if timestamp not provided', () {
      final before = DateTime.now();
      final entry = ActivityLogEntry(
        message: 'Test',
        level: LogLevel.info,
      );
      final after = DateTime.now();

      expect(
          entry.timestamp.isAfter(before) ||
              entry.timestamp.isAtSameMomentAs(before),
          isTrue);
      expect(
          entry.timestamp.isBefore(after) ||
              entry.timestamp.isAtSameMomentAs(after),
          isTrue);
    });

    test('info factory creates info level entry', () {
      final entry = ActivityLogEntry.info('Info message');

      expect(entry.level, LogLevel.info);
      expect(entry.message, 'Info message');
    });

    test('success factory creates success level entry', () {
      final entry = ActivityLogEntry.success('Success message');

      expect(entry.level, LogLevel.success);
      expect(entry.message, 'Success message');
    });

    test('warning factory creates warning level entry', () {
      final entry = ActivityLogEntry.warning('Warning message');

      expect(entry.level, LogLevel.warning);
      expect(entry.message, 'Warning message');
    });

    test('error factory creates error level entry', () {
      final entry = ActivityLogEntry.error('Error message');

      expect(entry.level, LogLevel.error);
      expect(entry.message, 'Error message');
    });

    test('factory methods accept relatedEpc', () {
      final entry =
          ActivityLogEntry.info('Tagged', relatedEpc: '5356TESTCODE');

      expect(entry.relatedEpc, '5356TESTCODE');
    });

    test('copyWith creates new instance with updated values', () {
      final original = ActivityLogEntry(
        id: 'original-id',
        message: 'Original',
        level: LogLevel.info,
      );

      final copied = original.copyWith(
        message: 'Copied',
        level: LogLevel.error,
      );

      expect(copied.id, 'original-id'); // Unchanged
      expect(copied.message, 'Copied'); // Changed
      expect(copied.level, LogLevel.error); // Changed
    });

    test('copyWith preserves values when not specified', () {
      final original = ActivityLogEntry(
        id: 'test-id',
        message: 'Test',
        level: LogLevel.warning,
        relatedEpc: '5356ABCD',
      );

      final copied = original.copyWith();

      expect(copied.id, original.id);
      expect(copied.message, original.message);
      expect(copied.level, original.level);
      expect(copied.relatedEpc, original.relatedEpc);
    });

    test('equality works correctly', () {
      final timestamp = DateTime(2025, 1, 15);
      final entry1 = ActivityLogEntry(
        id: 'same-id',
        timestamp: timestamp,
        message: 'Same message',
        level: LogLevel.info,
      );
      final entry2 = ActivityLogEntry(
        id: 'same-id',
        timestamp: timestamp,
        message: 'Same message',
        level: LogLevel.info,
      );
      final entry3 = ActivityLogEntry(
        id: 'different-id',
        timestamp: timestamp,
        message: 'Same message',
        level: LogLevel.info,
      );

      expect(entry1, equals(entry2));
      expect(entry1, isNot(equals(entry3)));
    });

    test('toString returns readable format', () {
      final entry = ActivityLogEntry(
        id: 'test-id',
        message: 'Test message',
        level: LogLevel.error,
      );

      expect(entry.toString(), contains('test-id'));
      expect(entry.toString(), contains('Test message'));
      expect(entry.toString(), contains('error'));
    });
  });

  group('LogLevel', () {
    test('has all expected values', () {
      expect(LogLevel.values, contains(LogLevel.info));
      expect(LogLevel.values, contains(LogLevel.success));
      expect(LogLevel.values, contains(LogLevel.warning));
      expect(LogLevel.values, contains(LogLevel.error));
      expect(LogLevel.values, hasLength(4));
    });
  });
}
