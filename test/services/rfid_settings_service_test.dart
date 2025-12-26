import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/models/rfid_settings.dart';
import 'package:saturday_app/services/rfid_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rfid_settings_service_test.mocks.dart';

@GenerateMocks([FlutterSecureStorage])
void main() {
  late RfidSettingsService service;
  late MockFlutterSecureStorage mockSecureStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    mockSecureStorage = MockFlutterSecureStorage();
    service = RfidSettingsService(prefs, mockSecureStorage);
  });

  group('RfidSettingsService', () {
    group('Port Settings', () {
      test('saves and retrieves port', () async {
        await service.savePort('/dev/ttyUSB0');
        expect(service.getPort(), '/dev/ttyUSB0');
      });

      test('returns null when no port saved', () {
        expect(service.getPort(), isNull);
      });

      test('clears port', () async {
        await service.savePort('/dev/ttyUSB0');
        await service.clearPort();
        expect(service.getPort(), isNull);
      });

      test('overwrites existing port', () async {
        await service.savePort('/dev/ttyUSB0');
        await service.savePort('/dev/ttyUSB1');
        expect(service.getPort(), '/dev/ttyUSB1');
      });
    });

    group('Baud Rate Settings', () {
      test('saves and retrieves baud rate', () async {
        await service.saveBaudRate(9600);
        expect(service.getBaudRate(), 9600);
      });

      test('returns default baud rate when not saved', () {
        expect(service.getBaudRate(), RfidConfig.defaultBaudRate);
      });

      test('overwrites existing baud rate', () async {
        await service.saveBaudRate(9600);
        await service.saveBaudRate(57600);
        expect(service.getBaudRate(), 57600);
      });
    });

    group('RF Power Settings', () {
      test('saves and retrieves RF power', () async {
        await service.saveRfPower(25);
        expect(service.getRfPower(), 25);
      });

      test('returns default RF power when not saved', () {
        expect(service.getRfPower(), RfidConfig.defaultRfPower);
      });

      test('clamps RF power to minimum', () async {
        await service.saveRfPower(-10);
        expect(service.getRfPower(), RfidConfig.minRfPower);
      });

      test('clamps RF power to maximum', () async {
        await service.saveRfPower(100);
        expect(service.getRfPower(), RfidConfig.maxRfPower);
      });

      test('accepts valid RF power within range', () async {
        await service.saveRfPower(15);
        expect(service.getRfPower(), 15);
      });
    });

    group('Access Password (Secure Storage)', () {
      test('saves password to secure storage', () async {
        when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value')))
            .thenAnswer((_) async {});

        await service.saveAccessPassword('AABBCCDD');

        verify(mockSecureStorage.write(
          key: 'rfid_access_password',
          value: 'AABBCCDD',
        )).called(1);
      });

      test('retrieves password from secure storage', () async {
        when(mockSecureStorage.read(key: anyNamed('key')))
            .thenAnswer((_) async => '12345678');

        final password = await service.getAccessPassword();

        expect(password, '12345678');
        verify(mockSecureStorage.read(key: 'rfid_access_password')).called(1);
      });

      test('returns null when no password saved', () async {
        when(mockSecureStorage.read(key: anyNamed('key')))
            .thenAnswer((_) async => null);

        final password = await service.getAccessPassword();

        expect(password, isNull);
      });

      test('clears password from secure storage', () async {
        when(mockSecureStorage.delete(key: anyNamed('key')))
            .thenAnswer((_) async {});

        await service.clearAccessPassword();

        verify(mockSecureStorage.delete(key: 'rfid_access_password')).called(1);
      });

      test('throws ArgumentError for invalid password - too short', () async {
        expect(
          () => service.saveAccessPassword('1234'),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError for invalid password - too long', () async {
        expect(
          () => service.saveAccessPassword('123456789ABC'),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError for invalid password - non-hex', () async {
        expect(
          () => service.saveAccessPassword('GGHHIIJJ'),
          throwsArgumentError,
        );
      });

      test('accepts lowercase hex password', () async {
        when(mockSecureStorage.write(key: anyNamed('key'), value: anyNamed('value')))
            .thenAnswer((_) async {});

        await service.saveAccessPassword('aabbccdd');

        verify(mockSecureStorage.write(
          key: 'rfid_access_password',
          value: 'aabbccdd',
        )).called(1);
      });
    });

    group('Bulk Operations', () {
      test('loadAllSettings returns all settings', () async {
        // Set up some values
        await service.savePort('/dev/ttyUSB0');
        await service.saveBaudRate(57600);
        await service.saveRfPower(25);

        when(mockSecureStorage.read(key: anyNamed('key')))
            .thenAnswer((_) async => 'AABBCCDD');

        final settings = await service.loadAllSettings();

        expect(settings.port, '/dev/ttyUSB0');
        expect(settings.baudRate, 57600);
        expect(settings.rfPower, 25);
        expect(settings.accessPassword, 'AABBCCDD');
      });

      test('loadAllSettings returns defaults when nothing saved', () async {
        when(mockSecureStorage.read(key: anyNamed('key')))
            .thenAnswer((_) async => null);

        final settings = await service.loadAllSettings();

        expect(settings.port, isNull);
        expect(settings.baudRate, RfidConfig.defaultBaudRate);
        expect(settings.rfPower, RfidConfig.defaultRfPower);
        expect(settings.accessPassword, isNull);
      });

      test('saveSettings saves port, baud rate, and RF power', () async {
        final settings = RfidSettings(
          port: '/dev/ttyUSB1',
          baudRate: 9600,
          rfPower: 20,
          accessPassword: 'ignored', // Should not be saved by this method
        );

        await service.saveSettings(settings);

        expect(service.getPort(), '/dev/ttyUSB1');
        expect(service.getBaudRate(), 9600);
        expect(service.getRfPower(), 20);
        // Access password should NOT have been saved
        verifyNever(mockSecureStorage.write(
          key: anyNamed('key'),
          value: anyNamed('value'),
        ));
      });

      test('saveSettings handles null port', () async {
        final settings = RfidSettings(
          port: null,
          baudRate: 9600,
          rfPower: 20,
        );

        await service.saveSettings(settings);

        expect(service.getPort(), isNull);
        expect(service.getBaudRate(), 9600);
        expect(service.getRfPower(), 20);
      });

      test('clearSettings removes all settings', () async {
        // Set up some values
        await service.savePort('/dev/ttyUSB0');
        await service.saveBaudRate(57600);
        await service.saveRfPower(25);

        when(mockSecureStorage.delete(key: anyNamed('key')))
            .thenAnswer((_) async {});

        await service.clearSettings();

        expect(service.getPort(), isNull);
        expect(service.getBaudRate(), RfidConfig.defaultBaudRate);
        expect(service.getRfPower(), RfidConfig.defaultRfPower);
        verify(mockSecureStorage.delete(key: 'rfid_access_password')).called(1);
      });
    });

    group('hasSettings', () {
      test('returns false when no settings saved', () {
        expect(service.hasSettings(), isFalse);
      });

      test('returns true when port is saved', () async {
        await service.savePort('/dev/ttyUSB0');
        expect(service.hasSettings(), isTrue);
      });

      test('returns true when baud rate is saved', () async {
        await service.saveBaudRate(9600);
        expect(service.hasSettings(), isTrue);
      });

      test('returns true when RF power is saved', () async {
        await service.saveRfPower(25);
        expect(service.hasSettings(), isTrue);
      });

      test('returns true when multiple settings saved', () async {
        await service.savePort('/dev/ttyUSB0');
        await service.saveBaudRate(9600);
        await service.saveRfPower(25);
        expect(service.hasSettings(), isTrue);
      });

      test('returns false after clearing all settings', () async {
        await service.savePort('/dev/ttyUSB0');
        await service.saveBaudRate(9600);

        when(mockSecureStorage.delete(key: anyNamed('key')))
            .thenAnswer((_) async {});

        await service.clearSettings();

        expect(service.hasSettings(), isFalse);
      });
    });
  });

  group('RfidSettings model', () {
    test('defaults factory creates correct defaults', () {
      final settings = RfidSettings.defaults();

      expect(settings.port, isNull);
      expect(settings.baudRate, RfidConfig.defaultBaudRate);
      expect(settings.rfPower, RfidConfig.defaultRfPower);
      expect(settings.accessPassword, isNull);
    });

    test('hasPort returns true when port is set', () {
      final settings = RfidSettings(port: '/dev/ttyUSB0');
      expect(settings.hasPort, isTrue);
    });

    test('hasPort returns false when port is null', () {
      final settings = RfidSettings(port: null);
      expect(settings.hasPort, isFalse);
    });

    test('hasPort returns false when port is empty', () {
      final settings = RfidSettings(port: '');
      expect(settings.hasPort, isFalse);
    });

    test('hasAccessPassword returns true when password is set', () {
      final settings = RfidSettings(accessPassword: 'AABBCCDD');
      expect(settings.hasAccessPassword, isTrue);
    });

    test('hasAccessPassword returns false when password is null', () {
      final settings = RfidSettings(accessPassword: null);
      expect(settings.hasAccessPassword, isFalse);
    });

    test('accessPasswordBytes converts hex to bytes', () {
      final settings = RfidSettings(accessPassword: 'AABBCCDD');
      expect(settings.accessPasswordBytes, [0xAA, 0xBB, 0xCC, 0xDD]);
    });

    test('accessPasswordBytes handles lowercase hex', () {
      final settings = RfidSettings(accessPassword: 'aabbccdd');
      expect(settings.accessPasswordBytes, [0xAA, 0xBB, 0xCC, 0xDD]);
    });

    test('accessPasswordBytes returns null for invalid length', () {
      final settings = RfidSettings(accessPassword: '1234');
      expect(settings.accessPasswordBytes, isNull);
    });

    test('accessPasswordBytes returns null for null password', () {
      final settings = RfidSettings(accessPassword: null);
      expect(settings.accessPasswordBytes, isNull);
    });

    test('isValidAccessPassword accepts valid hex', () {
      expect(RfidSettings.isValidAccessPassword('AABBCCDD'), isTrue);
      expect(RfidSettings.isValidAccessPassword('aabbccdd'), isTrue);
      expect(RfidSettings.isValidAccessPassword('12345678'), isTrue);
      expect(RfidSettings.isValidAccessPassword('00000000'), isTrue);
    });

    test('isValidAccessPassword accepts null/empty', () {
      expect(RfidSettings.isValidAccessPassword(null), isTrue);
      expect(RfidSettings.isValidAccessPassword(''), isTrue);
    });

    test('isValidAccessPassword rejects invalid input', () {
      expect(RfidSettings.isValidAccessPassword('1234'), isFalse); // Too short
      expect(RfidSettings.isValidAccessPassword('123456789'), isFalse); // Too long
      expect(RfidSettings.isValidAccessPassword('GGHHIIJJ'), isFalse); // Non-hex
    });

    test('copyWith creates new instance with updated values', () {
      final original = RfidSettings(
        port: '/dev/ttyUSB0',
        baudRate: 115200,
        rfPower: 20,
        accessPassword: 'AABBCCDD',
      );

      final updated = original.copyWith(
        port: '/dev/ttyUSB1',
        rfPower: 25,
      );

      expect(updated.port, '/dev/ttyUSB1');
      expect(updated.baudRate, 115200); // Unchanged
      expect(updated.rfPower, 25);
      expect(updated.accessPassword, 'AABBCCDD'); // Unchanged
    });

    test('copyWith can clear port', () {
      final original = RfidSettings(port: '/dev/ttyUSB0');
      final updated = original.copyWith(clearPort: true);
      expect(updated.port, isNull);
    });

    test('copyWith can clear access password', () {
      final original = RfidSettings(accessPassword: 'AABBCCDD');
      final updated = original.copyWith(clearAccessPassword: true);
      expect(updated.accessPassword, isNull);
    });

    test('equality works correctly', () {
      final settings1 = RfidSettings(
        port: '/dev/ttyUSB0',
        baudRate: 115200,
        rfPower: 20,
      );
      final settings2 = RfidSettings(
        port: '/dev/ttyUSB0',
        baudRate: 115200,
        rfPower: 20,
      );
      final settings3 = RfidSettings(
        port: '/dev/ttyUSB1',
        baudRate: 115200,
        rfPower: 20,
      );

      expect(settings1, equals(settings2));
      expect(settings1, isNot(equals(settings3)));
    });
  });
}
