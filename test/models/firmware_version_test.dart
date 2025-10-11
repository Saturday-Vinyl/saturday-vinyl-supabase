import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/firmware_version.dart';

void main() {
  group('FirmwareVersion', () {
    group('fromJson', () {
      test('creates FirmwareVersion from valid JSON', () {
        final json = {
          'id': 'test-id-123',
          'device_type_id': 'device-456',
          'version': '1.2.3',
          'release_notes': 'Bug fixes and improvements',
          'binary_url': 'storage/v1/object/firmware-binaries/test.bin',
          'binary_filename': 'test-firmware.bin',
          'binary_size': 1024000,
          'is_production_ready': true,
          'created_at': '2025-01-01T00:00:00.000Z',
          'created_by': 'user-789',
        };

        final firmware = FirmwareVersion.fromJson(json);

        expect(firmware.id, equals('test-id-123'));
        expect(firmware.deviceTypeId, equals('device-456'));
        expect(firmware.version, equals('1.2.3'));
        expect(firmware.releaseNotes, equals('Bug fixes and improvements'));
        expect(firmware.binaryUrl, equals('storage/v1/object/firmware-binaries/test.bin'));
        expect(firmware.binaryFilename, equals('test-firmware.bin'));
        expect(firmware.binarySize, equals(1024000));
        expect(firmware.isProductionReady, isTrue);
        expect(firmware.createdBy, equals('user-789'));
      });

      test('handles null optional fields', () {
        final json = {
          'id': 'test-id-123',
          'device_type_id': 'device-456',
          'version': '1.0.0',
          'release_notes': null,
          'binary_url': 'storage/v1/object/firmware-binaries/test.bin',
          'binary_filename': 'test.bin',
          'binary_size': null,
          'is_production_ready': false,
          'created_at': '2025-01-01T00:00:00.000Z',
          'created_by': null,
        };

        final firmware = FirmwareVersion.fromJson(json);

        expect(firmware.releaseNotes, isNull);
        expect(firmware.binarySize, isNull);
        expect(firmware.createdBy, isNull);
        expect(firmware.isProductionReady, isFalse);
      });

      test('defaults isProductionReady to false when null', () {
        final json = {
          'id': 'test-id',
          'device_type_id': 'device-id',
          'version': '1.0.0',
          'binary_url': 'url',
          'binary_filename': 'file.bin',
          'is_production_ready': null,
          'created_at': '2025-01-01T00:00:00.000Z',
        };

        final firmware = FirmwareVersion.fromJson(json);
        expect(firmware.isProductionReady, isFalse);
      });
    });

    group('toJson', () {
      test('converts FirmwareVersion to JSON', () {
        final firmware = FirmwareVersion(
          id: 'test-id-123',
          deviceTypeId: 'device-456',
          version: '2.0.0',
          releaseNotes: 'Major update',
          binaryUrl: 'storage/v1/object/firmware-binaries/v2.bin',
          binaryFilename: 'firmware-v2.bin',
          binarySize: 2048000,
          isProductionReady: true,
          createdAt: DateTime.parse('2025-01-15T12:00:00.000Z'),
          createdBy: 'user-789',
        );

        final json = firmware.toJson();

        expect(json['id'], equals('test-id-123'));
        expect(json['device_type_id'], equals('device-456'));
        expect(json['version'], equals('2.0.0'));
        expect(json['release_notes'], equals('Major update'));
        expect(json['binary_url'], equals('storage/v1/object/firmware-binaries/v2.bin'));
        expect(json['binary_filename'], equals('firmware-v2.bin'));
        expect(json['binary_size'], equals(2048000));
        expect(json['is_production_ready'], isTrue);
        expect(json['created_at'], equals('2025-01-15T12:00:00.000Z'));
        expect(json['created_by'], equals('user-789'));
      });

      test('includes null values in JSON', () {
        final firmware = FirmwareVersion(
          id: 'test-id',
          deviceTypeId: 'device-id',
          version: '1.0.0',
          releaseNotes: null,
          binaryUrl: 'url',
          binaryFilename: 'file.bin',
          binarySize: null,
          isProductionReady: false,
          createdAt: DateTime.parse('2025-01-01T00:00:00.000Z'),
          createdBy: null,
        );

        final json = firmware.toJson();

        expect(json.containsKey('release_notes'), isTrue);
        expect(json['release_notes'], isNull);
        expect(json.containsKey('binary_size'), isTrue);
        expect(json['binary_size'], isNull);
        expect(json.containsKey('created_by'), isTrue);
        expect(json['created_by'], isNull);
      });
    });

    group('toInsertJson', () {
      test('excludes id and timestamps from insert JSON', () {
        final firmware = FirmwareVersion(
          id: 'test-id-123',
          deviceTypeId: 'device-456',
          version: '1.0.0',
          binaryUrl: 'url',
          binaryFilename: 'file.bin',
          isProductionReady: true,
          createdAt: DateTime.now(),
        );

        final json = firmware.toInsertJson();

        expect(json.containsKey('id'), isFalse);
        expect(json.containsKey('created_at'), isFalse);
        expect(json.containsKey('device_type_id'), isTrue);
        expect(json.containsKey('version'), isTrue);
        expect(json.containsKey('binary_url'), isTrue);
        expect(json.containsKey('binary_filename'), isTrue);
        expect(json.containsKey('is_production_ready'), isTrue);
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = FirmwareVersion(
          id: 'test-id',
          deviceTypeId: 'device-id',
          version: '1.0.0',
          binaryUrl: 'url',
          binaryFilename: 'file.bin',
          isProductionReady: false,
          createdAt: DateTime.parse('2025-01-01T00:00:00.000Z'),
        );

        final updated = original.copyWith(
          version: '2.0.0',
          isProductionReady: true,
        );

        expect(updated.id, equals(original.id));
        expect(updated.deviceTypeId, equals(original.deviceTypeId));
        expect(updated.version, equals('2.0.0'));
        expect(updated.isProductionReady, isTrue);
        expect(updated.binaryUrl, equals(original.binaryUrl));
      });

      test('preserves original values when not specified', () {
        final original = FirmwareVersion(
          id: 'test-id',
          deviceTypeId: 'device-id',
          version: '1.0.0',
          releaseNotes: 'Original notes',
          binaryUrl: 'url',
          binaryFilename: 'file.bin',
          binarySize: 1000,
          isProductionReady: false,
          createdAt: DateTime.parse('2025-01-01T00:00:00.000Z'),
        );

        final updated = original.copyWith(version: '1.0.1');

        expect(updated.releaseNotes, equals('Original notes'));
        expect(updated.binarySize, equals(1000));
        expect(updated.isProductionReady, isFalse);
      });
    });

    group('Equatable', () {
      test('equals returns true for identical firmware versions', () {
        final firmware1 = FirmwareVersion(
          id: 'test-id',
          deviceTypeId: 'device-id',
          version: '1.0.0',
          binaryUrl: 'url',
          binaryFilename: 'file.bin',
          isProductionReady: true,
          createdAt: DateTime.parse('2025-01-01T00:00:00.000Z'),
        );

        final firmware2 = FirmwareVersion(
          id: 'test-id',
          deviceTypeId: 'device-id',
          version: '1.0.0',
          binaryUrl: 'url',
          binaryFilename: 'file.bin',
          isProductionReady: true,
          createdAt: DateTime.parse('2025-01-01T00:00:00.000Z'),
        );

        expect(firmware1, equals(firmware2));
      });

      test('equals returns false for different firmware versions', () {
        final firmware1 = FirmwareVersion(
          id: 'test-id-1',
          deviceTypeId: 'device-id',
          version: '1.0.0',
          binaryUrl: 'url',
          binaryFilename: 'file.bin',
          isProductionReady: true,
          createdAt: DateTime.parse('2025-01-01T00:00:00.000Z'),
        );

        final firmware2 = FirmwareVersion(
          id: 'test-id-2',
          deviceTypeId: 'device-id',
          version: '1.0.0',
          binaryUrl: 'url',
          binaryFilename: 'file.bin',
          isProductionReady: true,
          createdAt: DateTime.parse('2025-01-01T00:00:00.000Z'),
        );

        expect(firmware1, isNot(equals(firmware2)));
      });
    });

    group('toString', () {
      test('returns readable string representation', () {
        final firmware = FirmwareVersion(
          id: 'test-id',
          deviceTypeId: 'device-id',
          version: '1.0.0',
          binaryUrl: 'url',
          binaryFilename: 'file.bin',
          isProductionReady: true,
          createdAt: DateTime.parse('2025-01-01T00:00:00.000Z'),
        );

        final str = firmware.toString();

        expect(str, contains('test-id'));
        expect(str, contains('1.0.0'));
        expect(str, contains('device-id'));
        expect(str, contains('true'));
      });
    });
  });
}
