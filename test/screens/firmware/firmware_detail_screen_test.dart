import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/screens/firmware/firmware_detail_screen.dart';

void main() {
  group('FirmwareDetailScreen', () {
    late FirmwareVersion testFirmware;

    setUp(() {
      testFirmware = FirmwareVersion(
        id: 'test-id-123',
        deviceTypeId: 'device-456',
        version: '1.2.3',
        releaseNotes: 'Bug fixes and improvements',
        binaryUrl: 'https://example.com/firmware.bin',
        binaryFilename: 'esp32-firmware-v1.2.3.bin',
        binarySize: 1024000,
        isProductionReady: true,
        createdAt: DateTime(2025, 1, 15, 10, 30),
        createdBy: 'user-789',
      );
    });

    testWidgets('displays firmware version prominently', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareDetailScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('v1.2.3'), findsOneWidget);
    });

    testWidgets('displays production ready status', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareDetailScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Production Ready'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('displays testing status for non-production firmware',
        (tester) async {
      final testingFirmware = testFirmware.copyWith(isProductionReady: false);

      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareDetailScreen(firmware: testingFirmware),
        ),
      );

      expect(find.text('Testing'), findsOneWidget);
      expect(find.byIcon(Icons.build_circle), findsOneWidget);
    });

    testWidgets('displays release notes when present', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareDetailScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Release Notes'), findsOneWidget);
      expect(find.text('Bug fixes and improvements'), findsOneWidget);
    });

    testWidgets('displays binary file information', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareDetailScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Binary File'), findsOneWidget);
      expect(find.text('esp32-firmware-v1.2.3.bin'), findsOneWidget);
      expect(find.text('1.00 MB'), findsOneWidget); // Formatted file size
    });

    testWidgets('displays download binary button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareDetailScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Download Binary'), findsOneWidget);
      expect(find.byIcon(Icons.download), findsOneWidget);
    });

    testWidgets('displays upload information', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareDetailScreen(firmware: testFirmware),
        ),
      );

      expect(find.text('Upload Information'), findsOneWidget);
      expect(find.text('2025-01-15 10:30'), findsOneWidget);
    });

    testWidgets('hides release notes section when not present',
        (tester) async {
      final firmwareWithoutNotes =
          testFirmware.copyWith(releaseNotes: null);

      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareDetailScreen(firmware: firmwareWithoutNotes),
        ),
      );

      expect(find.text('Release Notes'), findsNothing);
    });
  });
}
