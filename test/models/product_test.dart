import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/product.dart';

void main() {
  group('Product', () {
    final now = DateTime.now();
    final product = Product(
      id: 'prod-123',
      shopifyProductId: 'shopify-456',
      shopifyProductHandle: 'test-product',
      name: 'Test Product',
      productCode: 'PROD1',
      description: 'A test product',
      isActive: true,
      createdAt: now,
      updatedAt: now,
      lastSyncedAt: now,
    );

    test('creates product with all fields', () {
      expect(product.id, 'prod-123');
      expect(product.shopifyProductId, 'shopify-456');
      expect(product.shopifyProductHandle, 'test-product');
      expect(product.name, 'Test Product');
      expect(product.productCode, 'PROD1');
      expect(product.description, 'A test product');
      expect(product.isActive, true);
      expect(product.createdAt, now);
      expect(product.updatedAt, now);
      expect(product.lastSyncedAt, now);
    });

    test('creates product without optional fields', () {
      final minimalProduct = Product(
        id: 'prod-123',
        shopifyProductId: 'shopify-456',
        shopifyProductHandle: 'test-product',
        name: 'Test Product',
        productCode: 'PROD1',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(minimalProduct.description, null);
      expect(minimalProduct.lastSyncedAt, null);
    });

    test('fromJson creates product correctly', () {
      final json = {
        'id': 'prod-123',
        'shopify_product_id': 'shopify-456',
        'shopify_product_handle': 'test-product',
        'name': 'Test Product',
        'product_code': 'PROD1',
        'description': 'A test product',
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'last_synced_at': now.toIso8601String(),
      };

      final fromJson = Product.fromJson(json);

      expect(fromJson.id, 'prod-123');
      expect(fromJson.shopifyProductId, 'shopify-456');
      expect(fromJson.shopifyProductHandle, 'test-product');
      expect(fromJson.name, 'Test Product');
      expect(fromJson.productCode, 'PROD1');
      expect(fromJson.description, 'A test product');
      expect(fromJson.isActive, true);
    });

    test('fromJson handles null description', () {
      final json = {
        'id': 'prod-123',
        'shopify_product_id': 'shopify-456',
        'shopify_product_handle': 'test-product',
        'name': 'Test Product',
        'product_code': 'PROD1',
        'description': null,
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      };

      final fromJson = Product.fromJson(json);
      expect(fromJson.description, null);
      expect(fromJson.lastSyncedAt, null);
    });

    test('toJson converts product correctly', () {
      final json = product.toJson();

      expect(json['id'], 'prod-123');
      expect(json['shopify_product_id'], 'shopify-456');
      expect(json['shopify_product_handle'], 'test-product');
      expect(json['name'], 'Test Product');
      expect(json['product_code'], 'PROD1');
      expect(json['description'], 'A test product');
      expect(json['is_active'], true);
      expect(json['created_at'], now.toIso8601String());
      expect(json['updated_at'], now.toIso8601String());
      expect(json['last_synced_at'], now.toIso8601String());
    });

    test('copyWith creates new instance with updated fields', () {
      final updated = product.copyWith(
        name: 'Updated Product',
        productCode: 'PROD2',
      );

      expect(updated.id, 'prod-123'); // unchanged
      expect(updated.name, 'Updated Product'); // changed
      expect(updated.productCode, 'PROD2'); // changed
      expect(updated.shopifyProductId, 'shopify-456'); // unchanged
    });

    test('copyWith without changes returns equal product', () {
      final copy = product.copyWith();
      expect(copy, equals(product));
    });

    test('equality works correctly', () {
      final product1 = Product(
        id: 'prod-123',
        shopifyProductId: 'shopify-456',
        shopifyProductHandle: 'test-product',
        name: 'Test Product',
        productCode: 'PROD1',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      final product2 = Product(
        id: 'prod-123',
        shopifyProductId: 'shopify-456',
        shopifyProductHandle: 'test-product',
        name: 'Test Product',
        productCode: 'PROD1',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(product1, equals(product2));
      expect(product1.hashCode, equals(product2.hashCode));
    });

    test('different products are not equal', () {
      final product2 = product.copyWith(id: 'prod-456');
      expect(product, isNot(equals(product2)));
    });

    test('toString includes key information', () {
      final str = product.toString();
      expect(str, contains('prod-123'));
      expect(str, contains('Test Product'));
      expect(str, contains('PROD1'));
    });

    test('serialization round-trip preserves data', () {
      final json = product.toJson();
      final fromJson = Product.fromJson(json);
      expect(fromJson, equals(product));
    });
  });
}
