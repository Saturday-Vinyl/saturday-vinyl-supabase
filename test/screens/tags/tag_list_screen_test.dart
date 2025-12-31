import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/serial_connection_state.dart';
import 'package:saturday_app/models/tag_filter.dart';
import 'package:saturday_app/providers/rfid_tag_provider.dart';
import 'package:saturday_app/providers/uhf_rfid_provider.dart';
import 'package:saturday_app/screens/tags/tag_list_screen.dart';

void main() {
  // Test data
  final testTags = [
    RfidTag(
      id: 'tag-1',
      epcIdentifier: '5356A1B2C3D4E5F67890ABCD',
      status: RfidTagStatus.active,
      createdAt: DateTime(2025, 1, 15, 10, 30),
      updatedAt: DateTime(2025, 1, 15, 10, 30),
    ),
    RfidTag(
      id: 'tag-2',
      epcIdentifier: '535600112233445566778899',
      status: RfidTagStatus.generated,
      createdAt: DateTime(2025, 1, 14, 9, 0),
      updatedAt: DateTime(2025, 1, 14, 9, 0),
    ),
    RfidTag(
      id: 'tag-3',
      epcIdentifier: '5356DEADBEEFCAFE12345678',
      tid: 'E2801234567890ABCDEF',
      status: RfidTagStatus.written,
      createdAt: DateTime(2025, 1, 13, 8, 0),
      updatedAt: DateTime(2025, 1, 13, 8, 5),
      writtenAt: DateTime(2025, 1, 13, 8, 5),
    ),
  ];

  Widget createTestWidget({
    List<RfidTag>? tags,
    bool isLoading = false,
    Object? error,
    TagFilter? filter,
  }) {
    return ProviderScope(
      overrides: [
        // Override the filtered tags provider
        filteredRfidTagsProvider.overrideWith((ref) async {
          if (error != null) {
            throw error;
          }
          if (isLoading) {
            // Return a future that never completes to simulate loading
            return await Future.delayed(
              const Duration(seconds: 10),
              () => tags ?? [],
            );
          }
          return tags ?? [];
        }),
        // Override the filter provider
        tagFilterProvider.overrideWith((ref) => TagFilterNotifier()),
        // Override RFID connection state
        uhfCurrentConnectionStateProvider.overrideWith((ref) {
          return SerialConnectionState.initial;
        }),
      ],
      child: const MaterialApp(
        home: TagListScreen(),
      ),
    );
  }

  group('TagListScreen', () {
    testWidgets('displays loading state', (tester) async {
      await tester.pumpWidget(createTestWidget(isLoading: true));
      // Just pump once to see loading state before the future completes
      await tester.pump();

      // Should show loading indicator initially
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Complete the test by allowing timers to finish
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('displays empty state when no tags', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: []));
      await tester.pumpAndSettle();

      // Should show empty state message (message contains newlines)
      expect(find.textContaining('No tags yet'), findsOneWidget);
    });

    testWidgets('displays error state with retry button', (tester) async {
      await tester.pumpWidget(createTestWidget(
        error: Exception('Network error'),
      ));
      await tester.pumpAndSettle();

      // Should show error message
      expect(find.text('Failed to load tags'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('displays tag list correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // Should show formatted EPCs
      expect(find.textContaining('5356-A1B2'), findsOneWidget);
      expect(find.textContaining('5356-0011'), findsOneWidget);
      expect(find.textContaining('5356-DEAD'), findsOneWidget);
    });

    testWidgets('displays app bar with title', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      expect(find.text('Tags'), findsOneWidget);
    });

    testWidgets('displays search field', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search by EPC...'), findsOneWidget);
    });

    testWidgets('displays status filter dropdown', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // Find the status dropdown
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('All Statuses'), findsOneWidget);
    });

    testWidgets('displays sort dropdown', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      expect(find.text('Sort By'), findsOneWidget);
      expect(find.text('Newest First'), findsOneWidget);
    });

    testWidgets('displays scan button', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      expect(find.text('Scan'), findsOneWidget);
      expect(find.byIcon(Icons.sensors), findsOneWidget);
    });

    testWidgets('displays add button', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      expect(find.text('Add'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('shows snackbar when add is tapped', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // Tap the Add button
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Should show coming soon message
      expect(
        find.text('Add tag functionality coming soon'),
        findsOneWidget,
      );
    });

    testWidgets('shows snackbar when scan is tapped', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // Tap the Scan button
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();

      // Should show coming soon message
      expect(
        find.text('Scan functionality coming soon'),
        findsOneWidget,
      );
    });

    testWidgets('can enter text in search field', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // Find and tap the search field
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'DEAD');
      await tester.pump();

      // The text should be entered
      expect(find.text('DEAD'), findsOneWidget);
    });

    testWidgets('displays clear button when search has text', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // Enter text in search
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'test');
      await tester.pump();

      // Clear button should appear
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('displays RFID status in app bar', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // The RfidAppBarStatus should be visible
      expect(find.byIcon(Icons.settings_input_antenna), findsOneWidget);
    });

    testWidgets('shows correct tag count in list', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // Should have 3 tag items in the list
      // Each tag renders a Card via TagListItem
      expect(find.byType(Card), findsNWidgets(3));
    });
  });

  group('TagListScreen status filter', () {
    testWidgets('can open status dropdown', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // Tap on the status dropdown
      await tester.tap(find.text('All Statuses'));
      await tester.pumpAndSettle();

      // Should show status options (may appear twice due to dropdown overlay)
      expect(find.text('Generated'), findsAtLeast(1));
      expect(find.text('Written'), findsAtLeast(1));
      expect(find.text('Active'), findsAtLeast(1));
      expect(find.text('Retired'), findsAtLeast(1));
    });
  });

  group('TagListScreen sort filter', () {
    testWidgets('can open sort dropdown', (tester) async {
      await tester.pumpWidget(createTestWidget(tags: testTags));
      await tester.pumpAndSettle();

      // Tap on the sort dropdown
      await tester.tap(find.text('Newest First'));
      await tester.pumpAndSettle();

      // Should show sort options (may appear twice due to dropdown overlay)
      expect(find.text('Oldest First'), findsAtLeast(1));
      expect(find.text('EPC A-Z'), findsAtLeast(1));
      expect(find.text('EPC Z-A'), findsAtLeast(1));
      expect(find.text('Status'), findsAtLeast(1));
    });
  });
}
