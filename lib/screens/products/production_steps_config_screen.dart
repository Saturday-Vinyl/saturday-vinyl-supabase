import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/production_step_provider.dart';
import 'package:saturday_app/screens/products/production_step_form_screen.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/products/production_step_item.dart';

/// Screen for configuring production steps (admin/manage_products only)
class ProductionStepsConfigScreen extends ConsumerWidget {
  final Product product;

  const ProductionStepsConfigScreen({
    super.key,
    required this.product,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPermission = ref.watch(hasPermissionProvider('manage_products'));
    final stepsAsync = ref.watch(productionStepsProvider(product.id));
    final localSteps = ref.watch(localProductionStepsProvider(product.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Configure Steps: ${product.name}'),
      ),
      body: hasPermission.when(
        data: (allowed) {
          if (!allowed) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 64,
                    color: SaturdayColors.error,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Access Denied',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: SaturdayColors.primaryDark,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'You need manage_products permission to configure production steps.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: SaturdayColors.secondaryGrey),
                  ),
                ],
              ),
            );
          }

          return stepsAsync.when(
            data: (steps) {
              // Use local steps if available (for optimistic updates), otherwise use server data
              final displaySteps = localSteps ?? steps;

              if (displaySteps.isEmpty) {
                return EmptyState(
                  icon: Icons.list_alt,
                  message: 'No production steps configured.\nAdd your first step to get started.',
                  actionLabel: 'Add Step',
                  onAction: () => _navigateToAddStep(context, ref),
                );
              }

              return Column(
                children: [
                  // Instructions banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: SaturdayColors.light,
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: SaturdayColors.info,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Long-press and drag to reorder steps',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Reorderable list
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.only(bottom: 80),
                      itemCount: displaySteps.length,
                      onReorder: (oldIndex, newIndex) {
                        _handleReorder(context, ref, displaySteps, oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final step = displaySteps[index];
                        return ProductionStepItem(
                          key: ValueKey(step.id),
                          step: step,
                          isEditable: true,
                          showDragHandle: true,
                          reorderIndex: index,
                          onEdit: () => _navigateToEditStep(context, ref, step),
                          onDelete: () => _handleDelete(context, ref, step),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
            loading: () => const LoadingIndicator(message: 'Loading production steps...'),
            error: (error, stack) => ErrorState(
              message: 'Failed to load production steps',
              details: error.toString(),
              onRetry: () => ref.invalidate(productionStepsProvider(product.id)),
            ),
          );
        },
        loading: () => const LoadingIndicator(),
        error: (error, stack) => ErrorState(
          message: 'Failed to check permissions',
          details: error.toString(),
        ),
      ),
      floatingActionButton: hasPermission.maybeWhen(
        data: (allowed) => allowed
            ? FloatingActionButton.extended(
                onPressed: () => _navigateToAddStep(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add Step'),
                backgroundColor: SaturdayColors.primaryDark,
                foregroundColor: SaturdayColors.light,
              )
            : null,
        orElse: () => null,
      ),
    );
  }

  /// Navigate to add step screen
  Future<void> _navigateToAddStep(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductionStepFormScreen(product: product),
      ),
    );

    // Refresh list if step was added
    if (result == true && context.mounted) {
      ref.invalidate(productionStepsProvider(product.id));
    }
  }

  /// Navigate to edit step screen
  Future<void> _navigateToEditStep(
    BuildContext context,
    WidgetRef ref,
    step,
  ) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductionStepFormScreen(
          product: product,
          step: step,
        ),
      ),
    );

    // Refresh list if step was edited
    if (result == true && context.mounted) {
      ref.invalidate(productionStepsProvider(product.id));
    }
  }

  /// Handle step deletion with confirmation
  Future<void> _handleDelete(BuildContext context, WidgetRef ref, step) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Production Step'),
        content: Text('Are you sure you want to delete "${step.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: SaturdayColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        final management = ref.read(productionStepManagementProvider);
        await management.deleteStep(step.id, product.id);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Production step deleted'),
              backgroundColor: SaturdayColors.success,
            ),
          );
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete step: $error'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    }
  }

  /// Handle step reordering
  Future<void> _handleReorder(
    BuildContext context,
    WidgetRef ref,
    List steps,
    int oldIndex,
    int newIndex,
  ) async {
    // Adjust newIndex if moving down
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    // Create new ordered list
    final reorderedSteps = List.from(steps);
    final step = reorderedSteps.removeAt(oldIndex);
    reorderedSteps.insert(newIndex, step);

    // Update step orders
    final updatedSteps = <ProductionStep>[];
    for (int i = 0; i < reorderedSteps.length; i++) {
      final s = reorderedSteps[i] as ProductionStep;
      updatedSteps.add(s.copyWith(stepOrder: i + 1));
    }

    // Optimistically update local state immediately
    ref.read(localProductionStepsProvider(product.id).notifier).state = updatedSteps;

    // Extract step IDs in new order
    final stepIds = reorderedSteps.map((s) => s.id as String).toList();

    try {
      final management = ref.read(productionStepManagementProvider);
      await management.reorderSteps(product.id, stepIds);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Steps reordered'),
            backgroundColor: SaturdayColors.success,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (error) {
      // Revert optimistic update on error
      ref.read(localProductionStepsProvider(product.id).notifier).state = null;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reorder steps: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }
}
