import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/supplier_parts_provider.dart';
import 'package:saturday_app/providers/suppliers_provider.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/screens/parts/supplier_form_screen.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

class SupplierDetailScreen extends ConsumerWidget {
  final String supplierId;

  const SupplierDetailScreen({super.key, required this.supplierId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplierAsync = ref.watch(supplierDetailProvider(supplierId));
    final partsAsync =
        ref.watch(supplierPartsForSupplierProvider(supplierId));
    final allPartsAsync = ref.watch(partsListProvider);

    return supplierAsync.when(
      data: (supplier) {
        if (supplier == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Supplier not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(supplier.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SupplierFormScreen(supplierId: supplierId),
                    ),
                  );
                  if (result == true) {
                    ref.invalidate(supplierDetailProvider(supplierId));
                    ref.invalidate(suppliersListProvider);
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => _deleteSupplier(context, ref),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(supplier.name,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold)),
                        if (supplier.website != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.link,
                                  size: 16,
                                  color: SaturdayColors.secondaryGrey),
                              const SizedBox(width: 4),
                              Text(supplier.website!,
                                  style: const TextStyle(color: Colors.blue)),
                            ],
                          ),
                        ],
                        if (supplier.notes != null &&
                            supplier.notes!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(supplier.notes!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Parts from this supplier',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                partsAsync.when(
                  data: (supplierParts) {
                    if (supplierParts.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No parts linked to this supplier',
                            style: TextStyle(
                                color: SaturdayColors.secondaryGrey)),
                      );
                    }

                    final allParts = allPartsAsync.valueOrNull ?? [];

                    return Column(
                      children: supplierParts.map((sp) {
                        final part = allParts
                            .where((p) => p.id == sp.partId)
                            .firstOrNull;
                        return ListTile(
                          title: Text(part?.name ?? 'Unknown Part'),
                          subtitle: Text('SKU: ${sp.supplierSku}'),
                          trailing: sp.isPreferred
                              ? const Icon(Icons.star,
                                  color: Colors.amber, size: 18)
                              : null,
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const LoadingIndicator(
                      message: 'Loading parts...'),
                  error: (e, _) => Text('Error: $e'),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const LoadingIndicator(message: 'Loading supplier...'),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          message: 'Failed to load supplier',
          details: error.toString(),
          onRetry: () => ref.invalidate(supplierDetailProvider(supplierId)),
        ),
      ),
    );
  }

  void _deleteSupplier(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Supplier'),
        content: const Text('Are you sure you want to delete this supplier?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SaturdayColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref
            .read(suppliersManagementProvider)
            .deleteSupplier(supplierId);
        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Failed to delete: $e'),
                backgroundColor: SaturdayColors.error),
          );
        }
      }
    }
  }
}
