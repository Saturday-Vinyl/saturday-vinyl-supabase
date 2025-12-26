import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/activity_log_entry.dart';
import 'package:saturday_app/providers/activity_log_provider.dart';

void main() {
  group('ActivityLogNotifier', () {
    late ActivityLogNotifier notifier;

    setUp(() {
      notifier = ActivityLogNotifier();
    });

    test('initial state is empty list', () {
      expect(notifier.state, isEmpty);
    });

    test('addEntry adds entry to state', () {
      notifier.addEntry('Test message', LogLevel.info);

      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.message, 'Test message');
      expect(notifier.state.first.level, LogLevel.info);
    });

    test('addEntry with relatedEpc sets the epc', () {
      notifier.addEntry('Tag found', LogLevel.success,
          relatedEpc: '5356A1B2C3D4E5F67890ABCD');

      expect(notifier.state.first.relatedEpc, '5356A1B2C3D4E5F67890ABCD');
    });

    test('info() adds info level entry', () {
      notifier.info('Info message');

      expect(notifier.state.first.level, LogLevel.info);
      expect(notifier.state.first.message, 'Info message');
    });

    test('success() adds success level entry', () {
      notifier.success('Success message');

      expect(notifier.state.first.level, LogLevel.success);
      expect(notifier.state.first.message, 'Success message');
    });

    test('warning() adds warning level entry', () {
      notifier.warning('Warning message');

      expect(notifier.state.first.level, LogLevel.warning);
      expect(notifier.state.first.message, 'Warning message');
    });

    test('error() adds error level entry', () {
      notifier.error('Error message');

      expect(notifier.state.first.level, LogLevel.error);
      expect(notifier.state.first.message, 'Error message');
    });

    test('clear() removes all entries', () {
      notifier.info('Message 1');
      notifier.info('Message 2');
      notifier.info('Message 3');

      expect(notifier.state, hasLength(3));

      notifier.clear();

      expect(notifier.state, isEmpty);
    });

    test('entries are stored newest first', () {
      notifier.info('First');
      notifier.info('Second');
      notifier.info('Third');

      expect(notifier.state[0].message, 'Third');
      expect(notifier.state[1].message, 'Second');
      expect(notifier.state[2].message, 'First');
    });

    test('entriesInDisplayOrder returns oldest first', () {
      notifier.info('First');
      notifier.info('Second');
      notifier.info('Third');

      final displayOrder = notifier.entriesInDisplayOrder;

      expect(displayOrder[0].message, 'First');
      expect(displayOrder[1].message, 'Second');
      expect(displayOrder[2].message, 'Third');
    });

    test('max entries limit is enforced', () {
      // Add more than 100 entries
      for (var i = 0; i < 110; i++) {
        notifier.info('Message $i');
      }

      // Should be capped at 100
      expect(notifier.state, hasLength(100));

      // Newest entries should be kept (109 down to 10)
      expect(notifier.state.first.message, 'Message 109');
      expect(notifier.state.last.message, 'Message 10');
    });

    test('entries have unique ids', () {
      notifier.info('Message 1');
      notifier.info('Message 2');

      expect(notifier.state[0].id, isNot(equals(notifier.state[1].id)));
    });

    test('entries have timestamps', () {
      final before = DateTime.now();
      notifier.info('Message');
      final after = DateTime.now();

      final timestamp = notifier.state.first.timestamp;
      expect(timestamp.isAfter(before) || timestamp.isAtSameMomentAs(before),
          isTrue);
      expect(
          timestamp.isBefore(after) || timestamp.isAtSameMomentAs(after), isTrue);
    });
  });
}
