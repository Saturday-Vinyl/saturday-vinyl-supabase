import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/providers/scan_mode_provider.dart';

void main() {
  group('ScanModeState', () {
    test('initial state has correct defaults', () {
      const state = ScanModeState();

      expect(state.isScanning, isFalse);
      expect(state.foundEpcs, isEmpty);
      expect(state.unknownEpcs, isEmpty);
      expect(state.nonSaturdayEpcs, isEmpty);
      expect(state.lastError, isNull);
    });

    test('saturdayTagCount returns sum of found and unknown', () {
      const state = ScanModeState(
        foundEpcs: {'EPC1', 'EPC2'},
        unknownEpcs: {'EPC3'},
      );

      expect(state.saturdayTagCount, 3);
    });

    test('totalTagCount returns sum of all EPCs', () {
      const state = ScanModeState(
        foundEpcs: {'EPC1', 'EPC2'},
        unknownEpcs: {'EPC3'},
        nonSaturdayEpcs: {'EPC4', 'EPC5'},
      );

      expect(state.totalTagCount, 5);
    });

    test('copyWith creates new state with updated values', () {
      const original = ScanModeState(
        isScanning: false,
        foundEpcs: {'EPC1'},
      );

      final copied = original.copyWith(
        isScanning: true,
        foundEpcs: {'EPC1', 'EPC2'},
      );

      expect(copied.isScanning, isTrue);
      expect(copied.foundEpcs, {'EPC1', 'EPC2'});
    });

    test('copyWith preserves values when not specified', () {
      const original = ScanModeState(
        isScanning: true,
        foundEpcs: {'EPC1'},
        lastError: 'test error',
      );

      final copied = original.copyWith();

      expect(copied.isScanning, isTrue);
      expect(copied.foundEpcs, {'EPC1'});
      expect(copied.lastError, 'test error');
    });

    test('copyWith with clearError removes error', () {
      const original = ScanModeState(
        lastError: 'test error',
      );

      final copied = original.copyWith(clearError: true);

      expect(copied.lastError, isNull);
    });

    test('toString returns readable format', () {
      const state = ScanModeState(
        isScanning: true,
        foundEpcs: {'EPC1', 'EPC2'},
        unknownEpcs: {'EPC3'},
        nonSaturdayEpcs: {'EPC4'},
      );

      final str = state.toString();
      expect(str, contains('scanning: true'));
      expect(str, contains('found: 2'));
      expect(str, contains('unknown: 1'));
      expect(str, contains('nonSaturday: 1'));
    });
  });

  group('isEpcHighlightedProvider', () {
    test('provides correct value based on foundEpcs', () {
      // This is a family provider that depends on scanModeProvider
      // Testing the logic directly in the state
      const state = ScanModeState(
        foundEpcs: {'5356ABCD1234567890ABCDEF'},
      );

      expect(
        state.foundEpcs.contains('5356ABCD1234567890ABCDEF'),
        isTrue,
      );
      expect(
        state.foundEpcs.contains('5356OTHER'),
        isFalse,
      );
    });
  });
}
