import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/widgets/tags/tag_list_item.dart';

void main() {
  late RfidTag testTag;
  late RfidTag tagWithTid;

  setUp(() {
    testTag = RfidTag(
      id: 'tag-1',
      epcIdentifier: '5356A1B2C3D4E5F67890ABCD',
      status: RfidTagStatus.active,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
    );

    tagWithTid = RfidTag(
      id: 'tag-2',
      epcIdentifier: '5356DEADBEEFCAFE12345678',
      tid: 'E2801234567890ABCDEF',
      status: RfidTagStatus.written,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      updatedAt: DateTime.now().subtract(const Duration(days: 3)),
      writtenAt: DateTime.now().subtract(const Duration(days: 3)),
    );
  });

  Widget createTestWidget({
    required RfidTag tag,
    VoidCallback? onTap,
    bool isHighlighted = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TagListItem(
          tag: tag,
          onTap: onTap,
          isHighlighted: isHighlighted,
        ),
      ),
    );
  }

  group('TagListItem', () {
    testWidgets('displays formatted EPC', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: testTag));
      await tester.pumpAndSettle();

      // EPC should be formatted with dashes
      expect(find.text('5356-A1B2-C3D4-E5F6-7890-ABCD'), findsOneWidget);
    });

    testWidgets('displays status badge', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: testTag));
      await tester.pumpAndSettle();

      // Should show the active status
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('displays time ago for recent dates', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: testTag));
      await tester.pumpAndSettle();

      // Should show "2h ago" for 2 hours old
      expect(find.text('2h ago'), findsOneWidget);
    });

    testWidgets('displays TID when available', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: tagWithTid));
      await tester.pumpAndSettle();

      // TID should be truncated and displayed
      expect(find.text('E2801234...'), findsOneWidget);
    });

    testWidgets('does not display TID when null', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: testTag));
      await tester.pumpAndSettle();

      // Fingerprint icon should not be present without TID
      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });

    testWidgets('displays label icon', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: testTag));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.label), findsOneWidget);
    });

    testWidgets('displays schedule icon for date', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: testTag));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    testWidgets('displays chevron right icon', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: testTag));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('is tappable with InkWell', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: testTag));
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(createTestWidget(
        tag: testTag,
        onTap: () => tapped = true,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('uses Card widget', (tester) async {
      await tester.pumpWidget(createTestWidget(tag: testTag));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
    });

    testWidgets('highlighted mode has elevated card', (tester) async {
      await tester.pumpWidget(createTestWidget(
        tag: testTag,
        isHighlighted: true,
      ));
      await tester.pumpAndSettle();

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.elevation, 4);
    });

    testWidgets('non-highlighted mode has lower elevation', (tester) async {
      await tester.pumpWidget(createTestWidget(
        tag: testTag,
        isHighlighted: false,
      ));
      await tester.pumpAndSettle();

      final card = tester.widget<Card>(find.byType(Card));
      expect(card.elevation, 1);
    });
  });

  group('TagListItem date formatting', () {
    testWidgets('displays "Just now" for very recent tags', (tester) async {
      final recentTag = testTag.copyWith(
        createdAt: DateTime.now().subtract(const Duration(seconds: 30)),
      );
      await tester.pumpWidget(createTestWidget(tag: recentTag));
      await tester.pumpAndSettle();

      expect(find.text('Just now'), findsOneWidget);
    });

    testWidgets('displays minutes ago for recent tags', (tester) async {
      final recentTag = testTag.copyWith(
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
      );
      await tester.pumpWidget(createTestWidget(tag: recentTag));
      await tester.pumpAndSettle();

      expect(find.text('15m ago'), findsOneWidget);
    });

    testWidgets('displays "Yesterday" for yesterday tags', (tester) async {
      final yesterdayTag = testTag.copyWith(
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      await tester.pumpWidget(createTestWidget(tag: yesterdayTag));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
    });

    testWidgets('displays days ago for recent week tags', (tester) async {
      final daysAgoTag = testTag.copyWith(
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      );
      await tester.pumpWidget(createTestWidget(tag: daysAgoTag));
      await tester.pumpAndSettle();

      expect(find.text('5d ago'), findsOneWidget);
    });
  });

  group('TagListItem with different statuses', () {
    testWidgets('displays generated status', (tester) async {
      final tag = testTag.copyWith(status: RfidTagStatus.generated);
      await tester.pumpWidget(createTestWidget(tag: tag));
      await tester.pumpAndSettle();

      expect(find.text('Generated'), findsOneWidget);
    });

    testWidgets('displays written status', (tester) async {
      final tag = testTag.copyWith(status: RfidTagStatus.written);
      await tester.pumpWidget(createTestWidget(tag: tag));
      await tester.pumpAndSettle();

      expect(find.text('Written'), findsOneWidget);
    });

    testWidgets('displays active status', (tester) async {
      final tag = testTag.copyWith(status: RfidTagStatus.active);
      await tester.pumpWidget(createTestWidget(tag: tag));
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('displays retired status', (tester) async {
      final tag = testTag.copyWith(status: RfidTagStatus.retired);
      await tester.pumpWidget(createTestWidget(tag: tag));
      await tester.pumpAndSettle();

      expect(find.text('Retired'), findsOneWidget);
    });
  });
}
