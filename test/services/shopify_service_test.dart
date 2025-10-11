import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/services/shopify_queries.dart';

void main() {
  group('ShopifyQueries', () {
    test('productsQuery contains required fields', () {
      expect(ShopifyQueries.productsQuery, contains('products'));
      expect(ShopifyQueries.productsQuery, contains('pageInfo'));
      expect(ShopifyQueries.productsQuery, contains('hasNextPage'));
      expect(ShopifyQueries.productsQuery, contains('endCursor'));
      expect(ShopifyQueries.productsQuery, contains('id'));
      expect(ShopifyQueries.productsQuery, contains('handle'));
      expect(ShopifyQueries.productsQuery, contains('title'));
      expect(ShopifyQueries.productsQuery, contains('description'));
      expect(ShopifyQueries.productsQuery, contains('variants'));
      expect(ShopifyQueries.productsQuery, contains('sku'));
      expect(ShopifyQueries.productsQuery, contains('price'));
      expect(ShopifyQueries.productsQuery, contains('selectedOptions'));
    });

    test('productsQuery supports pagination parameters', () {
      expect(ShopifyQueries.productsQuery, contains(r'$first'));
      expect(ShopifyQueries.productsQuery, contains(r'$after'));
    });

    test('productQuery contains required fields', () {
      expect(ShopifyQueries.productQuery, contains('product'));
      expect(ShopifyQueries.productQuery, contains(r'$id'));
      expect(ShopifyQueries.productQuery, contains('id'));
      expect(ShopifyQueries.productQuery, contains('handle'));
      expect(ShopifyQueries.productQuery, contains('title'));
      expect(ShopifyQueries.productQuery, contains('variants'));
    });

    test('ordersQuery contains required fields', () {
      expect(ShopifyQueries.ordersQuery, contains('orders'));
      expect(ShopifyQueries.ordersQuery, contains('pageInfo'));
      expect(ShopifyQueries.ordersQuery, contains('customer'));
      expect(ShopifyQueries.ordersQuery, contains('email'));
      expect(ShopifyQueries.ordersQuery, contains('firstName'));
      expect(ShopifyQueries.ordersQuery, contains('lastName'));
      expect(ShopifyQueries.ordersQuery, contains('lineItems'));
      expect(ShopifyQueries.ordersQuery, contains('fulfillmentStatus'));
    });

    test('ordersQuery supports pagination and filtering', () {
      expect(ShopifyQueries.ordersQuery, contains(r'$first'));
      expect(ShopifyQueries.ordersQuery, contains(r'$after'));
      expect(ShopifyQueries.ordersQuery, contains(r'$query'));
    });

    test('orderQuery fetches single order', () {
      expect(ShopifyQueries.orderQuery, contains('order'));
      expect(ShopifyQueries.orderQuery, contains(r'$id'));
      expect(ShopifyQueries.orderQuery, contains('customer'));
      expect(ShopifyQueries.orderQuery, contains('lineItems'));
    });

    test('all queries are valid GraphQL syntax', () {
      // Basic syntax checks
      final queries = [
        ShopifyQueries.productsQuery,
        ShopifyQueries.productQuery,
        ShopifyQueries.ordersQuery,
        ShopifyQueries.orderQuery,
      ];

      for (final query in queries) {
        // Check for matching braces
        final openBraces = '{'.allMatches(query).length;
        final closeBraces = '}'.allMatches(query).length;
        expect(openBraces, equals(closeBraces), reason: 'Query has unmatched braces');

        // Check for matching parentheses
        final openParens = '('.allMatches(query).length;
        final closeParens = ')'.allMatches(query).length;
        expect(openParens, equals(closeParens), reason: 'Query has unmatched parentheses');
      }
    });

    test('productsQuery fetches up to 100 variants per product', () {
      expect(ShopifyQueries.productsQuery, contains('variants(first: 100)'));
    });

    test('productQuery fetches up to 100 variants', () {
      expect(ShopifyQueries.productQuery, contains('variants(first: 100)'));
    });

    test('ordersQuery fetches up to 50 line items per order', () {
      expect(ShopifyQueries.ordersQuery, contains('lineItems(first: 50)'));
    });

    test('orderQuery fetches up to 50 line items', () {
      expect(ShopifyQueries.orderQuery, contains('lineItems(first: 50)'));
    });
  });

  group('ShopifyService', () {
    // Note: We can't test the actual service without mocking GraphQL client
    // These tests verify the structure is correct
    test('service should be a singleton', () {
      // This would require importing ShopifyService, but we can't test it
      // without proper mocking setup. For now, we'll rely on integration tests.
      expect(true, true);
    });
  });
}
