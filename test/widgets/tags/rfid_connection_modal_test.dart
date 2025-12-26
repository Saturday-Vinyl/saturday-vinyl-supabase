import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/models/rfid_settings.dart';
import 'package:saturday_app/models/serial_connection_state.dart';
import 'package:saturday_app/providers/rfid_settings_provider.dart';
import 'package:saturday_app/providers/uhf_rfid_provider.dart';
import 'package:saturday_app/services/serial_port_service.dart';
import 'package:saturday_app/services/uhf_rfid_service.dart';
import 'package:saturday_app/widgets/tags/rfid_connection_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rfid_connection_modal_test.mocks.dart';

@GenerateMocks([SerialPortService, UhfRfidService])
void main() {
  late MockSerialPortService mockSerialPortService;
  late MockUhfRfidService mockUhfRfidService;

  setUp(() {
    mockSerialPortService = MockSerialPortService();
    mockUhfRfidService = MockUhfRfidService();

    // Default mock behavior
    when(mockSerialPortService.getAvailablePorts())
        .thenReturn(['/dev/ttyUSB0', '/dev/ttyUSB1']);
    when(mockUhfRfidService.connectionState)
        .thenReturn(SerialConnectionState.initial);
    when(mockUhfRfidService.isConnected).thenReturn(false);
  });

  Widget createTestWidget({
    RfidSettings? initialSettings,
  }) {
    return ProviderScope(
      overrides: [
        serialPortServiceProvider.overrideWithValue(mockSerialPortService),
        uhfRfidServiceProvider.overrideWithValue(mockUhfRfidService),
        uhfCurrentConnectionStateProvider.overrideWith((ref) {
          return SerialConnectionState.initial;
        }),
        refreshablePortsProvider.overrideWith((ref) async {
          return mockSerialPortService.getAvailablePorts();
        }),
        rfidSettingsProvider.overrideWith((ref) {
          return _MockRfidSettingsNotifier(initialSettings ?? RfidSettings.defaults());
        }),
        currentRfidSettingsProvider.overrideWith((ref) {
          return initialSettings ?? RfidSettings.defaults();
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: RfidConnectionModal(),
        ),
      ),
    );
  }

  group('RfidConnectionModal', () {
    testWidgets('displays header with RFID Module Settings title',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('RFID Module Settings'), findsOneWidget);
    });

    testWidgets('displays port dropdown with available ports', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find the port dropdown
      expect(find.text('Serial Port'), findsOneWidget);

      // Open the dropdown
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();

      // Check that ports are listed
      expect(find.text('/dev/ttyUSB0'), findsWidgets);
      expect(find.text('/dev/ttyUSB1'), findsOneWidget);
    });

    testWidgets('displays baud rate dropdown with options', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Baud Rate'), findsOneWidget);

      // Find baud rate dropdown and tap it
      final baudRateDropdown =
          find.byType(DropdownButtonFormField<int>).first;
      await tester.tap(baudRateDropdown);
      await tester.pumpAndSettle();

      // Check that baud rates are listed
      expect(find.text('115200 bps (default)'), findsWidgets);
    });

    testWidgets('displays RF power slider', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('RF Power'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('${RfidConfig.defaultRfPower} dBm'), findsOneWidget);
    });

    testWidgets('displays access password field', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Access Password (optional)'), findsOneWidget);
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('validates password - rejects too short', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find password field and enter short password
      final passwordField = find.byType(TextFormField);
      await tester.enterText(passwordField, '1234');
      await tester.pumpAndSettle();

      expect(find.text('Must be exactly 8 hex characters'), findsOneWidget);
    });

    testWidgets('validates password - accepts valid hex', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Find password field and enter valid password
      final passwordField = find.byType(TextFormField);
      await tester.enterText(passwordField, 'AABBCCDD');
      await tester.pumpAndSettle();

      // Should not show error
      expect(find.text('Must be exactly 8 hex characters'), findsNothing);
      expect(find.text('Invalid hex characters'), findsNothing);
    });

    testWidgets('displays test connection button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Test Connection'), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);
    });

    testWidgets('displays Save & Connect button when disconnected',
        (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Save & Connect'), findsOneWidget);
    });

    testWidgets('displays Cancel button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('displays Scan Ports button', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Scan Ports'), findsOneWidget);
    });

    testWidgets('displays no ports message when empty', (tester) async {
      when(mockSerialPortService.getAvailablePorts()).thenReturn([]);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No serial ports found'),
        findsOneWidget,
      );
    });

    testWidgets('loads saved settings', (tester) async {
      final savedSettings = RfidSettings(
        port: '/dev/ttyUSB0',
        baudRate: 57600,
        rfPower: 25,
      );

      await tester.pumpWidget(createTestWidget(initialSettings: savedSettings));
      await tester.pumpAndSettle();

      // RF power should show saved value
      expect(find.text('25 dBm'), findsOneWidget);
    });

    testWidgets('displays status chip showing disconnected', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Disconnected'), findsOneWidget);
    });

    testWidgets('displays RF power helper text', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Lower power = shorter range'),
        findsOneWidget,
      );
    });

    testWidgets('displays close button in header', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });
}

/// Mock RfidSettingsNotifier for testing
class _MockRfidSettingsNotifier extends StateNotifier<RfidSettingsState>
    implements RfidSettingsNotifier {
  _MockRfidSettingsNotifier(RfidSettings settings)
      : super(RfidSettingsState(settings: settings, isLoading: false));

  @override
  Future<void> clearAllSettings() async {}

  @override
  Future<void> reload() async {}

  @override
  Future<void> updateAccessPassword(String? passwordHex) async {}

  @override
  Future<void> updateBaudRate(int baudRate) async {}

  @override
  Future<void> updatePort(String? port) async {}

  @override
  Future<void> updateRfPower(int dbm) async {}
}
