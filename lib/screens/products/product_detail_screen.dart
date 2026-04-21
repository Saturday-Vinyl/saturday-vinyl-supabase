import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/providers/bom_provider.dart';
import 'package:saturday_app/providers/inventory_provider.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/providers/supplier_parts_provider.dart';
import 'package:saturday_app/providers/production_step_provider.dart';
import 'package:saturday_app/screens/products/production_steps_config_screen.dart';
import 'package:saturday_app/utils/extensions.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/providers/image_slot_provider.dart';
import 'package:saturday_app/screens/products/image_slots/image_slot_selection_screen.dart';
import 'package:saturday_app/widgets/products/device_type_assignment_dialog.dart';
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

                // Device Types section
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Device Types',
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
                                        onPressed: () => _showDeviceTypeAssignmentDialog(
                                          context,
                                          ref,
                                          product,
                                        ),
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
                          final deviceTypesAsync = ref.watch(
                            productDeviceTypesProvider(productId),
                          );
                          return deviceTypesAsync.when(
                            data: (deviceTypes) {
                              if (deviceTypes.isEmpty) {
                                return Text(
                                  'No device types assigned',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: SaturdayColors.secondaryGrey,
                                      ),
                                );
                              }
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: deviceTypes.map((pdt) {
                                  return Chip(
                                    avatar: CircleAvatar(
                                      backgroundColor: SaturdayColors.primaryDark,
                                      child: Text(
                                        '${pdt.quantity}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    label: Text(pdt.deviceType.name),
                                    backgroundColor: SaturdayColors.info.withValues(alpha: 0.1),
                                  );
                                }).toList(),
                              );
                            },
                            loading: () => const LoadingIndicator(
                              message: 'Loading device types...',
                            ),
                            error: (error, stack) => Text(
                              'Failed to load device types: $error',
                              style: const TextStyle(color: SaturdayColors.error),
                            ),
                          );
                        },
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

                // BOM section
                _BomSection(productId: productId),

                const Divider(height: 1),

                // Image Slots section
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Image Slots',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      ImageSlotSelectionScreen(
                                    productId: productId,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit),
                            label: const Text('Configure'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Consumer(
                        builder: (context, ref, _) {
                          final slotsAsync = ref.watch(
                            productImageSlotsProvider(productId),
                          );
                          return slotsAsync.when(
                            data: (slots) {
                              if (slots.isEmpty) {
                                return Text(
                                  'No image slots configured',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: SaturdayColors.secondaryGrey,
                                      ),
                                );
                              }
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: slots.map((slot) {
                                  return Chip(
                                    avatar: const Icon(
                                      Icons.photo_size_select_actual,
                                      size: 16,
                                    ),
                                    label: Text('${slot.angle} / ${slot.capacity}'),
                                    backgroundColor:
                                        SaturdayColors.success.withValues(alpha: 0.1),
                                  );
                                }).toList(),
                              );
                            },
                            loading: () => const LoadingIndicator(
                              message: 'Loading image slots...',
                            ),
                            error: (error, stack) => Text(
                              'Failed to load image slots: $error',
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

  /// Show dialog to configure device type assignments
  void _showDeviceTypeAssignmentDialog(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) {
    showDialog(
      context: context,
      builder: (context) => DeviceTypeAssignmentDialog(
        productId: product.id,
        productName: product.name,
      ),
    );
  }
}

/// BOM section widget for product detail
class _BomSection extends ConsumerWidget {
  final String productId;
  const _BomSection({required this.productId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bomAsync = ref.watch(productBomProvider(productId));
    final allPartsAsync = ref.watch(partsListProvider);
    final levelsAsync = ref.watch(allInventoryLevelsProvider);
    final stepsAsync = ref.watch(productionStepsProvider(productId));
    final costsAsync = ref.watch(allPreferredCostsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Bill of Materials',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _checkAvailability(context, ref),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Check Availability'),
                  ),
                  TextButton.icon(
                    onPressed: () => _addBomLine(context, ref),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Part'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          bomAsync.when(
            data: (bomLines) {
              if (bomLines.isEmpty) {
                return Text(
                  'No parts in BOM. Add parts to define what\'s needed to build this product.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                );
              }

              final allParts = allPartsAsync.valueOrNull ?? [];
              final levels = levelsAsync.valueOrNull ?? {};
              final steps = stepsAsync.valueOrNull ?? [];
              final costs = costsAsync.valueOrNull ?? {};

              // Calculate total BOM cost
              double? totalBomCost;
              bool allHaveCosts = bomLines.isNotEmpty;
              for (final line in bomLines) {
                final unitCost = costs[line.partId];
                if (unitCost != null) {
                  totalBomCost =
                      (totalBomCost ?? 0) + (unitCost * line.quantity);
                } else {
                  allHaveCosts = false;
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (totalBomCost != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: SaturdayColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.attach_money,
                                size: 18, color: SaturdayColors.success),
                            const SizedBox(width: 4),
                            Text(
                              'Estimated BOM cost: ${allHaveCosts ? '' : '~'}\$${totalBomCost.toStringAsFixed(2)} per unit',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: SaturdayColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ...bomLines.map((line) {
                  final part = allParts.where((p) => p.id == line.partId).firstOrNull;
                  final step = line.productionStepId != null
                      ? steps.where((s) => s.id == line.productionStepId).firstOrNull
                      : null;
                  final stock = levels[line.partId] ?? 0.0;
                  final needed = line.quantity;
                  final lineCost = costs[line.partId];
                  final lineTotal =
                      lineCost != null ? lineCost * line.quantity : null;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        stock >= needed ? Icons.check_circle : Icons.warning,
                        color: stock >= needed
                            ? SaturdayColors.success
                            : Colors.orange,
                        size: 20,
                      ),
                      title: Text(part?.name ?? 'Unknown Part'),
                      subtitle: Text(
                        '${line.quantity % 1 == 0 ? line.quantity.toInt() : line.quantity} ${part?.unitOfMeasure.displayName ?? ''}'
                        '${lineTotal != null ? ' • \$${lineTotal.toStringAsFixed(2)}' : ''}'
                        '${step != null ? ' • Step: ${step.name}' : ''}'
                        '${line.notes != null && line.notes!.isNotEmpty ? ' • ${line.notes}' : ''}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${stock % 1 == 0 ? stock.toInt() : stock.toStringAsFixed(1)} avail',
                            style: TextStyle(
                              fontSize: 12,
                              color: stock >= needed
                                  ? SaturdayColors.success
                                  : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Remove from BOM?'),
                                  content: Text(
                                      'Remove ${part?.name ?? 'this part'} from the BOM?'),
                                  actions: [
                                    TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Cancel')),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: TextButton.styleFrom(
                                          foregroundColor: SaturdayColors.error),
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await ref.read(bomManagementProvider).deleteBomLine(
                                      line.id,
                                      productId: productId,
                                    );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                ],
              );
            },
            loading: () => const LoadingIndicator(message: 'Loading BOM...'),
            error: (error, stack) => Text(
              'Failed to load BOM: $error',
              style: const TextStyle(color: SaturdayColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _addBomLine(BuildContext context, WidgetRef ref) {
    final allPartsAsync = ref.read(partsListProvider);
    final stepsAsync = ref.read(productionStepsProvider(productId));
    final allParts = allPartsAsync.valueOrNull ?? [];
    final steps = stepsAsync.valueOrNull ?? [];

    if (allParts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Create parts first before adding to BOM'),
            backgroundColor: SaturdayColors.warning),
      );
      return;
    }

    String? selectedPartId;
    String? selectedStepId;
    final qtyController = TextEditingController(text: '1');
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Part to BOM'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Part *'),
                isExpanded: true,
                items: allParts
                    .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.name} (${p.partNumber})')))
                    .toList(),
                onChanged: (v) => selectedPartId = v,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                decoration: const InputDecoration(labelText: 'Quantity *'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                    labelText: 'Production Step (optional)'),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('None (product-level)')),
                  ...steps.map((s) =>
                      DropdownMenuItem(value: s.id, child: Text(s.name))),
                ],
                onChanged: (v) => selectedStepId = v,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration:
                    const InputDecoration(labelText: 'Notes (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (selectedPartId == null || qtyController.text.isEmpty) return;
              final qty = double.tryParse(qtyController.text);
              if (qty == null || qty <= 0) return;

              try {
                await ref.read(bomManagementProvider).createBomLine(
                      productId: productId,
                      partId: selectedPartId!,
                      productionStepId: selectedStepId,
                      quantity: qty,
                      notes: notesController.text.isNotEmpty
                          ? notesController.text
                          : null,
                    );
                if (context.mounted) Navigator.pop(context);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: SaturdayColors.error),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _checkAvailability(BuildContext context, WidgetRef ref) {
    final bomAsync = ref.read(productBomProvider(productId));
    final allPartsAsync = ref.read(partsListProvider);
    final levelsAsync = ref.read(allInventoryLevelsProvider);

    final bomLines = bomAsync.valueOrNull ?? [];
    final allParts = allPartsAsync.valueOrNull ?? [];
    final levels = levelsAsync.valueOrNull ?? {};

    if (bomLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('BOM is empty')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('BOM Availability Check'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: bomLines.map((line) {
              final part =
                  allParts.where((p) => p.id == line.partId).firstOrNull;
              final stock = levels[line.partId] ?? 0.0;
              final sufficient = stock >= line.quantity;

              return ListTile(
                dense: true,
                leading: Icon(
                  sufficient ? Icons.check_circle : Icons.warning,
                  color: sufficient ? SaturdayColors.success : Colors.orange,
                  size: 18,
                ),
                title: Text(part?.name ?? 'Unknown'),
                subtitle: Text(
                    'Need: ${line.quantity % 1 == 0 ? line.quantity.toInt() : line.quantity}  •  Have: ${stock % 1 == 0 ? stock.toInt() : stock.toStringAsFixed(1)}'),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }
}
