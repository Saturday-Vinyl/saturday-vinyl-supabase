import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/device_type.dart';

void main() {
  group('DeviceType', () {
    final now = DateTime.now();
    final deviceType = DeviceType(
      id: 'device-123',
      name: 'ESP32 Audio Controller',
      description: 'ESP32-based audio controller with BLE and WiFi',
      capabilities: ['BLE', 'WiFi', 'Thread'],
      specUrl: 'https://example.com/esp32-spec.pdf',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    test('creates device type with all fields', () {
      expect(deviceType.id, 'device-123');
      expect(deviceType.name, 'ESP32 Audio Controller');
      expect(deviceType.description, 'ESP32-based audio controller with BLE and WiFi');
      expect(deviceType.capabilities, ['BLE', 'WiFi', 'Thread']);
      expect(deviceType.specUrl, 'https://example.com/esp32-spec.pdf');
      expect(deviceType.isActive, true);
    });

    test('creates device type without optional fields', () {
      final minimalDevice = DeviceType(
        id: 'device-456',
        name: 'Simple Device',
        capabilities: [],
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(minimalDevice.description, null);
      expect(minimalDevice.specUrl, null);
      expect(minimalDevice.capabilities, isEmpty);
    });

    test('hasCapability returns true for existing capability', () {
      expect(deviceType.hasCapability('BLE'), true);
      expect(deviceType.hasCapability('WiFi'), true);
      expect(deviceType.hasCapability('Thread'), true);
    });

    test('hasCapability returns false for non-existing capability', () {
      expect(deviceType.hasCapability('RFID'), false);
      expect(deviceType.hasCapability('Zigbee'), false);
    });

    test('hasCapability is case-sensitive', () {
      expect(deviceType.hasCapability('ble'), false);
      expect(deviceType.hasCapability('BLE'), true);
    });

    test('fromJson creates device type correctly', () {
      final json = {
        'id': 'device-123',
        'name': 'ESP32 Audio Controller',
        'description': 'ESP32-based audio controller',
        'capabilities': ['BLE', 'WiFi', 'Thread'],
        'spec_url': 'https://example.com/spec.pdf',
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final fromJson = DeviceType.fromJson(json);
      expect(fromJson.id, 'device-123');
      expect(fromJson.name, 'ESP32 Audio Controller');
      expect(fromJson.capabilities, ['BLE', 'WiFi', 'Thread']);
    });

    test('fromJson handles null capabilities as empty list', () {
      final json = {
        'id': 'device-123',
        'name': 'Simple Device',
        'capabilities': null,
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final fromJson = DeviceType.fromJson(json);
      expect(fromJson.capabilities, isEmpty);
    });

    test('fromJson handles missing capabilities field', () {
      final json = {
        'id': 'device-123',
        'name': 'Simple Device',
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final fromJson = DeviceType.fromJson(json);
      expect(fromJson.capabilities, isEmpty);
    });

    test('toJson converts device type correctly', () {
      final json = deviceType.toJson();
      expect(json['id'], 'device-123');
      expect(json['name'], 'ESP32 Audio Controller');
      expect(json['capabilities'], ['BLE', 'WiFi', 'Thread']);
      expect(json['spec_url'], 'https://example.com/esp32-spec.pdf');
    });

    test('copyWith creates new instance with updated fields', () {
      final updated = deviceType.copyWith(
        name: 'Updated Device',
        capabilities: ['BLE', 'WiFi', 'Thread', 'RFID'],
      );

      expect(updated.id, 'device-123'); // unchanged
      expect(updated.name, 'Updated Device'); // changed
      expect(updated.capabilities, ['BLE', 'WiFi', 'Thread', 'RFID']); // changed
    });

    test('equality works correctly', () {
      final device1 = DeviceType(
        id: 'device-123',
        name: 'ESP32',
        capabilities: ['BLE', 'WiFi'],
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final device2 = DeviceType(
        id: 'device-123',
        name: 'ESP32',
        capabilities: ['BLE', 'WiFi'],
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(device1, equals(device2));
      expect(device1.hashCode, equals(device2.hashCode));
    });

    test('different capabilities make devices unequal', () {
      final device1 = deviceType;
      final device2 = deviceType.copyWith(capabilities: ['BLE']);
      expect(device1, isNot(equals(device2)));
    });

    test('toString includes key information', () {
      final str = deviceType.toString();
      expect(str, contains('device-123'));
      expect(str, contains('ESP32 Audio Controller'));
      expect(str, contains('BLE'));
    });

    test('serialization round-trip preserves data', () {
      final json = deviceType.toJson();
      final fromJson = DeviceType.fromJson(json);
      expect(fromJson, equals(deviceType));
    });

    test('capabilities list can be modified in copyWith', () {
      final original = DeviceType(
        id: 'device-1',
        name: 'Test Device',
        capabilities: ['BLE'],
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final withMoreCapabilities = original.copyWith(
        capabilities: ['BLE', 'WiFi', 'Thread', 'RFID'],
      );

      expect(original.capabilities.length, 1);
      expect(withMoreCapabilities.capabilities.length, 4);
    });
  });
}
