import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/screens/products/product_detail_screen.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/products/product_card.dart';

/// Screen displaying list of products with sync functionality
class ProductListScreen extends ConsumerWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final syncState = ref.watch(syncProductsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          // Sync button
          if (syncState.isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(SaturdayColors.light),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync from Shopify',
              onPressed: () => _handleSync(context, ref),
            ),
        ],
      ),
      body: Column(
        children: [
          // Sync status banner
          if (syncState.lastSyncedAt != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: SaturdayColors.light,
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: SaturdayColors.success,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Last synced: ${syncState.lastSyncedAt!.toString()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (syncState.syncedCount != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(${syncState.syncedCount} products)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          // Error banner
          if (syncState.error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: SaturdayColors.error.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: SaturdayColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Sync failed: ${syncState.error}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.error,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          // Products list
          Expanded(
            child: productsAsync.when(
              data: (products) {
                if (products.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'No products found.\nSync from Shopify to get started.',
                    actionLabel: 'Sync Products',
                    onAction: () => _handleSync(context, ref),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(productsProvider);
                  },
                  child: ListView.builder(
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return ProductCard(
                        product: product,
                        onTap: () => _navigateToDetail(context, product.id),
                      );
                    },
                  ),
                );
              },
              loading: () => const LoadingIndicator(message: 'Loading products...'),
              error: (error, stack) => ErrorState(
                message: 'Failed to load products',
                details: error.toString(),
                onRetry: () => ref.invalidate(productsProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Handle sync from Shopify
  Future<void> _handleSync(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(syncProductsProvider.notifier);
    await notifier.syncFromShopify();

    if (context.mounted) {
      final syncState = ref.read(syncProductsProvider);
      if (syncState.error == null && syncState.syncedCount != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully synced ${syncState.syncedCount} products'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    }
  }

  /// Navigate to product detail screen
  void _navigateToDetail(BuildContext context, String productId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(productId: productId),
      ),
    );
  }
}
