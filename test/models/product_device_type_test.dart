import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/product_device_type.dart';

void main() {
  group('ProductDeviceType', () {
    final productDeviceType = ProductDeviceType(
      productId: 'prod-123',
      deviceTypeId: 'device-456',
      quantity: 2,
    );

    test('creates product device type with all fields', () {
      expect(productDeviceType.productId, 'prod-123');
      expect(productDeviceType.deviceTypeId, 'device-456');
      expect(productDeviceType.quantity, 2);
    });

    test('fromJson creates product device type correctly', () {
      final json = {
        'product_id': 'prod-123',
        'device_type_id': 'device-456',
        'quantity': 2,
      };

      final fromJson = ProductDeviceType.fromJson(json);
      expect(fromJson.productId, 'prod-123');
      expect(fromJson.deviceTypeId, 'device-456');
      expect(fromJson.quantity, 2);
    });

    test('toJson converts product device type correctly', () {
      final json = productDeviceType.toJson();
      expect(json['product_id'], 'prod-123');
      expect(json['device_type_id'], 'device-456');
      expect(json['quantity'], 2);
    });

    test('copyWith creates new instance with updated fields', () {
      final updated = productDeviceType.copyWith(quantity: 3);

      expect(updated.productId, 'prod-123'); // unchanged
      expect(updated.deviceTypeId, 'device-456'); // unchanged
      expect(updated.quantity, 3); // changed
    });

    test('copyWith without changes returns equal instance', () {
      final copy = productDeviceType.copyWith();
      expect(copy, equals(productDeviceType));
    });

    test('equality works correctly', () {
      final pdt1 = ProductDeviceType(
        productId: 'prod-123',
        deviceTypeId: 'device-456',
        quantity: 2,
      );

      final pdt2 = ProductDeviceType(
        productId: 'prod-123',
        deviceTypeId: 'device-456',
        quantity: 2,
      );

      expect(pdt1, equals(pdt2));
      expect(pdt1.hashCode, equals(pdt2.hashCode));
    });

    test('different quantities make instances unequal', () {
      final pdt2 = productDeviceType.copyWith(quantity: 5);
      expect(productDeviceType, isNot(equals(pdt2)));
    });

    test('toString includes key information', () {
      final str = productDeviceType.toString();
      expect(str, contains('prod-123'));
      expect(str, contains('device-456'));
      expect(str, contains('2'));
    });

    test('serialization round-trip preserves data', () {
      final json = productDeviceType.toJson();
      final fromJson = ProductDeviceType.fromJson(json);
      expect(fromJson, equals(productDeviceType));
    });

    test('handles different quantity values', () {
      final single = ProductDeviceType(
        productId: 'prod-1',
        deviceTypeId: 'device-1',
        quantity: 1,
      );
      expect(single.quantity, 1);

      final multiple = ProductDeviceType(
        productId: 'prod-1',
        deviceTypeId: 'device-1',
        quantity: 10,
      );
      expect(multiple.quantity, 10);
    });

    test('different product IDs make instances unequal', () {
      final pdt2 = productDeviceType.copyWith(productId: 'prod-999');
      expect(productDeviceType, isNot(equals(pdt2)));
    });

    test('different device type IDs make instances unequal', () {
      final pdt2 = productDeviceType.copyWith(deviceTypeId: 'device-999');
      expect(productDeviceType, isNot(equals(pdt2)));
    });
  });
}
