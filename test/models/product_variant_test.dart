import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/product_variant.dart';

void main() {
  group('ProductVariant', () {
    final now = DateTime.now();
    final variant = ProductVariant(
      id: 'var-123',
      productId: 'prod-456',
      shopifyVariantId: 'shopify-789',
      sku: 'TEST-SKU-001',
      name: 'Test Variant',
      option1Name: 'Wood Species',
      option1Value: 'Walnut',
      option2Name: 'Liner Color',
      option2Value: 'Black',
      option3Name: 'Size',
      option3Value: 'Large',
      price: 299.99,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    test('creates variant with all fields', () {
      expect(variant.id, 'var-123');
      expect(variant.productId, 'prod-456');
      expect(variant.shopifyVariantId, 'shopify-789');
      expect(variant.sku, 'TEST-SKU-001');
      expect(variant.name, 'Test Variant');
      expect(variant.option1Name, 'Wood Species');
      expect(variant.option1Value, 'Walnut');
      expect(variant.option2Name, 'Liner Color');
      expect(variant.option2Value, 'Black');
      expect(variant.option3Name, 'Size');
      expect(variant.option3Value, 'Large');
      expect(variant.price, 299.99);
      expect(variant.isActive, true);
    });

    test('getFormattedVariantName returns all options', () {
      final formatted = variant.getFormattedVariantName();
      expect(formatted, 'Walnut / Black / Large');
    });

    test('getFormattedVariantName with two options', () {
      final variant2 = variant.copyWith(
        option3Name: null,
        option3Value: null,
      );
      final formatted = variant2.getFormattedVariantName();
      expect(formatted, 'Walnut / Black');
    });

    test('getFormattedVariantName with one option', () {
      final variant2 = variant.copyWith(
        option2Name: null,
        option2Value: null,
        option3Name: null,
        option3Value: null,
      );
      final formatted = variant2.getFormattedVariantName();
      expect(formatted, 'Walnut');
    });

    test('getFormattedVariantName with no options returns name', () {
      final variant2 = variant.copyWith(
        option1Name: null,
        option1Value: null,
        option2Name: null,
        option2Value: null,
        option3Name: null,
        option3Value: null,
      );
      final formatted = variant2.getFormattedVariantName();
      expect(formatted, 'Test Variant');
    });

    test('getFormattedVariantName handles empty option values', () {
      final variant2 = ProductVariant(
        id: 'var-123',
        productId: 'prod-456',
        shopifyVariantId: 'shopify-789',
        sku: 'TEST-SKU-001',
        name: 'Test Variant',
        option1Name: 'Color',
        option1Value: '',
        price: 299.99,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
      expect(variant2.getFormattedVariantName(), 'Test Variant');
    });

    test('fromJson creates variant correctly', () {
      final json = {
        'id': 'var-123',
        'product_id': 'prod-456',
        'shopify_variant_id': 'shopify-789',
        'sku': 'TEST-SKU-001',
        'name': 'Test Variant',
        'option1_name': 'Wood Species',
        'option1_value': 'Walnut',
        'option2_name': 'Liner Color',
        'option2_value': 'Black',
        'option3_name': 'Size',
        'option3_value': 'Large',
        'price': 299.99,
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final fromJson = ProductVariant.fromJson(json);
      expect(fromJson.id, 'var-123');
      expect(fromJson.option1Value, 'Walnut');
      expect(fromJson.price, 299.99);
    });

    test('fromJson handles null options', () {
      final json = {
        'id': 'var-123',
        'product_id': 'prod-456',
        'shopify_variant_id': 'shopify-789',
        'sku': 'TEST-SKU-001',
        'name': 'Test Variant',
        'price': 99.99,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final fromJson = ProductVariant.fromJson(json);
      expect(fromJson.option1Name, null);
      expect(fromJson.option1Value, null);
      expect(fromJson.option2Name, null);
      expect(fromJson.option2Value, null);
      expect(fromJson.option3Name, null);
      expect(fromJson.option3Value, null);
    });

    test('toJson converts variant correctly', () {
      final json = variant.toJson();
      expect(json['id'], 'var-123');
      expect(json['sku'], 'TEST-SKU-001');
      expect(json['option1_value'], 'Walnut');
      expect(json['price'], 299.99);
    });

    test('copyWith creates new instance with updated fields', () {
      final updated = variant.copyWith(
        price: 399.99,
        option1Value: 'Oak',
      );

      expect(updated.id, 'var-123'); // unchanged
      expect(updated.price, 399.99); // changed
      expect(updated.option1Value, 'Oak'); // changed
    });

    test('equality works correctly', () {
      final variant1 = ProductVariant(
        id: 'var-123',
        productId: 'prod-456',
        shopifyVariantId: 'shopify-789',
        sku: 'TEST-SKU-001',
        name: 'Test Variant',
        price: 299.99,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final variant2 = ProductVariant(
        id: 'var-123',
        productId: 'prod-456',
        shopifyVariantId: 'shopify-789',
        sku: 'TEST-SKU-001',
        name: 'Test Variant',
        price: 299.99,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(variant1, equals(variant2));
      expect(variant1.hashCode, equals(variant2.hashCode));
    });

    test('toString includes formatted variant name', () {
      final str = variant.toString();
      expect(str, contains('Walnut / Black / Large'));
    });

    test('serialization round-trip preserves data', () {
      final json = variant.toJson();
      final fromJson = ProductVariant.fromJson(json);
      expect(fromJson, equals(variant));
    });
  });
}
