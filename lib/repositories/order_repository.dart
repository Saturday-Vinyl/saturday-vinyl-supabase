import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saturday_app/models/customer.dart';
import 'package:saturday_app/models/order.dart';
import 'package:saturday_app/models/order_line_item.dart';
import 'package:saturday_app/services/shopify_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing orders
class OrderRepository {
  final _supabase = Supabase.instance.client;
  final _shopifyService = ShopifyService();

  /// Sync orders from Shopify to local database
  ///
  /// Fetches unfulfilled orders from Shopify, transforms to Order model,
  /// and upserts to Supabase. Returns count of orders synced.
  Future<int> syncOrdersFromShopify() async {
    try {
      AppLogger.info('Starting Shopify order sync');

      // Fetch unfulfilled orders from Shopify
      final shopifyOrders = await _shopifyService.fetchOrders(
        queryFilter: 'fulfillment_status:unfulfilled',
      );

      AppLogger.info('Fetched ${shopifyOrders.length} unfulfilled orders from Shopify');

      int syncedCount = 0;

      for (final shopifyOrderData in shopifyOrders) {
        try {
          // Transform Shopify data to Order model
          final order = Order.fromShopify(shopifyOrderData);

          // Note: Customer data may not be available on Basic Shopify plans
          // Skip customer sync if customer data is not available
          String? customerId;
          if (order.customer != null) {
            customerId = await _upsertCustomer(order.customer!);
          } else {
            AppLogger.info('Skipping customer sync (not available on Basic plan)');
          }

          // Upsert order to database
          final orderId = await _upsertOrder(order, customerId);

          // Sync line items
          await _syncLineItems(orderId, order.lineItems);

          syncedCount++;
        } catch (e) {
          AppLogger.error('Error syncing order ${shopifyOrderData['name']}', e);
          // Continue with next order
        }
      }

      AppLogger.info('Order sync complete. Synced $syncedCount orders');
      return syncedCount;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to sync orders from Shopify', error, stackTrace);
      rethrow;
    }
  }

  /// Upsert customer to database
  ///
  /// Returns the database customer ID
  Future<String> _upsertCustomer(Customer customer) async {
    try {
      // Check if customer already exists by Shopify ID
      final existing = await _supabase
          .from('customers')
          .select('id')
          .eq('shopify_customer_id', customer.shopifyCustomerId)
          .maybeSingle();

      if (existing != null) {
        // Customer exists, update if needed
        final customerId = existing['id'] as String;
        await _supabase.from('customers').update({
          'email': customer.email,
          'first_name': customer.firstName,
          'last_name': customer.lastName,
        }).eq('id', customerId);

        return customerId;
      } else {
        // Insert new customer
        final result = await _supabase.from('customers').insert({
          'shopify_customer_id': customer.shopifyCustomerId,
          'email': customer.email,
          'first_name': customer.firstName,
          'last_name': customer.lastName,
        }).select('id').single();

        return result['id'] as String;
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upsert customer', error, stackTrace);
      rethrow;
    }
  }

  /// Upsert order to database
  ///
  /// Returns the database order ID
  Future<String> _upsertOrder(Order order, String? customerId) async {
    try {
      // Check if order already exists by Shopify ID
      final existing = await _supabase
          .from('orders')
          .select('id')
          .eq('shopify_order_id', order.shopifyOrderId)
          .maybeSingle();

      if (existing != null) {
        // Order exists, update if needed
        final orderId = existing['id'] as String;
        await _supabase.from('orders').update({
          'shopify_order_number': order.shopifyOrderNumber,
          'customer_id': customerId,
          'order_date': order.orderDate.toIso8601String(),
          'status': order.status,
          'fulfillment_status': order.fulfillmentStatus,
        }).eq('id', orderId);

        return orderId;
      } else {
        // Insert new order
        final result = await _supabase.from('orders').insert({
          'shopify_order_id': order.shopifyOrderId,
          'shopify_order_number': order.shopifyOrderNumber,
          'customer_id': customerId,
          'order_date': order.orderDate.toIso8601String(),
          'status': order.status,
          'fulfillment_status': order.fulfillmentStatus,
        }).select('id').single();

        return result['id'] as String;
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upsert order', error, stackTrace);
      rethrow;
    }
  }

  /// Sync line items for an order
  Future<void> _syncLineItems(String orderId, List<OrderLineItem> lineItems) async {
    try {
      // Delete existing line items for this order
      await _supabase.from('order_line_items').delete().eq('order_id', orderId);

      // Insert new line items
      for (final item in lineItems) {
        // Try to match Shopify product/variant to our internal IDs
        String? productId;
        String? variantId;

        AppLogger.info('Attempting to match line item: ${item.title}');
        AppLogger.info('  Shopify Product ID: ${item.shopifyProductId}');
        AppLogger.info('  Shopify Variant ID: ${item.shopifyVariantId}');

        try {
          // Look up product by Shopify product ID
          final productResult = await _supabase
              .from('products')
              .select('id, name, shopify_product_id')
              .eq('shopify_product_id', item.shopifyProductId)
              .maybeSingle();

          if (productResult != null) {
            productId = productResult['id'] as String;
            AppLogger.info('  ✓ Matched to product: ${productResult['name']} ($productId)');

            // Look up variant by Shopify variant ID
            final variantResult = await _supabase
                .from('product_variants')
                .select('id, name, shopify_variant_id')
                .eq('shopify_variant_id', item.shopifyVariantId)
                .eq('product_id', productId)
                .maybeSingle();

            if (variantResult != null) {
              variantId = variantResult['id'] as String;
              AppLogger.info('  ✓ Matched to variant: ${variantResult['name']} ($variantId)');
            } else {
              AppLogger.warning('  ✗ No variant match found for ${item.shopifyVariantId}');
            }
          } else {
            AppLogger.warning('  ✗ No product match found for ${item.shopifyProductId}');
          }
        } catch (e) {
          AppLogger.warning('Could not match line item to product/variant: $e');
        }

        // Insert line item
        await _supabase.from('order_line_items').insert({
          'order_id': orderId,
          'product_id': productId,
          'variant_id': variantId,
          'shopify_product_id': item.shopifyProductId,
          'shopify_variant_id': item.shopifyVariantId,
          'title': item.title,
          'quantity': item.quantity,
          'price': item.price,
        });
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to sync line items', error, stackTrace);
      rethrow;
    }
  }

  /// Get unfulfilled orders (orders without associated production units)
  Future<List<Order>> getUnfulfilledOrders() async {
    try {
      AppLogger.info('Fetching unfulfilled orders');

      final response = await _supabase
          .from('orders')
          .select('''
            *,
            customer:customers(*),
            line_items:order_line_items(*)
          ''')
          .isFilter('assigned_unit_id', null)
          .order('order_date', ascending: false);

      final orders = (response as List)
          .map((json) => Order.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Found ${orders.length} unfulfilled orders');
      return orders;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch unfulfilled orders', error, stackTrace);
      rethrow;
    }
  }

  /// Get recommended orders for a specific product variant
  ///
  /// Returns orders that have line items matching this product/variant
  /// and don't have a production unit assigned yet
  Future<List<Order>> getOrdersForProductVariant(
    String productId,
    String variantId,
  ) async {
    try {
      AppLogger.info('Fetching orders for product $productId, variant $variantId');

      // First, check what line items exist for debugging
      final allLineItems = await _supabase
          .from('order_line_items')
          .select('product_id, variant_id, title, shopify_product_id, shopify_variant_id')
          .limit(10);

      AppLogger.info('Sample line items in database (first 10):');
      for (final item in allLineItems as List) {
        AppLogger.info('  - ${item['title']}: product_id=${item['product_id']}, variant_id=${item['variant_id']}');
      }

      // First get order IDs that have matching line items
      final lineItemResponse = await _supabase
          .from('order_line_items')
          .select('order_id, product_id, variant_id, title')
          .eq('product_id', productId)
          .eq('variant_id', variantId);

      AppLogger.info('Line items matching query: ${(lineItemResponse as List).length}');

      final orderIds = (lineItemResponse as List)
          .map((item) => item['order_id'] as String)
          .toSet()
          .toList();

      if (orderIds.isEmpty) {
        AppLogger.info('No orders found for this product/variant');
        return [];
      }

      // Fetch orders with matching IDs that don't have units assigned
      final ordersResponse = await _supabase
          .from('orders')
          .select('''
            *,
            customer:customers(*),
            line_items:order_line_items(*)
          ''')
          .inFilter('id', orderIds)
          .isFilter('assigned_unit_id', null)
          .order('order_date', ascending: false);

      final orders = (ordersResponse as List)
          .map((json) => Order.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Found ${orders.length} recommended orders');
      return orders;
    } catch (error, stackTrace) {
      AppLogger.error(
        'Failed to fetch orders for product variant',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Get order by ID
  Future<Order?> getOrderById(String id) async {
    try {
      AppLogger.info('Fetching order by ID: $id');

      final response = await _supabase
          .from('orders')
          .select('''
            *,
            customer:customers(*),
            line_items:order_line_items(*)
          ''')
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Order.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch order by ID', error, stackTrace);
      rethrow;
    }
  }

  /// Assign a production unit to an order
  Future<void> assignUnitToOrder(String orderId, String unitId) async {
    try {
      AppLogger.info('Assigning unit $unitId to order $orderId');

      await _supabase
          .from('orders')
          .update({'assigned_unit_id': unitId})
          .eq('id', orderId);

      AppLogger.info('Unit assigned successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to assign unit to order', error, stackTrace);
      rethrow;
    }
  }

  /// Get all orders
  Future<List<Order>> getAllOrders() async {
    try {
      AppLogger.info('Fetching all orders');

      final response = await _supabase
          .from('orders')
          .select('''
            *,
            customer:customers(*),
            line_items:order_line_items(*)
          ''')
          .order('order_date', ascending: false);

      final orders = (response as List)
          .map((json) => Order.fromJson(json as Map<String, dynamic>))
          .toList();

      AppLogger.info('Found ${orders.length} orders');
      return orders;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch all orders', error, stackTrace);
      rethrow;
    }
  }
}
