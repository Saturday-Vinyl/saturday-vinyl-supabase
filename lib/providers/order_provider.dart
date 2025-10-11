import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/order.dart';
import 'package:saturday_app/repositories/order_repository.dart';

/// Provider for OrderRepository singleton
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository();
});

/// Provider for list of all orders
final ordersProvider = FutureProvider<List<Order>>((ref) async {
  final repository = ref.watch(orderRepositoryProvider);
  return repository.getAllOrders();
});

/// Provider for unfulfilled orders (orders without assigned production units)
final unfulfilledOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final repository = ref.watch(orderRepositoryProvider);
  return repository.getUnfulfilledOrders();
});

/// Provider for a single order by ID
final orderProvider = FutureProvider.family<Order?, String>((ref, orderId) async {
  final repository = ref.watch(orderRepositoryProvider);
  return repository.getOrderById(orderId);
});

/// Provider for recommended orders for a specific product variant
final recommendedOrdersProvider = FutureProvider.family<List<Order>, ({String productId, String variantId})>(
  (ref, params) async {
    final repository = ref.watch(orderRepositoryProvider);
    return repository.getOrdersForProductVariant(
      params.productId,
      params.variantId,
    );
  },
);

/// Provider for triggering order sync from Shopify
final syncOrdersProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(orderRepositoryProvider);
  return repository.syncOrdersFromShopify();
});

/// Notifier for syncing orders manually
class OrderSyncNotifier extends StateNotifier<AsyncValue<int>> {
  final OrderRepository _repository;

  OrderSyncNotifier(this._repository) : super(const AsyncValue.data(0));

  /// Trigger a sync from Shopify
  Future<void> sync() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _repository.syncOrdersFromShopify());
  }
}

/// Provider for order sync notifier
final orderSyncNotifierProvider = StateNotifierProvider<OrderSyncNotifier, AsyncValue<int>>((ref) {
  final repository = ref.watch(orderRepositoryProvider);
  return OrderSyncNotifier(repository);
});
