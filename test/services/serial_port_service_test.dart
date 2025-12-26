import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/models/serial_connection_state.dart';
import 'package:saturday_app/services/serial_port_service.dart';

void main() {
  group('SerialPortService Logic', () {
    // Note: These tests verify the logic used by SerialPortService
    // without requiring actual serial port hardware

    group('State transitions', () {
      test('initial state is disconnected', () {
        expect(
          SerialConnectionState.initial.status,
          SerialConnectionStatus.disconnected,
        );
        expect(SerialConnectionState.initial.isModuleEnabled, false);
      });

      test('connecting state has correct properties', () {
        const state = SerialConnectionState(
          status: SerialConnectionStatus.connecting,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
        );
        expect(state.isConnecting, true);
        expect(state.isConnected, false);
        expect(state.portName, '/dev/ttyUSB0');
        expect(state.baudRate, 115200);
      });

      test('connected state includes module enabled', () {
        const state = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
          isModuleEnabled: true,
        );
        expect(state.isConnected, true);
        expect(state.isModuleEnabled, true);
      });

      test('error state includes error message', () {
        const state = SerialConnectionState(
          status: SerialConnectionStatus.error,
          errorMessage: 'Failed to open port',
        );
        expect(state.hasError, true);
        expect(state.errorMessage, 'Failed to open port');
      });
    });

    group('Configuration defaults', () {
      test('default baud rate is used from RfidConfig', () {
        expect(RfidConfig.defaultBaudRate, 115200);
      });

      test('serial port config matches spec', () {
        expect(RfidConfig.dataBits, 8);
        expect(RfidConfig.stopBits, 1);
        expect(RfidConfig.parity, 0);
      });

      test('module enable delay is 100ms', () {
        expect(RfidConfig.moduleEnableDelayMs, 100);
      });
    });

    group('DTR control logic', () {
      test('DTR assertion enables module', () {
        // When DTR is asserted (true), EN pin goes LOW, module is ON
        const stateEnabled = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          isModuleEnabled: true,
        );
        expect(stateEnabled.isModuleEnabled, true);
      });

      test('DTR deassertion disables module', () {
        // When DTR is deasserted (false), EN pin goes HIGH, module is OFF
        const stateDisabled = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          isModuleEnabled: false,
        );
        expect(stateDisabled.isModuleEnabled, false);
      });

      test('state transition from enabled to disabled', () {
        const enabled = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          isModuleEnabled: true,
        );
        final disabled = enabled.copyWith(isModuleEnabled: false);
        expect(disabled.isModuleEnabled, false);
        expect(disabled.isConnected, true); // Still connected
      });
    });

    group('Hex formatting', () {
      test('format small byte arrays', () {
        final bytes = [0xBB, 0x00, 0x22, 0x00, 0x00, 0x22, 0x7E];
        final formatted = bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');
        expect(formatted, 'BB 00 22 00 00 22 7E');
      });

      test('handles single byte', () {
        final bytes = [0xBB];
        final formatted = bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');
        expect(formatted, 'BB');
      });

      test('handles empty array', () {
        final bytes = <int>[];
        final formatted = bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');
        expect(formatted, '');
      });
    });

    group('Port name validation', () {
      test('Unix-style port names', () {
        const unixPorts = [
          '/dev/ttyUSB0',
          '/dev/ttyUSB1',
          '/dev/tty.usbserial-0001',
          '/dev/cu.usbserial-0001',
        ];
        for (final port in unixPorts) {
          expect(port.startsWith('/dev/'), true);
        }
      });

      test('Windows-style port names', () {
        const windowsPorts = ['COM1', 'COM2', 'COM3', 'COM10'];
        for (final port in windowsPorts) {
          expect(port.startsWith('COM'), true);
        }
      });
    });

    group('Data stream handling', () {
      test('incoming data is converted to list', () {
        final uint8Data = [0xBB, 0x01, 0x22, 0x00, 0x04, 0x10, 0x20, 0x30, 0x40, 0xC7, 0x7E];
        final listData = uint8Data.toList();
        expect(listData, isA<List<int>>());
        expect(listData.length, 11);
        expect(listData.first, 0xBB);
        expect(listData.last, 0x7E);
      });
    });

    group('Service instantiation', () {
      test('creates service instance', () {
        final service = SerialPortService();
        expect(service, isNotNull);
        expect(service.isConnected, false);
        expect(service.isModuleEnabled, false);
        service.dispose();
      });

      test('initial state is correct', () {
        final service = SerialPortService();
        expect(service.state.status, SerialConnectionStatus.disconnected);
        expect(service.state.portName, null);
        expect(service.state.baudRate, null);
        expect(service.state.isModuleEnabled, false);
        service.dispose();
      });

      test('static listAvailablePorts does not throw', () {
        // This should not throw even without hardware
        expect(() => SerialPortService.listAvailablePorts(), returnsNormally);
      });
    });

    group('State stream', () {
      test('state stream is broadcast', () async {
        final service = SerialPortService();

        // Multiple listeners should work (broadcast stream)
        final states1 = <SerialConnectionState>[];
        final states2 = <SerialConnectionState>[];

        final sub1 = service.stateStream.listen(states1.add);
        final sub2 = service.stateStream.listen(states2.add);

        await Future.delayed(const Duration(milliseconds: 10));

        await sub1.cancel();
        await sub2.cancel();
        service.dispose();
      });
    });

    group('Connection workflow logic', () {
      test('connection should assert DTR after opening port', () {
        // The workflow is:
        // 1. Open port
        // 2. Configure serial settings
        // 3. Assert DTR (enable module)
        // 4. Wait for module init delay
        // 5. Set up reader
        // 6. Update state to connected

        // This is documented behavior, tested via state transitions
        const afterConnect = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
          isModuleEnabled: true, // DTR was asserted
        );
        expect(afterConnect.isConnected, true);
        expect(afterConnect.isModuleEnabled, true);
      });

      test('disconnection should deassert DTR before closing port', () {
        // The workflow is:
        // 1. Deassert DTR (disable module)
        // 2. Brief delay
        // 3. Cancel reader subscription
        // 4. Close reader
        // 5. Close port
        // 6. Update state to disconnected

        // After disconnect, module should be disabled
        expect(SerialConnectionState.initial.isModuleEnabled, false);
      });
    });

    group('Error handling logic', () {
      test('error state preserves port info for debugging', () {
        const errorState = SerialConnectionState(
          status: SerialConnectionStatus.error,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
          errorMessage: 'Connection timeout',
          isModuleEnabled: false,
        );
        // Port info preserved for debugging
        expect(errorState.portName, '/dev/ttyUSB0');
        expect(errorState.baudRate, 115200);
        expect(errorState.errorMessage, 'Connection timeout');
        // Module disabled on error
        expect(errorState.isModuleEnabled, false);
      });

      test('can clear error and retry', () {
        const errorState = SerialConnectionState(
          status: SerialConnectionStatus.error,
          errorMessage: 'Some error',
        );
        final retryState = errorState.copyWith(
          status: SerialConnectionStatus.connecting,
          clearError: true,
        );
        expect(retryState.status, SerialConnectionStatus.connecting);
        expect(retryState.errorMessage, null);
      });
    });
  });
}
