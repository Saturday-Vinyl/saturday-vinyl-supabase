import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/providers/bulk_write_provider.dart';
import 'package:saturday_app/widgets/tags/bulk_write_status.dart';

void main() {
  Widget createTestWidget({
    BulkWriteState? bulkState,
    VoidCallback? onStop,
  }) {
    return ProviderScope(
      overrides: [
        bulkWriteProvider.overrideWith((ref) {
          return _TestBulkWriteNotifier(bulkState ?? const BulkWriteState());
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: BulkWriteStatus(onStop: onStop),
        ),
      ),
    );
  }

  group('BulkWriteStatus', () {
    testWidgets('hides when not writing', (tester) async {
      await tester.pumpWidget(createTestWidget(
        bulkState: const BulkWriteState(isWriting: false),
      ));
      await tester.pumpAndSettle();

      // Should not find any content since it returns SizedBox.shrink()
      expect(find.text('Stop'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows when writing', (tester) async {
      await tester.pumpWidget(createTestWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
          currentOperation: 'Writing EPC...',
        ),
      ));
      await tester.pump();

      expect(find.text('Writing EPC...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows current operation text', (tester) async {
      await tester.pumpWidget(createTestWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
          currentOperation: 'Verifying write...',
        ),
      ));
      await tester.pump();

      expect(find.text('Verifying write...'), findsOneWidget);
    });

    testWidgets('shows tags written count', (tester) async {
      await tester.pumpWidget(createTestWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
          tagsWritten: 5,
          currentOperation: 'Searching...',
        ),
      ));
      await tester.pump();

      expect(find.text('5 tags created'), findsOneWidget);
    });

    testWidgets('shows singular tag text for 1 tag', (tester) async {
      await tester.pumpWidget(createTestWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
          tagsWritten: 1,
          currentOperation: 'Searching...',
        ),
      ));
      await tester.pump();

      expect(find.text('1 tag created'), findsOneWidget);
    });

    testWidgets('shows stop button', (tester) async {
      await tester.pumpWidget(createTestWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
          currentOperation: 'Writing...',
        ),
      ));
      await tester.pump();

      expect(find.text('Stop'), findsOneWidget);
    });

    testWidgets('shows stopping text when stop requested', (tester) async {
      await tester.pumpWidget(createTestWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
          stopRequested: true,
          currentOperation: 'Finishing current tag...',
        ),
      ));
      await tester.pump();

      expect(find.text('Stopping...'), findsOneWidget);
    });

    testWidgets('shows count badge with check icon', (tester) async {
      await tester.pumpWidget(createTestWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
          tagsWritten: 3,
          currentOperation: 'Searching...',
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('hides tags created text when zero', (tester) async {
      await tester.pumpWidget(createTestWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
          tagsWritten: 0,
          currentOperation: 'Searching...',
        ),
      ));
      await tester.pump();

      expect(find.textContaining('tag created'), findsNothing);
      expect(find.textContaining('tags created'), findsNothing);
    });
  });

  group('BulkWriteChip', () {
    Widget createChipWidget({
      BulkWriteState? bulkState,
      VoidCallback? onTap,
    }) {
      return ProviderScope(
        overrides: [
          bulkWriteProvider.overrideWith((ref) {
            return _TestBulkWriteNotifier(bulkState ?? const BulkWriteState());
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BulkWriteChip(onTap: onTap),
          ),
        ),
      );
    }

    testWidgets('hides when not writing and no tags written', (tester) async {
      await tester.pumpWidget(createChipWidget(
        bulkState: const BulkWriteState(
          isWriting: false,
          tagsWritten: 0,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('shows writing state with count', (tester) async {
      await tester.pumpWidget(createChipWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
          tagsWritten: 2,
        ),
      ));
      await tester.pump();

      expect(find.text('Writing (2)'), findsOneWidget);
    });

    testWidgets('shows written count when not writing but has results',
        (tester) async {
      await tester.pumpWidget(createChipWidget(
        bulkState: const BulkWriteState(
          isWriting: false,
          tagsWritten: 5,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('5 written'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(createChipWidget(
        bulkState: const BulkWriteState(
          isWriting: false,
          tagsWritten: 1,
        ),
        onTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('shows circular progress indicator when writing',
        (tester) async {
      await tester.pumpWidget(createChipWidget(
        bulkState: const BulkWriteState(
          isWriting: true,
        ),
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('hides progress indicator when not writing', (tester) async {
      await tester.pumpWidget(createChipWidget(
        bulkState: const BulkWriteState(
          isWriting: false,
          tagsWritten: 3,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}

/// Test notifier that exposes a fixed state
class _TestBulkWriteNotifier extends BulkWriteNotifier {
  _TestBulkWriteNotifier(BulkWriteState initialState) : super(_FakeRef()) {
    state = initialState;
  }
}

/// Fake Ref for testing
class _FakeRef implements Ref {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
