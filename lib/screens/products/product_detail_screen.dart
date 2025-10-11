import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/providers/production_step_provider.dart';
import 'package:saturday_app/screens/products/production_steps_config_screen.dart';
import 'package:saturday_app/utils/extensions.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/products/production_step_item.dart';

/// Screen displaying detailed information about a product
class ProductDetailScreen extends ConsumerWidget {
  final String productId;

  const ProductDetailScreen({
    super.key,
    required this.productId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(productProvider(productId));
    final variantsAsync = ref.watch(productVariantsProvider(productId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
      ),
      body: productAsync.when(
        data: (product) {
          if (product == null) {
            return const ErrorState(
              message: 'Product not found',
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Product header
                Container(
                  padding: const EdgeInsets.all(24),
                  color: SaturdayColors.light,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Product icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: SaturdayColors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: SaturdayColors.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        product.name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: SaturdayColors.primaryDark,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        product.productCode,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                      ),
                      if (product.description != null && product.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          product.description!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ],
                  ),
                ),

                // Product information
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Product Information',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                        context,
                        'Shopify Product ID',
                        product.shopifyProductId,
                      ),
                      _buildInfoRow(
                        context,
                        'Shopify Handle',
                        product.shopifyProductHandle,
                      ),
                      _buildInfoRow(
                        context,
                        'Status',
                        product.isActive ? 'Active' : 'Inactive',
                        valueColor: product.isActive
                            ? SaturdayColors.success
                            : SaturdayColors.error,
                      ),
                      _buildInfoRow(
                        context,
                        'Created',
                        product.createdAt.friendlyDateTime,
                      ),
                      _buildInfoRow(
                        context,
                        'Last Updated',
                        product.updatedAt.friendlyDateTime,
                      ),
                      if (product.lastSyncedAt != null)
                        _buildInfoRow(
                          context,
                          'Last Synced',
                          product.lastSyncedAt!.friendlyDateTime,
                        ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Production Steps section
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Production Steps',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          // Configure button (only with manage_products permission)
                          Consumer(
                            builder: (context, ref, _) {
                              final hasPermission = ref.watch(
                                hasPermissionProvider('manage_products'),
                              );
                              return hasPermission.maybeWhen(
                                data: (allowed) => allowed
                                    ? TextButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ProductionStepsConfigScreen(
                                                product: product,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.settings),
                                        label: const Text('Configure'),
                                      )
                                    : const SizedBox.shrink(),
                                orElse: () => const SizedBox.shrink(),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Consumer(
                        builder: (context, ref, _) {
                          final stepsAsync = ref.watch(
                            productionStepsProvider(productId),
                          );
                          return stepsAsync.when(
                            data: (steps) {
                              if (steps.isEmpty) {
                                return Text(
                                  'No production steps configured',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: SaturdayColors.secondaryGrey,
                                      ),
                                );
                              }
                              return Column(
                                children: steps.map((step) {
                                  return ProductionStepItem(
                                    step: step,
                                    isEditable: false,
                                  );
                                }).toList(),
                              );
                            },
                            loading: () => const LoadingIndicator(
                              message: 'Loading production steps...',
                            ),
                            error: (error, stack) => Text(
                              'Failed to load production steps: $error',
                              style: const TextStyle(color: SaturdayColors.error),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Variants section
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Product Variants',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 16),
                      variantsAsync.when(
                        data: (variants) {
                          if (variants.isEmpty) {
                            return Text(
                              'No variants found',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: SaturdayColors.secondaryGrey,
                                  ),
                            );
                          }

                          return Column(
                            children: variants.map((variant) {
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              variant.getFormattedVariantName(),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                          ),
                                          Text(
                                            '\$${variant.price.toStringAsFixed(2)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  color: SaturdayColors.success,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'SKU: ${variant.sku}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: SaturdayColors.secondaryGrey,
                                            ),
                                      ),
                                      if (variant.option1Value != null) ...[
                                        const SizedBox(height: 8),
                                        _buildVariantOption(
                                          context,
                                          variant.option1Name ?? 'Option 1',
                                          variant.option1Value!,
                                        ),
                                      ],
                                      if (variant.option2Value != null) ...[
                                        const SizedBox(height: 4),
                                        _buildVariantOption(
                                          context,
                                          variant.option2Name ?? 'Option 2',
                                          variant.option2Value!,
                                        ),
                                      ],
                                      if (variant.option3Value != null) ...[
                                        const SizedBox(height: 4),
                                        _buildVariantOption(
                                          context,
                                          variant.option3Name ?? 'Option 3',
                                          variant.option3Value!,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                        loading: () => const LoadingIndicator(
                          message: 'Loading variants...',
                        ),
                        error: (error, stack) => Text(
                          'Failed to load variants: $error',
                          style: TextStyle(color: SaturdayColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const LoadingIndicator(message: 'Loading product...'),
        error: (error, stack) => ErrorState(
          message: 'Failed to load product',
          details: error.toString(),
          onRetry: () => ref.invalidate(productProvider(productId)),
        ),
      ),
    );
  }

  /// Build info row widget
  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontWeight: valueColor != null ? FontWeight.bold : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build variant option widget
  Widget _buildVariantOption(
    BuildContext context,
    String name,
    String value,
  ) {
    return Row(
      children: [
        Text(
          '$name: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}
