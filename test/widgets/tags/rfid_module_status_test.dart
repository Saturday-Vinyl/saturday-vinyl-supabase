import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/serial_connection_state.dart';
import 'package:saturday_app/providers/uhf_rfid_provider.dart';
import 'package:saturday_app/widgets/tags/rfid_module_status.dart';

void main() {
  Widget createTestWidget({
    required SerialConnectionState connectionState,
    bool showLabel = true,
    bool compact = false,
  }) {
    return ProviderScope(
      overrides: [
        uhfCurrentConnectionStateProvider.overrideWith((ref) {
          return connectionState;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: RfidModuleStatus(
            showLabel: showLabel,
            compact: compact,
          ),
        ),
      ),
    );
  }

  Widget createAppBarTestWidget({
    required SerialConnectionState connectionState,
  }) {
    return ProviderScope(
      overrides: [
        uhfCurrentConnectionStateProvider.overrideWith((ref) {
          return connectionState;
        }),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: RfidAppBarStatus(),
        ),
      ),
    );
  }

  group('RfidModuleStatus', () {
    testWidgets('displays disconnected state', (tester) async {
      await tester.pumpWidget(createTestWidget(
        connectionState: SerialConnectionState.initial,
      ));
      await tester.pumpAndSettle();

      expect(find.text('RFID: Off'), findsOneWidget);
    });

    testWidgets('displays connected state', (tester) async {
      await tester.pumpWidget(createTestWidget(
        connectionState: const SerialConnectionState(
          status: SerialConnectionStatus.connected,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
          isModuleEnabled: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('RFID: Ready'), findsOneWidget);
    });

    testWidgets('displays connecting state', (tester) async {
      await tester.pumpWidget(createTestWidget(
        connectionState: const SerialConnectionState(
          status: SerialConnectionStatus.connecting,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
        ),
      ));
      // Don't settle - connecting state has a circular progress indicator
      await tester.pump();

      expect(find.text('RFID: Connecting'), findsOneWidget);
    });

    testWidgets('displays error state', (tester) async {
      await tester.pumpWidget(createTestWidget(
        connectionState: const SerialConnectionState(
          status: SerialConnectionStatus.error,
          errorMessage: 'Connection failed',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('RFID: Error'), findsOneWidget);
    });

    testWidgets('hides label when showLabel is false', (tester) async {
      await tester.pumpWidget(createTestWidget(
        connectionState: SerialConnectionState.initial,
        showLabel: false,
      ));
      await tester.pumpAndSettle();

      // Should not find the text label
      expect(find.text('RFID: Off'), findsNothing);
    });

    testWidgets('shows compact mode', (tester) async {
      await tester.pumpWidget(createTestWidget(
        connectionState: SerialConnectionState.initial,
        compact: true,
      ));
      await tester.pumpAndSettle();

      // Should not find the text label in compact mode
      expect(find.text('RFID: Off'), findsNothing);
    });

    testWidgets('displays settings icon', (tester) async {
      await tester.pumpWidget(createTestWidget(
        connectionState: SerialConnectionState.initial,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('has tooltip', (tester) async {
      await tester.pumpWidget(createTestWidget(
        connectionState: SerialConnectionState.initial,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('is clickable with InkWell', (tester) async {
      await tester.pumpWidget(createTestWidget(
        connectionState: SerialConnectionState.initial,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(InkWell), findsOneWidget);
    });
  });

  group('RfidAppBarStatus', () {
    testWidgets('displays antenna icon', (tester) async {
      await tester.pumpWidget(createAppBarTestWidget(
        connectionState: SerialConnectionState.initial,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings_input_antenna), findsOneWidget);
    });

    testWidgets('displays status dot overlay', (tester) async {
      await tester.pumpWidget(createAppBarTestWidget(
        connectionState: SerialConnectionState.initial,
      ));
      await tester.pumpAndSettle();

      // Should have at least one Stack (there may be others in the widget tree)
      expect(find.byType(Stack), findsWidgets);
    });

    testWidgets('is an IconButton', (tester) async {
      await tester.pumpWidget(createAppBarTestWidget(
        connectionState: SerialConnectionState.initial,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('shows connected tooltip', (tester) async {
      await tester.pumpWidget(createAppBarTestWidget(
        connectionState: const SerialConnectionState(
          status: SerialConnectionStatus.connected,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
          isModuleEnabled: true,
        ),
      ));
      await tester.pumpAndSettle();

      final iconButton = find.byType(IconButton);
      final IconButton widget = tester.widget(iconButton);
      expect(widget.tooltip, 'RFID Module: Connected');
    });

    testWidgets('shows disconnected tooltip', (tester) async {
      await tester.pumpWidget(createAppBarTestWidget(
        connectionState: SerialConnectionState.initial,
      ));
      await tester.pumpAndSettle();

      final iconButton = find.byType(IconButton);
      final IconButton widget = tester.widget(iconButton);
      expect(widget.tooltip, 'RFID Module: Disconnected');
    });

    testWidgets('shows error tooltip', (tester) async {
      await tester.pumpWidget(createAppBarTestWidget(
        connectionState: const SerialConnectionState(
          status: SerialConnectionStatus.error,
          errorMessage: 'Connection failed',
        ),
      ));
      await tester.pumpAndSettle();

      final iconButton = find.byType(IconButton);
      final IconButton widget = tester.widget(iconButton);
      expect(widget.tooltip, 'RFID Module: Error');
    });

    testWidgets('shows connecting tooltip', (tester) async {
      await tester.pumpWidget(createAppBarTestWidget(
        connectionState: const SerialConnectionState(
          status: SerialConnectionStatus.connecting,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
        ),
      ));
      await tester.pumpAndSettle();

      final iconButton = find.byType(IconButton);
      final IconButton widget = tester.widget(iconButton);
      expect(widget.tooltip, 'RFID Module: Connecting...');
    });
  });
}
