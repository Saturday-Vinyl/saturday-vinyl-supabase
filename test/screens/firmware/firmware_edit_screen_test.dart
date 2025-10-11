import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/screens/firmware/firmware_edit_screen.dart';

void main() {
  group('FirmwareEditScreen', () {
    late FirmwareVersion testFirmware;

    setUp(() {
      testFirmware = FirmwareVersion(
        id: 'test-id-123',
        deviceTypeId: 'device-456',
        version: '1.2.3',
        releaseNotes: 'Original release notes',
        binaryUrl: 'https://example.com/firmware.bin',
        binaryFilename: 'esp32-firmware-v1.2.3.bin',
        binarySize: 1024000,
        isProductionReady: false,
        createdAt: DateTime(2025, 1, 15, 10, 30),
        createdBy: 'user-789',
      );
    });

    testWidgets('displays info card about unchangeable fields', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      expect(
        find.text(
          'Device type and binary file cannot be changed. Upload a new version to change these.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('pre-fills form with existing firmware data', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      // Check version field
      expect(find.text('1.2.3'), findsOneWidget);

      // Check release notes field
      expect(find.text('Original release notes'), findsOneWidget);

      // Check production ready checkbox (should be unchecked)
      final checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, isFalse);
    });

    testWidgets('displays version field with validation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Version *'), findsOneWidget);
      expect(find.text('e.g., 1.2.3'), findsOneWidget);
      expect(find.text('Semantic versioning (X.Y.Z)'), findsOneWidget);
    });

    testWidgets('displays release notes field', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Release Notes'), findsOneWidget);
      expect(find.text('What\'s new in this version?'), findsOneWidget);
    });

    testWidgets('displays production ready checkbox', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Mark as Production Ready'), findsOneWidget);
      expect(
        find.text(
          'Check this if the firmware is stable and ready for production deployment',
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays read-only fields section', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Read-Only Information'), findsOneWidget);
      expect(find.text('Device Type ID'), findsOneWidget);
      expect(find.text('device-456'), findsOneWidget);
      expect(find.text('Binary Filename'), findsOneWidget);
      expect(find.text('esp32-firmware-v1.2.3.bin'), findsOneWidget);
      expect(find.text('Upload Date'), findsOneWidget);
      expect(find.text('2025-01-15'), findsOneWidget);
    });

    testWidgets('displays save changes button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('allows toggling production ready checkbox', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      // Initially unchecked
      var checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, isFalse);

      // Tap to check
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      // Should be checked now
      checkbox = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(checkbox.value, isTrue);
    });

    testWidgets('version field accepts valid semantic versions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      // Find version text field
      final versionField = find.widgetWithText(TextFormField, '1.2.3');

      // Clear and enter new version
      await tester.enterText(versionField, '2.0.0');
      await tester.pump();

      expect(find.text('2.0.0'), findsOneWidget);
    });

    testWidgets('release notes field accepts multiline text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareEditScreen(firmware: testFirmware),
        ),
      );

      // Find release notes field
      final notesField =
          find.widgetWithText(TextFormField, 'Original release notes');

      // Enter multiline text
      await tester.enterText(
        notesField,
        'Line 1\nLine 2\nLine 3',
      );
      await tester.pump();

      expect(find.text('Line 1\nLine 2\nLine 3'), findsOneWidget);
    });
  });
}
