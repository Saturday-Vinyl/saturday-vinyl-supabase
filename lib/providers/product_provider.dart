import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/product_variant.dart';
import 'package:saturday_app/repositories/product_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Provider for ProductRepository
final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});

/// Provider for all products (stream of products from database)
final productsProvider = FutureProvider<List<Product>>((ref) async {
  final repository = ref.watch(productRepositoryProvider);
  return await repository.getProducts();
});

/// Provider for a single product by ID (family provider)
final productProvider = FutureProvider.family<Product?, String>((ref, productId) async {
  final repository = ref.watch(productRepositoryProvider);
  return await repository.getProduct(productId);
});

/// Provider for variants of a specific product (family provider)
final productVariantsProvider = FutureProvider.family<List<ProductVariant>, String>((ref, productId) async {
  final repository = ref.watch(productRepositoryProvider);
  return await repository.getProductVariants(productId);
});

/// Provider for all variants across all products
final allVariantsProvider = FutureProvider<List<ProductVariant>>((ref) async {
  final repository = ref.watch(productRepositoryProvider);
  return await repository.getAllVariants();
});

/// Provider for a single variant by ID (family provider)
final variantProvider = FutureProvider.family<ProductVariant?, String>((ref, variantId) async {
  final repository = ref.watch(productRepositoryProvider);
  return await repository.getVariant(variantId);
});

/// Provider for variant management operations
final variantManagementProvider = Provider<VariantManagement>((ref) {
  return VariantManagement(ref);
});

/// Management class for variant CRUD operations
class VariantManagement {
  final Ref ref;

  VariantManagement(this.ref);

  /// Create a new variant
  Future<ProductVariant> createVariant({
    required String productId,
    required String shopifyVariantId,
    required String sku,
    required String name,
    String? option1Name,
    String? option1Value,
    String? option2Name,
    String? option2Value,
    String? option3Name,
    String? option3Value,
    required double price,
  }) async {
    final repository = ref.read(productRepositoryProvider);
    final variant = await repository.createVariant(
      productId: productId,
      shopifyVariantId: shopifyVariantId,
      sku: sku,
      name: name,
      option1Name: option1Name,
      option1Value: option1Value,
      option2Name: option2Name,
      option2Value: option2Value,
      option3Name: option3Name,
      option3Value: option3Value,
      price: price,
    );

    // Invalidate providers to refresh UI
    ref.invalidate(productVariantsProvider(productId));
    ref.invalidate(allVariantsProvider);

    return variant;
  }

  /// Update an existing variant
  Future<ProductVariant> updateVariant({
    required String variantId,
    required String productId,
    String? sku,
    String? name,
    String? option1Name,
    String? option1Value,
    String? option2Name,
    String? option2Value,
    String? option3Name,
    String? option3Value,
    double? price,
    bool? isActive,
  }) async {
    final repository = ref.read(productRepositoryProvider);
    final variant = await repository.updateVariant(
      variantId: variantId,
      sku: sku,
      name: name,
      option1Name: option1Name,
      option1Value: option1Value,
      option2Name: option2Name,
      option2Value: option2Value,
      option3Name: option3Name,
      option3Value: option3Value,
      price: price,
      isActive: isActive,
    );

    // Invalidate providers to refresh UI
    ref.invalidate(variantProvider(variantId));
    ref.invalidate(productVariantsProvider(productId));
    ref.invalidate(allVariantsProvider);

    return variant;
  }

  /// Delete a variant
  Future<void> deleteVariant(String variantId, String productId) async {
    final repository = ref.read(productRepositoryProvider);
    await repository.deleteVariant(variantId);

    // Invalidate providers to refresh UI
    ref.invalidate(variantProvider(variantId));
    ref.invalidate(productVariantsProvider(productId));
    ref.invalidate(allVariantsProvider);
  }

  /// Toggle product active status
  Future<Product> toggleProductActive(String productId, bool isActive) async {
    final repository = ref.read(productRepositoryProvider);
    final product = await repository.toggleProductActive(productId, isActive);

    // Invalidate providers to refresh UI
    ref.invalidate(productProvider(productId));
    ref.invalidate(productsProvider);

    return product;
  }
}

/// Provider for syncing products from Shopify
/// Returns a StateNotifier to track sync progress
final syncProductsProvider = StateNotifierProvider<SyncProductsNotifier, SyncState>((ref) {
  return SyncProductsNotifier(ref);
});

/// State for product sync operations
class SyncState {
  final bool isLoading;
  final int? syncedCount;
  final String? error;
  final DateTime? lastSyncedAt;

  const SyncState({
    this.isLoading = false,
    this.syncedCount,
    this.error,
    this.lastSyncedAt,
  });

  SyncState copyWith({
    bool? isLoading,
    int? syncedCount,
    String? error,
    DateTime? lastSyncedAt,
  }) {
    return SyncState(
      isLoading: isLoading ?? this.isLoading,
      syncedCount: syncedCount ?? this.syncedCount,
      error: error ?? this.error,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

/// Notifier for managing product sync operations
class SyncProductsNotifier extends StateNotifier<SyncState> {
  final Ref ref;

  SyncProductsNotifier(this.ref) : super(const SyncState());

  /// Trigger a sync from Shopify
  Future<void> syncFromShopify() async {
    if (state.isLoading) {
      AppLogger.warning('Sync already in progress');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final repository = ref.read(productRepositoryProvider);
      final syncedCount = await repository.syncProductsFromShopify();

      state = state.copyWith(
        isLoading: false,
        syncedCount: syncedCount,
        lastSyncedAt: DateTime.now(),
      );

      // Invalidate products provider to refresh the list
      ref.invalidate(productsProvider);

      AppLogger.info('Product sync completed successfully: $syncedCount products');
    } catch (error, stackTrace) {
      AppLogger.error('Product sync failed', error, stackTrace);
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
      );
    }
  }
}
