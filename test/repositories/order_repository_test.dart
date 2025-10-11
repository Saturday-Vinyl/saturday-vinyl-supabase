import 'package:flutter_test/flutter_test.dart';
import 'package:saturday_app/models/customer.dart';
import 'package:saturday_app/models/order.dart';
import 'package:saturday_app/models/order_line_item.dart';

void main() {
  group('Order Model Tests', () {
    final now = DateTime.now();

    test('Order.fromShopify creates order correctly', () {
      // Sample Shopify order data
      final shopifyData = {
        'id': 'gid://shopify/Order/1234567890',
        'name': '#1001',
        'createdAt': '2024-01-15T10:30:00Z',
        'fulfillmentStatus': 'UNFULFILLED',
        'customer': {
          'id': 'gid://shopify/Customer/987654321',
          'email': 'customer@example.com',
          'firstName': 'John',
          'lastName': 'Doe',
        },
        'lineItems': {
          'edges': [
            {
              'node': {
                'id': 'gid://shopify/LineItem/111',
                'title': 'Turntable - Walnut',
                'quantity': 1,
                'variant': {
                  'id': 'gid://shopify/ProductVariant/222',
                  'product': {
                    'id': 'gid://shopify/Product/333',
                  },
                },
              },
            },
          ],
        },
      };

      final order = Order.fromShopify(shopifyData);

      // Verify order fields
      expect(order.shopifyOrderId, 'gid://shopify/Order/1234567890');
      expect(order.shopifyOrderNumber, '1001');
      expect(order.status, 'UNFULFILLED');
      expect(order.fulfillmentStatus, 'UNFULFILLED');

      // Verify customer
      expect(order.customer, isNotNull);
      expect(order.customer!.shopifyCustomerId,
          'gid://shopify/Customer/987654321');
      expect(order.customer!.email, 'customer@example.com');
      expect(order.customer!.firstName, 'John');
      expect(order.customer!.lastName, 'Doe');

      // Verify line items
      expect(order.lineItems.length, 1);
      expect(order.lineItems[0].title, 'Turntable - Walnut');
      expect(order.lineItems[0].quantity, 1);
      expect(order.lineItems[0].shopifyProductId, 'gid://shopify/Product/333');
      expect(order.lineItems[0].shopifyVariantId,
          'gid://shopify/ProductVariant/222');
    });

    test('Order.fromShopify handles order without customer', () {
      final shopifyData = {
        'id': 'gid://shopify/Order/1234567890',
        'name': '#1001',
        'createdAt': '2024-01-15T10:30:00Z',
        'fulfillmentStatus': 'UNFULFILLED',
        'lineItems': {
          'edges': [],
        },
      };

      final order = Order.fromShopify(shopifyData);

      expect(order.customer, isNull);
      expect(order.lineItems, isEmpty);
    });

    test('Order.customerName returns correct name', () {
      final customer = Customer(
        id: 'cust-1',
        shopifyCustomerId: 'shopify-cust-1',
        email: 'test@example.com',
        firstName: 'Jane',
        lastName: 'Smith',
        createdAt: now,
      );

      final order = Order(
        id: 'order-1',
        shopifyOrderId: 'shopify-order-1',
        shopifyOrderNumber: '1001',
        orderDate: now,
        status: 'unfulfilled',
        createdAt: now,
        customer: customer,
      );

      expect(order.customerName, 'Jane Smith');
    });

    test('Order.customerName returns "Unknown Customer" when no customer', () {
      final order = Order(
        id: 'order-1',
        shopifyOrderId: 'shopify-order-1',
        shopifyOrderNumber: '1001',
        orderDate: now,
        status: 'unfulfilled',
        createdAt: now,
      );

      expect(order.customerName, 'Unknown Customer');
    });

    test('Order.needsProductionUnit returns true when has line items and not assigned', () {
      final lineItem = OrderLineItem(
        id: 'line-1',
        orderId: 'order-1',
        shopifyProductId: 'prod-1',
        shopifyVariantId: 'var-1',
        title: 'Product 1',
        quantity: 1,
      );

      final order = Order(
        id: 'order-1',
        shopifyOrderId: 'shopify-order-1',
        shopifyOrderNumber: '1001',
        orderDate: now,
        status: 'unfulfilled',
        createdAt: now,
        lineItems: [lineItem],
        assignedUnitId: null,
      );

      expect(order.needsProductionUnit(), true);
    });

    test('Order.needsProductionUnit returns false when assigned', () {
      final lineItem = OrderLineItem(
        id: 'line-1',
        orderId: 'order-1',
        shopifyProductId: 'prod-1',
        shopifyVariantId: 'var-1',
        title: 'Product 1',
        quantity: 1,
      );

      final order = Order(
        id: 'order-1',
        shopifyOrderId: 'shopify-order-1',
        shopifyOrderNumber: '1001',
        orderDate: now,
        status: 'unfulfilled',
        createdAt: now,
        lineItems: [lineItem],
        assignedUnitId: 'unit-1',
      );

      expect(order.needsProductionUnit(), false);
    });

    test('Order.needsProductionUnit returns false when no line items', () {
      final order = Order(
        id: 'order-1',
        shopifyOrderId: 'shopify-order-1',
        shopifyOrderNumber: '1001',
        orderDate: now,
        status: 'unfulfilled',
        createdAt: now,
        lineItems: [],
      );

      expect(order.needsProductionUnit(), false);
    });

    test('Order serialization round-trip preserves data', () {
      final customer = Customer(
        id: 'cust-1',
        shopifyCustomerId: 'shopify-cust-1',
        email: 'test@example.com',
        firstName: 'Test',
        lastName: 'User',
        createdAt: now,
      );

      final lineItem = OrderLineItem(
        id: 'line-1',
        orderId: 'order-1',
        shopifyProductId: 'prod-1',
        shopifyVariantId: 'var-1',
        title: 'Product 1',
        quantity: 2,
      );

      final order = Order(
        id: 'order-1',
        shopifyOrderId: 'shopify-order-1',
        shopifyOrderNumber: '1001',
        orderDate: now,
        status: 'unfulfilled',
        createdAt: now,
        customer: customer,
        lineItems: [lineItem],
        fulfillmentStatus: 'UNFULFILLED',
      );

      final json = order.toJson();
      final fromJson = Order.fromJson(json);

      expect(fromJson.id, order.id);
      expect(fromJson.shopifyOrderId, order.shopifyOrderId);
      expect(fromJson.shopifyOrderNumber, order.shopifyOrderNumber);
      expect(fromJson.customer?.email, order.customer?.email);
      expect(fromJson.lineItems.length, order.lineItems.length);
      expect(fromJson.fulfillmentStatus, order.fulfillmentStatus);
    });
  });

  group('OrderLineItem Model Tests', () {
    test('OrderLineItem.fromShopify creates line item correctly', () {
      final shopifyData = {
        'id': 'gid://shopify/LineItem/111',
        'title': 'Turntable - Walnut',
        'quantity': 2,
        'variant': {
          'id': 'gid://shopify/ProductVariant/222',
          'product': {
            'id': 'gid://shopify/Product/333',
          },
        },
      };

      final lineItem = OrderLineItem.fromShopify(shopifyData, 'order-1');

      expect(lineItem.orderId, 'order-1');
      expect(lineItem.title, 'Turntable - Walnut');
      expect(lineItem.quantity, 2);
      expect(lineItem.shopifyProductId, 'gid://shopify/Product/333');
      expect(lineItem.shopifyVariantId, 'gid://shopify/ProductVariant/222');
    });

    test('OrderLineItem.fromShopify handles missing variant', () {
      final shopifyData = {
        'id': 'gid://shopify/LineItem/111',
        'title': 'Product Name',
        'quantity': 1,
      };

      final lineItem = OrderLineItem.fromShopify(shopifyData, 'order-1');

      expect(lineItem.title, 'Product Name');
      expect(lineItem.quantity, 1);
      expect(lineItem.shopifyProductId, '');
      expect(lineItem.shopifyVariantId, '');
    });

    test('OrderLineItem serialization round-trip preserves data', () {
      final lineItem = OrderLineItem(
        id: 'line-1',
        orderId: 'order-1',
        productId: 'prod-1',
        variantId: 'var-1',
        shopifyProductId: 'shopify-prod-1',
        shopifyVariantId: 'shopify-var-1',
        title: 'Test Product',
        quantity: 3,
        price: '99.99',
      );

      final json = lineItem.toJson();
      final fromJson = OrderLineItem.fromJson(json);

      expect(fromJson, equals(lineItem));
    });
  });
}
