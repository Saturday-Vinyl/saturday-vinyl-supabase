import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/serial_connection_state.dart';

void main() {
  group('SerialConnectionStatus', () {
    test('has expected values', () {
      expect(SerialConnectionStatus.values.length, 4);
      expect(SerialConnectionStatus.values, contains(SerialConnectionStatus.disconnected));
      expect(SerialConnectionStatus.values, contains(SerialConnectionStatus.connecting));
      expect(SerialConnectionStatus.values, contains(SerialConnectionStatus.connected));
      expect(SerialConnectionStatus.values, contains(SerialConnectionStatus.error));
    });
  });

  group('SerialConnectionState', () {
    test('creates with required status', () {
      const state = SerialConnectionState(
        status: SerialConnectionStatus.disconnected,
      );
      expect(state.status, SerialConnectionStatus.disconnected);
      expect(state.portName, null);
      expect(state.baudRate, null);
      expect(state.errorMessage, null);
      expect(state.isModuleEnabled, false);
    });

    test('creates with all fields', () {
      const state = SerialConnectionState(
        status: SerialConnectionStatus.connected,
        portName: '/dev/ttyUSB0',
        baudRate: 115200,
        errorMessage: null,
        isModuleEnabled: true,
      );
      expect(state.status, SerialConnectionStatus.connected);
      expect(state.portName, '/dev/ttyUSB0');
      expect(state.baudRate, 115200);
      expect(state.isModuleEnabled, true);
    });

    group('initial', () {
      test('is disconnected with defaults', () {
        expect(SerialConnectionState.initial.status, SerialConnectionStatus.disconnected);
        expect(SerialConnectionState.initial.portName, null);
        expect(SerialConnectionState.initial.baudRate, null);
        expect(SerialConnectionState.initial.errorMessage, null);
        expect(SerialConnectionState.initial.isModuleEnabled, false);
      });
    });

    group('convenience getters', () {
      test('isConnected returns true when connected', () {
        const state = SerialConnectionState(
          status: SerialConnectionStatus.connected,
        );
        expect(state.isConnected, true);
        expect(state.isConnecting, false);
        expect(state.hasError, false);
        expect(state.isDisconnected, false);
      });

      test('isConnecting returns true when connecting', () {
        const state = SerialConnectionState(
          status: SerialConnectionStatus.connecting,
        );
        expect(state.isConnected, false);
        expect(state.isConnecting, true);
        expect(state.hasError, false);
        expect(state.isDisconnected, false);
      });

      test('hasError returns true when error', () {
        const state = SerialConnectionState(
          status: SerialConnectionStatus.error,
          errorMessage: 'Connection failed',
        );
        expect(state.isConnected, false);
        expect(state.isConnecting, false);
        expect(state.hasError, true);
        expect(state.isDisconnected, false);
      });

      test('isDisconnected returns true when disconnected', () {
        const state = SerialConnectionState(
          status: SerialConnectionStatus.disconnected,
        );
        expect(state.isConnected, false);
        expect(state.isConnecting, false);
        expect(state.hasError, false);
        expect(state.isDisconnected, true);
      });
    });

    group('copyWith', () {
      const original = SerialConnectionState(
        status: SerialConnectionStatus.connected,
        portName: '/dev/ttyUSB0',
        baudRate: 115200,
        errorMessage: null,
        isModuleEnabled: true,
      );

      test('copies with updated status', () {
        final updated = original.copyWith(status: SerialConnectionStatus.error);
        expect(updated.status, SerialConnectionStatus.error);
        expect(updated.portName, '/dev/ttyUSB0');
        expect(updated.baudRate, 115200);
        expect(updated.isModuleEnabled, true);
      });

      test('copies with updated portName', () {
        final updated = original.copyWith(portName: 'COM3');
        expect(updated.portName, 'COM3');
        expect(updated.status, SerialConnectionStatus.connected);
      });

      test('copies with updated baudRate', () {
        final updated = original.copyWith(baudRate: 9600);
        expect(updated.baudRate, 9600);
      });

      test('copies with updated errorMessage', () {
        final updated = original.copyWith(errorMessage: 'Test error');
        expect(updated.errorMessage, 'Test error');
      });

      test('copies with updated isModuleEnabled', () {
        final updated = original.copyWith(isModuleEnabled: false);
        expect(updated.isModuleEnabled, false);
      });

      test('clearError removes error message', () {
        const withError = SerialConnectionState(
          status: SerialConnectionStatus.error,
          errorMessage: 'Some error',
        );
        final cleared = withError.copyWith(clearError: true);
        expect(cleared.errorMessage, null);
      });

      test('clearPort removes port and baudRate', () {
        final cleared = original.copyWith(clearPort: true);
        expect(cleared.portName, null);
        expect(cleared.baudRate, null);
      });

      test('preserves all values when no args', () {
        final updated = original.copyWith();
        expect(updated, equals(original));
      });
    });

    group('equality', () {
      test('equal states are equal', () {
        const state1 = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
          isModuleEnabled: true,
        );
        const state2 = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
          isModuleEnabled: true,
        );
        expect(state1, equals(state2));
        expect(state1.hashCode, equals(state2.hashCode));
      });

      test('different status makes states unequal', () {
        const state1 = SerialConnectionState(
          status: SerialConnectionStatus.connected,
        );
        const state2 = SerialConnectionState(
          status: SerialConnectionStatus.disconnected,
        );
        expect(state1, isNot(equals(state2)));
      });

      test('different portName makes states unequal', () {
        const state1 = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          portName: 'COM1',
        );
        const state2 = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          portName: 'COM2',
        );
        expect(state1, isNot(equals(state2)));
      });

      test('different isModuleEnabled makes states unequal', () {
        const state1 = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          isModuleEnabled: true,
        );
        const state2 = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          isModuleEnabled: false,
        );
        expect(state1, isNot(equals(state2)));
      });
    });

    group('toString', () {
      test('includes key information', () {
        const state = SerialConnectionState(
          status: SerialConnectionStatus.connected,
          portName: '/dev/ttyUSB0',
          baudRate: 115200,
          isModuleEnabled: true,
        );
        final str = state.toString();
        expect(str, contains('connected'));
        expect(str, contains('/dev/ttyUSB0'));
        expect(str, contains('115200'));
        expect(str, contains('moduleEnabled: true'));
      });

      test('includes error message when present', () {
        const state = SerialConnectionState(
          status: SerialConnectionStatus.error,
          errorMessage: 'Connection failed',
        );
        final str = state.toString();
        expect(str, contains('error'));
        expect(str, contains('Connection failed'));
      });
    });
  });
}
