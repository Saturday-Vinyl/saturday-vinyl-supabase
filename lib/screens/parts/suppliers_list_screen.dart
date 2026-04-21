import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/suppliers_provider.dart';
import 'package:saturday_app/screens/parts/supplier_detail_screen.dart';
import 'package:saturday_app/screens/parts/supplier_form_screen.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

class SuppliersListScreen extends ConsumerWidget {
  const SuppliersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(suppliersListProvider);

    return Scaffold(
      body: suppliersAsync.when(
        data: (suppliers) {
          if (suppliers.isEmpty) {
            return EmptyState(
              icon: Icons.business_outlined,
              message:
                  'No suppliers yet.\nAdd your first supplier to get started.',
              actionLabel: 'Add Supplier',
              onAction: () => _createSupplier(context, ref),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(suppliersListProvider),
            child: ListView.builder(
              itemCount: suppliers.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: OutlinedButton.icon(
                      onPressed: () => _createSupplier(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Supplier'),
                    ),
                  );
                }
                final supplier = suppliers[index - 1];
                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: SaturdayColors.light,
                    child: Icon(Icons.business,
                        color: SaturdayColors.primaryDark, size: 20),
                  ),
                  title: Text(supplier.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: supplier.website != null
                      ? Text(supplier.website!)
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SupplierDetailScreen(supplierId: supplier.id),
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () =>
            const LoadingIndicator(message: 'Loading suppliers...'),
        error: (error, stack) => ErrorState(
          message: 'Failed to load suppliers',
          details: error.toString(),
          onRetry: () => ref.invalidate(suppliersListProvider),
        ),
      ),
    );
  }

  void _createSupplier(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const SupplierFormScreen()),
    );
    if (result == true) {
      ref.invalidate(suppliersListProvider);
    }
  }
}
