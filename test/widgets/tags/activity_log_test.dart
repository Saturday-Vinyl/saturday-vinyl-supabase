import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/activity_log_entry.dart';
import 'package:saturday_app/providers/activity_log_provider.dart';
import 'package:saturday_app/widgets/tags/activity_log.dart';

void main() {
  Widget createTestWidget({
    List<ActivityLogEntry>? entries,
    bool initiallyExpanded = true,
    ValueChanged<String>? onEpcTap,
  }) {
    return ProviderScope(
      overrides: [
        activityLogProvider.overrideWith((ref) {
          final notifier = ActivityLogNotifier();
          if (entries != null) {
            for (final entry in entries.reversed) {
              notifier.addEntry(entry.message, entry.level,
                  relatedEpc: entry.relatedEpc);
            }
          }
          return notifier;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ActivityLog(
            initiallyExpanded: initiallyExpanded,
            onEpcTap: onEpcTap,
          ),
        ),
      ),
    );
  }

  group('ActivityLog', () {
    testWidgets('displays header with Activity Log title', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Activity Log'), findsOneWidget);
    });

    testWidgets('displays entry count badge', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [
          ActivityLogEntry.info('Message 1'),
          ActivityLogEntry.info('Message 2'),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('displays zero count when empty', (tester) async {
      await tester.pumpWidget(createTestWidget(entries: []));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('shows "No activity yet" when empty and expanded',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [],
        initiallyExpanded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('No activity yet'), findsOneWidget);
    });

    testWidgets('displays entries when expanded', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [
          ActivityLogEntry.info('First message'),
          ActivityLogEntry.success('Second message'),
        ],
        initiallyExpanded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('First message'), findsOneWidget);
      expect(find.text('Second message'), findsOneWidget);
    });

    testWidgets('hides entries when collapsed', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [
          ActivityLogEntry.info('Hidden message'),
        ],
        initiallyExpanded: false,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Hidden message'), findsNothing);
    });

    testWidgets('can toggle expand/collapse', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [
          ActivityLogEntry.info('Toggle message'),
        ],
        initiallyExpanded: false,
      ));
      await tester.pumpAndSettle();

      // Initially collapsed - message not visible
      expect(find.text('Toggle message'), findsNothing);

      // Tap to expand
      await tester.tap(find.text('Activity Log'));
      await tester.pumpAndSettle();

      // Now visible
      expect(find.text('Toggle message'), findsOneWidget);

      // Tap to collapse
      await tester.tap(find.text('Activity Log'));
      await tester.pumpAndSettle();

      // Hidden again
      expect(find.text('Toggle message'), findsNothing);
    });

    testWidgets('displays Clear button when entries exist', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [
          ActivityLogEntry.info('Message'),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('hides Clear button when empty', (tester) async {
      await tester.pumpWidget(createTestWidget(entries: []));
      await tester.pumpAndSettle();

      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('Clear button clears entries', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [
          ActivityLogEntry.info('Message to clear'),
        ],
        initiallyExpanded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Message to clear'), findsOneWidget);

      // Tap Clear button
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Message to clear'), findsNothing);
      expect(find.text('No activity yet'), findsOneWidget);
    });

    testWidgets('displays info icon for info level', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [ActivityLogEntry.info('Info message')],
        initiallyExpanded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('displays check icon for success level', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [ActivityLogEntry.success('Success message')],
        initiallyExpanded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('displays warning icon for warning level', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [ActivityLogEntry.warning('Warning message')],
        initiallyExpanded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
    });

    testWidgets('displays error icon for error level', (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [ActivityLogEntry.error('Error message')],
        initiallyExpanded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('displays link icon for entries with relatedEpc',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [
          ActivityLogEntry.info('Tag found', relatedEpc: '5356ABCD'),
        ],
        initiallyExpanded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('does not display link icon without relatedEpc',
        (tester) async {
      await tester.pumpWidget(createTestWidget(
        entries: [
          ActivityLogEntry.info('No tag'),
        ],
        initiallyExpanded: true,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.link), findsNothing);
    });

    testWidgets('calls onEpcTap when entry with epc is tapped', (tester) async {
      String? tappedEpc;
      await tester.pumpWidget(createTestWidget(
        entries: [
          ActivityLogEntry.info('Tag found', relatedEpc: '5356TESTCODE'),
        ],
        initiallyExpanded: true,
        onEpcTap: (epc) => tappedEpc = epc,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tag found'));
      await tester.pumpAndSettle();

      expect(tappedEpc, '5356TESTCODE');
    });
  });

  group('ActivityLogIndicator', () {
    Widget createIndicatorWidget({List<ActivityLogEntry>? entries}) {
      return ProviderScope(
        overrides: [
          activityLogProvider.overrideWith((ref) {
            final notifier = ActivityLogNotifier();
            if (entries != null) {
              for (final entry in entries.reversed) {
                notifier.addEntry(entry.message, entry.level);
              }
            }
            return notifier;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ActivityLogIndicator(),
          ),
        ),
      );
    }

    testWidgets('displays count when entries exist', (tester) async {
      await tester.pumpWidget(createIndicatorWidget(
        entries: [
          ActivityLogEntry.info('1'),
          ActivityLogEntry.info('2'),
          ActivityLogEntry.info('3'),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('does not display count when empty', (tester) async {
      await tester.pumpWidget(createIndicatorWidget(entries: []));
      await tester.pumpAndSettle();

      // Should not find any number text
      expect(find.text('0'), findsNothing);
    });
  });
}
