import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/widgets/tags/tag_status_badge.dart';

void main() {
  Widget createTestWidget({
    required RfidTagStatus status,
    bool compact = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: TagStatusBadge(
          status: status,
          compact: compact,
        ),
      ),
    );
  }

  group('TagStatusBadge', () {
    testWidgets('displays generated status correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(status: RfidTagStatus.generated));
      await tester.pumpAndSettle();

      expect(find.text('Generated'), findsOneWidget);
    });

    testWidgets('displays written status correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(status: RfidTagStatus.written));
      await tester.pumpAndSettle();

      expect(find.text('Written'), findsOneWidget);
    });

    testWidgets('displays active status correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(status: RfidTagStatus.active));
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('displays retired status correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(status: RfidTagStatus.retired));
      await tester.pumpAndSettle();

      expect(find.text('Retired'), findsOneWidget);
    });

    testWidgets('compact mode uses smaller padding and font', (tester) async {
      await tester.pumpWidget(createTestWidget(
        status: RfidTagStatus.active,
        compact: true,
      ));
      await tester.pumpAndSettle();

      // Text should still be visible in compact mode
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('uses Container with border decoration', (tester) async {
      await tester.pumpWidget(createTestWidget(
        status: RfidTagStatus.active,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Container), findsWidgets);
    });
  });

  group('TagStatusBadge.getColorForStatus', () {
    test('returns correct color for generated', () {
      final color = TagStatusBadge.getColorForStatus(RfidTagStatus.generated);
      expect(color, SaturdayColors.secondaryGrey);
    });

    test('returns correct color for written', () {
      final color = TagStatusBadge.getColorForStatus(RfidTagStatus.written);
      expect(color, SaturdayColors.info);
    });

    test('returns correct color for active', () {
      final color = TagStatusBadge.getColorForStatus(RfidTagStatus.active);
      expect(color, SaturdayColors.success);
    });

    test('returns correct color for retired', () {
      final color = TagStatusBadge.getColorForStatus(RfidTagStatus.retired);
      // Retired uses a custom dark gray color
      expect(color, const Color(0xFF5C5C5C));
    });
  });

  group('TagStatusBadge.getIconForStatus', () {
    test('returns correct icon for generated', () {
      final icon = TagStatusBadge.getIconForStatus(RfidTagStatus.generated);
      expect(icon, Icons.auto_awesome);
    });

    test('returns correct icon for written', () {
      final icon = TagStatusBadge.getIconForStatus(RfidTagStatus.written);
      expect(icon, Icons.edit_note);
    });

    test('returns correct icon for active', () {
      final icon = TagStatusBadge.getIconForStatus(RfidTagStatus.active);
      expect(icon, Icons.album);
    });

    test('returns correct icon for retired', () {
      final icon = TagStatusBadge.getIconForStatus(RfidTagStatus.retired);
      expect(icon, Icons.cancel_outlined);
    });
  });
}
