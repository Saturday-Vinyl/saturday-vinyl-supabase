import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/providers/scan_mode_provider.dart';
import 'package:saturday_app/widgets/tags/scan_mode_indicator.dart';

void main() {
  Widget createTestWidget({
    ScanModeState? scanState,
  }) {
    return ProviderScope(
      overrides: [
        scanModeProvider.overrideWith((ref) {
          return _TestScanModeNotifier(scanState ?? const ScanModeState());
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: ScanModeIndicator(),
        ),
      ),
    );
  }

  group('ScanModeIndicator', () {
    testWidgets('hides when not scanning', (tester) async {
      await tester.pumpWidget(createTestWidget(
        scanState: const ScanModeState(isScanning: false),
      ));
      await tester.pumpAndSettle();

      // Should not find any content since it returns SizedBox.shrink()
      expect(find.text('Scanning...'), findsNothing);
    });

    testWidgets('shows when scanning', (tester) async {
      await tester.pumpWidget(createTestWidget(
        scanState: const ScanModeState(isScanning: true),
      ));
      await tester.pump();

      expect(find.text('Scanning...'), findsOneWidget);
    });

    testWidgets('shows found count', (tester) async {
      await tester.pumpWidget(createTestWidget(
        scanState: const ScanModeState(
          isScanning: true,
          foundEpcs: {'EPC1', 'EPC2', 'EPC3'},
        ),
      ));
      await tester.pump();

      expect(find.text('Found'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('shows unknown count when present', (tester) async {
      await tester.pumpWidget(createTestWidget(
        scanState: const ScanModeState(
          isScanning: true,
          foundEpcs: {'EPC1'},
          unknownEpcs: {'EPC2', 'EPC3'},
        ),
      ));
      await tester.pump();

      expect(find.text('Unknown'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('hides unknown count when empty', (tester) async {
      await tester.pumpWidget(createTestWidget(
        scanState: const ScanModeState(
          isScanning: true,
          foundEpcs: {'EPC1'},
          unknownEpcs: {},
        ),
      ));
      await tester.pump();

      expect(find.text('Unknown'), findsNothing);
    });
  });

  group('ScanStatusChip', () {
    Widget createChipWidget({
      ScanModeState? scanState,
      VoidCallback? onTap,
    }) {
      return ProviderScope(
        overrides: [
          scanModeProvider.overrideWith((ref) {
            return _TestScanModeNotifier(scanState ?? const ScanModeState());
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ScanStatusChip(onTap: onTap),
          ),
        ),
      );
    }

    testWidgets('hides when not scanning and no found tags', (tester) async {
      await tester.pumpWidget(createChipWidget(
        scanState: const ScanModeState(
          isScanning: false,
          foundEpcs: {},
        ),
      ));
      await tester.pumpAndSettle();

      // Should find nothing since it returns SizedBox.shrink()
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('shows scanning state with count', (tester) async {
      await tester.pumpWidget(createChipWidget(
        scanState: const ScanModeState(
          isScanning: true,
          foundEpcs: {'EPC1', 'EPC2'},
        ),
      ));
      await tester.pump();

      expect(find.text('Scanning (2)'), findsOneWidget);
    });

    testWidgets('shows found count when not scanning but has results',
        (tester) async {
      await tester.pumpWidget(createChipWidget(
        scanState: const ScanModeState(
          isScanning: false,
          foundEpcs: {'EPC1', 'EPC2', 'EPC3'},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('3 found'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(createChipWidget(
        scanState: const ScanModeState(
          isScanning: false,
          foundEpcs: {'EPC1'},
        ),
        onTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('shows circular progress indicator when scanning',
        (tester) async {
      await tester.pumpWidget(createChipWidget(
        scanState: const ScanModeState(
          isScanning: true,
        ),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

/// Test notifier that exposes a fixed state
class _TestScanModeNotifier extends ScanModeNotifier {
  _TestScanModeNotifier(ScanModeState initialState) : super(_FakeRef()) {
    state = initialState;
  }
}

/// Fake Ref for testing
class _FakeRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
