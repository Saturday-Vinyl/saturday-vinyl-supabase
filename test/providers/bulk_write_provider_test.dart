import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/providers/bulk_write_provider.dart';

void main() {
  group('BulkWriteState', () {
    test('initial state has correct defaults', () {
      const state = BulkWriteState();

      expect(state.isWriting, isFalse);
      expect(state.tagsWritten, 0);
      expect(state.currentOperation, isNull);
      expect(state.lastError, isNull);
      expect(state.stopRequested, isFalse);
    });

    test('copyWith creates new state with updated values', () {
      const original = BulkWriteState(
        isWriting: false,
        tagsWritten: 0,
      );

      final copied = original.copyWith(
        isWriting: true,
        tagsWritten: 5,
        currentOperation: 'Writing EPC...',
      );

      expect(copied.isWriting, isTrue);
      expect(copied.tagsWritten, 5);
      expect(copied.currentOperation, 'Writing EPC...');
    });

    test('copyWith preserves values when not specified', () {
      const original = BulkWriteState(
        isWriting: true,
        tagsWritten: 3,
        currentOperation: 'Verifying...',
        lastError: null,
        stopRequested: false,
      );

      final copied = original.copyWith();

      expect(copied.isWriting, isTrue);
      expect(copied.tagsWritten, 3);
      expect(copied.currentOperation, 'Verifying...');
      expect(copied.lastError, isNull);
      expect(copied.stopRequested, isFalse);
    });

    test('copyWith with clearOperation removes operation', () {
      const original = BulkWriteState(
        currentOperation: 'Writing...',
      );

      final copied = original.copyWith(clearOperation: true);

      expect(copied.currentOperation, isNull);
    });

    test('copyWith with clearError removes error', () {
      const original = BulkWriteState(
        lastError: 'test error',
      );

      final copied = original.copyWith(clearError: true);

      expect(copied.lastError, isNull);
    });

    test('copyWith can set stopRequested', () {
      const original = BulkWriteState(
        isWriting: true,
        stopRequested: false,
      );

      final copied = original.copyWith(stopRequested: true);

      expect(copied.stopRequested, isTrue);
    });

    test('toString returns readable format', () {
      const state = BulkWriteState(
        isWriting: true,
        tagsWritten: 5,
        currentOperation: 'Locking...',
      );

      final str = state.toString();
      expect(str, contains('writing: true'));
      expect(str, contains('written: 5'));
      expect(str, contains('op: Locking...'));
    });

    test('state can track full write cycle', () {
      // Start writing
      var state = const BulkWriteState().copyWith(
        isWriting: true,
        currentOperation: 'Searching for unwritten tags...',
      );
      expect(state.isWriting, isTrue);
      expect(state.tagsWritten, 0);

      // Found tag, writing
      state = state.copyWith(
        currentOperation: 'Writing EPC...',
      );
      expect(state.currentOperation, 'Writing EPC...');

      // Verifying
      state = state.copyWith(
        currentOperation: 'Verifying write...',
      );
      expect(state.currentOperation, 'Verifying write...');

      // Locking
      state = state.copyWith(
        currentOperation: 'Locking tag...',
      );
      expect(state.currentOperation, 'Locking tag...');

      // Saving
      state = state.copyWith(
        currentOperation: 'Saving to database...',
      );
      expect(state.currentOperation, 'Saving to database...');

      // Complete one tag
      state = state.copyWith(
        tagsWritten: 1,
        currentOperation: 'Searching for unwritten tags...',
      );
      expect(state.tagsWritten, 1);

      // Second tag complete
      state = state.copyWith(
        tagsWritten: 2,
      );
      expect(state.tagsWritten, 2);

      // Stop requested
      state = state.copyWith(stopRequested: true);
      expect(state.stopRequested, isTrue);

      // Writing stopped
      state = state.copyWith(
        isWriting: false,
        stopRequested: false,
        clearOperation: true,
      );
      expect(state.isWriting, isFalse);
      expect(state.tagsWritten, 2);
      expect(state.currentOperation, isNull);
    });

    test('state can track error condition', () {
      var state = const BulkWriteState().copyWith(
        isWriting: true,
        currentOperation: 'Writing EPC...',
      );

      // Error during write
      state = state.copyWith(
        isWriting: false,
        lastError: 'Error: Write failed',
        clearOperation: true,
      );

      expect(state.isWriting, isFalse);
      expect(state.lastError, 'Error: Write failed');
      expect(state.currentOperation, isNull);
    });
  });

  group('BulkWriteProvider', () {
    test('isBulkWritingProvider reflects isWriting state', () {
      // This tests that the derived provider would work correctly
      // based on the state
      const notWriting = BulkWriteState(isWriting: false);
      const writing = BulkWriteState(isWriting: true);

      expect(notWriting.isWriting, isFalse);
      expect(writing.isWriting, isTrue);
    });
  });
}
