import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/product_variant.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/screens/products/variant_form_dialog.dart';

/// Screen displaying all variants for a product
class ProductVariantsScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductVariantsScreen({
    super.key,
    required this.productId,
  });

  @override
  ConsumerState<ProductVariantsScreen> createState() => _ProductVariantsScreenState();
}

class _ProductVariantsScreenState extends ConsumerState<ProductVariantsScreen> {
  String _searchQuery = '';
  bool _showInactiveVariants = false;

  @override
  Widget build(BuildContext context) {
    final productAsync = ref.watch(productProvider(widget.productId));
    final variantsAsync = ref.watch(productVariantsProvider(widget.productId));

    return Scaffold(
      appBar: AppBar(
        title: productAsync.when(
          data: (product) => Text(product?.name ?? 'Product Variants'),
          loading: () => const Text('Product Variants'),
          error: (_, __) => const Text('Product Variants'),
        ),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_showInactiveVariants ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                _showInactiveVariants = !_showInactiveVariants;
              });
            },
            tooltip: _showInactiveVariants ? 'Hide inactive' : 'Show inactive',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddVariantDialog(context),
        backgroundColor: SaturdayColors.primaryDark,
        icon: const Icon(Icons.add),
        label: const Text('Add Variant'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search variants...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),

          // Variants list
          Expanded(
            child: variantsAsync.when(
              data: (variants) {
                if (variants.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: SaturdayColors.secondaryGrey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No variants found',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: SaturdayColors.secondaryGrey,
                              ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showAddVariantDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Add First Variant'),
                        ),
                      ],
                    ),
                  );
                }

                // Filter variants
                final filteredVariants = variants.where((variant) {
                  // Search filter
                  if (_searchQuery.isNotEmpty) {
                    final matchesSearch = variant.name.toLowerCase().contains(_searchQuery) ||
                        variant.sku.toLowerCase().contains(_searchQuery) ||
                        (variant.option1Value?.toLowerCase().contains(_searchQuery) ?? false) ||
                        (variant.option2Value?.toLowerCase().contains(_searchQuery) ?? false) ||
                        (variant.option3Value?.toLowerCase().contains(_searchQuery) ?? false);

                    if (!matchesSearch) return false;
                  }

                  // Active filter (only applies if _showInactiveVariants is false)
                  if (!_showInactiveVariants && !variant.isActive) {
                    return false;
                  }

                  return true;
                }).toList();

                if (filteredVariants.isEmpty) {
                  return Center(
                    child: Text(
                      'No variants match your search',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredVariants.length,
                  itemBuilder: (context, index) {
                    final variant = filteredVariants[index];
                    return _buildVariantCard(context, variant);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error loading variants: $error'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantCard(BuildContext context, ProductVariant variant) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showEditVariantDialog(context, variant),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      variant.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            decoration: variant.isActive ? null : TextDecoration.lineThrough,
                          ),
                    ),
                  ),
                  if (!variant.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'INACTIVE',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // SKU and Price
              Row(
                children: [
                  Chip(
                    label: Text(
                      'SKU: ${variant.sku}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: SaturdayColors.light,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      '\$${variant.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: SaturdayColors.success.withValues(alpha: 0.1),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),

              // Options
              if (variant.option1Value != null || variant.option2Value != null || variant.option3Value != null) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (variant.option1Value != null)
                      _buildOptionChip(
                        variant.option1Name ?? 'Option 1',
                        variant.option1Value!,
                      ),
                    if (variant.option2Value != null)
                      _buildOptionChip(
                        variant.option2Name ?? 'Option 2',
                        variant.option2Value!,
                      ),
                    if (variant.option3Value != null)
                      _buildOptionChip(
                        variant.option3Name ?? 'Option 3',
                        variant.option3Value!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionChip(String optionName, String optionValue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: SaturdayColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: SaturdayColors.info.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        '$optionName: $optionValue',
        style: TextStyle(
          fontSize: 12,
          color: SaturdayColors.primaryDark,
        ),
      ),
    );
  }

  Future<void> _showAddVariantDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => VariantFormDialog(
        productId: widget.productId,
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Variant created successfully'),
          backgroundColor: SaturdayColors.success,
        ),
      );
    }
  }

  Future<void> _showEditVariantDialog(BuildContext context, ProductVariant variant) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => VariantFormDialog(
        productId: widget.productId,
        variant: variant,
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Variant updated successfully'),
          backgroundColor: SaturdayColors.success,
        ),
      );
    }
  }
}
