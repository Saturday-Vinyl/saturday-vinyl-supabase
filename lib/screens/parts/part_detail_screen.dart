import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/models/inventory_transaction.dart';
import 'package:saturday_app/models/sub_assembly_line.dart';
import 'package:saturday_app/providers/inventory_provider.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/providers/sub_assembly_provider.dart';
import 'package:saturday_app/models/supplier_part.dart';
import 'package:saturday_app/providers/supplier_parts_provider.dart';
import 'package:saturday_app/providers/suppliers_provider.dart';
import 'package:saturday_app/repositories/sub_assembly_repository.dart';
import 'package:saturday_app/repositories/supplier_parts_repository.dart';
import 'package:saturday_app/screens/parts/build_batch_screen.dart';
import 'package:saturday_app/screens/parts/import_bom_screen.dart';
import 'package:saturday_app/screens/parts/part_form_screen.dart';
import 'package:saturday_app/services/printer_service.dart';
import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

class PartDetailScreen extends ConsumerWidget {
  final String partId;

  const PartDetailScreen({super.key, required this.partId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partAsync = ref.watch(partDetailProvider(partId));
    final stockAsync = ref.watch(inventoryLevelProvider(partId));

    return partAsync.when(
      data: (part) {
        if (part == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Part not found')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(part.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.print),
                tooltip: 'Print Label',
                onPressed: () => _printLabel(context, part),
              ),
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Adjust Stock',
                onPressed: () => _adjustStock(context, ref, part),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Duplicate Part',
                onPressed: () => _duplicatePart(context, ref, part),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _editPart(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () => _deletePart(context, ref, part),
              ),
            ],
          ),
          body: _PartDetailBody(
            part: part,
            stockLevel: stockAsync.valueOrNull ?? 0.0,
            partId: partId,
          ),
          floatingActionButton: part.partType == PartType.subAssembly
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            BuildBatchScreen(partId: partId),
                      ),
                    );
                    if (result == true) {
                      ref.invalidate(inventoryLevelProvider(partId));
                      ref.invalidate(transactionHistoryProvider(partId));
                    }
                  },
                  backgroundColor: Colors.deepPurple,
                  icon: const Icon(Icons.build, color: Colors.white),
                  label: const Text('Build Batch',
                      style: TextStyle(color: Colors.white)),
                )
              : null,
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const LoadingIndicator(message: 'Loading part...'),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          message: 'Failed to load part',
          details: error.toString(),
          onRetry: () => ref.invalidate(partDetailProvider(partId)),
        ),
      ),
    );
  }

  void _printLabel(BuildContext context, Part part) {
    final qtyController = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Print Part Label'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${part.name} (${part.partNumber})',
                style: const TextStyle(color: SaturdayColors.secondaryGrey)),
            const SizedBox(height: 16),
            TextField(
              controller: qtyController,
              decoration: const InputDecoration(
                labelText: 'Number of labels',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final qty = int.tryParse(qtyController.text);
              if (qty == null || qty <= 0) return;

              Navigator.pop(context);

              try {
                final qrService = QRService();
                final printerService = PrinterService();

                // Generate QR code with part URI
                final qrData = await qrService.generateQRCode(
                  part.partNumber,
                  type: QRCodeType.part,
                  embedLogo: false,
                  size: 256,
                );

                // Generate and print labels
                for (var i = 0; i < qty; i++) {
                  final labelPdf = await printerService.generatePartLabel(
                    partName: part.name,
                    partNumber: part.partNumber,
                    category: part.category.displayName,
                    qrImageData: qrData,
                  );
                  await printerService.printLabel(labelPdf,
                      labelWidth: 1.25, labelHeight: 1.0);
                }

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Printed $qty label${qty > 1 ? 's' : ''}'),
                      backgroundColor: SaturdayColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Print failed: $e'),
                        backgroundColor: SaturdayColors.error),
                  );
                }
              }
            },
            child: const Text('Print'),
          ),
        ],
      ),
    );
  }

  void _adjustStock(BuildContext context, WidgetRef ref, Part part) {
    final qtyController = TextEditingController();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adjust Stock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${part.name} (${part.unitOfMeasure.displayName})',
                style: const TextStyle(color: SaturdayColors.secondaryGrey)),
            const SizedBox(height: 16),
            TextField(
              controller: qtyController,
              decoration: const InputDecoration(
                labelText: 'Adjustment quantity *',
                hintText: 'Positive to add, negative to remove',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason / Reference *',
                hintText: 'e.g., Cycle count correction',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final qty = double.tryParse(qtyController.text);
              if (qty == null || qty == 0 || reasonController.text.isEmpty) {
                return;
              }
              try {
                final userId =
                    SupabaseService.instance.client.auth.currentUser!.id;
                await ref.read(inventoryManagementProvider).adjust(
                      partId: partId,
                      quantity: qty,
                      reference: reasonController.text,
                      performedBy: userId,
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Stock adjusted'),
                        backgroundColor: SaturdayColors.success),
                  );
                }
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
            child: const Text('Adjust'),
          ),
        ],
      ),
    );
  }

  void _duplicatePart(BuildContext context, WidgetRef ref, Part part) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (context) => PartFormScreen(initialPart: part)),
    );
    if (result == true) {
      ref.invalidate(partsListProvider);
    }
  }

  void _editPart(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (context) => PartFormScreen(partId: partId)),
    );
    if (result == true) {
      ref.invalidate(partDetailProvider(partId));
      ref.invalidate(partsListProvider);
    }
  }

  void _deletePart(BuildContext context, WidgetRef ref, Part part) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Part'),
        content: Text('Are you sure you want to delete "${part.name}"?'),
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
        await ref.read(partsManagementProvider).deletePart(partId);
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

class _PartDetailBody extends ConsumerWidget {
  final Part part;
  final double stockLevel;
  final String partId;

  const _PartDetailBody({
    required this.part,
    required this.stockLevel,
    required this.partId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: part.partType == PartType.subAssembly ? 3 : 2,
      child: Column(
        children: [
          // Header card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(part.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: part.partNumber));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Copied "${part.partNumber}"'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(part.partNumber,
                                  style: const TextStyle(
                                      color: SaturdayColors.secondaryGrey)),
                              const SizedBox(width: 4),
                              const Icon(Icons.copy,
                                  size: 14,
                                  color: SaturdayColors.secondaryGrey),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _TypeChip(partType: part.partType),
                            Chip(label: Text(part.category.displayName)),
                            Chip(label: Text(part.unitOfMeasure.displayName)),
                            _UsageChip(partId: partId),
                          ],
                        ),
                        if (part.description != null &&
                            part.description!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(part.description!),
                        ],
                      ],
                    ),
                  ),
                  // Stock level with threshold coloring
                  Builder(builder: (context) {
                    final Color stockColor;
                    if (stockLevel <= 0) {
                      stockColor = SaturdayColors.error;
                    } else if (part.reorderThreshold != null &&
                        stockLevel <= part.reorderThreshold!) {
                      stockColor = Colors.orange;
                    } else {
                      stockColor = SaturdayColors.success;
                    }
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: stockColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            stockLevel % 1 == 0
                                ? '${stockLevel.toInt()}'
                                : stockLevel.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: stockColor,
                            ),
                          ),
                          Text(part.unitOfMeasure.displayName,
                              style: const TextStyle(
                                  color: SaturdayColors.secondaryGrey)),
                          const Text('on hand',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: SaturdayColors.secondaryGrey)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Tabs — sub-assemblies get an extra Components tab
          TabBar(
            tabs: [
              if (part.partType == PartType.subAssembly)
                const Tab(text: 'Components'),
              const Tab(text: 'Suppliers'),
              const Tab(text: 'History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                if (part.partType == PartType.subAssembly)
                  _ComponentsTab(partId: partId),
                _SuppliersTab(partId: partId),
                _HistoryTab(partId: partId),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final PartType partType;
  const _TypeChip({required this.partType});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (partType) {
      case PartType.rawMaterial:
        color = Colors.brown;
      case PartType.component:
        color = Colors.blue;
      case PartType.subAssembly:
        color = Colors.deepPurple;
      case PartType.pcbBlank:
        color = Colors.teal;
    }
    return Chip(
      label: Text(partType.displayName,
          style: TextStyle(color: color, fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _UsageChip extends ConsumerWidget {
  final String partId;
  const _UsageChip({required this.partId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usageAsync = ref.watch(subAssemblyUsageCountProvider(partId));

    return usageAsync.when(
      data: (count) {
        if (count > 0) {
          return Chip(
            avatar: const Icon(Icons.link, size: 14, color: Colors.green),
            label: Text(
              'Used in $count assembl${count == 1 ? 'y' : 'ies'}',
              style: const TextStyle(color: Colors.green, fontSize: 12),
            ),
            backgroundColor: Colors.green.withValues(alpha: 0.1),
            side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
            visualDensity: VisualDensity.compact,
          );
        }
        return Chip(
          avatar: Icon(Icons.link_off, size: 14, color: Colors.grey.shade500),
          label: Text('Not in use',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          backgroundColor: Colors.grey.withValues(alpha: 0.1),
          side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
          visualDensity: VisualDensity.compact,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _SuppliersTab extends ConsumerWidget {
  final String partId;
  const _SuppliersTab({required this.partId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplierPartsAsync = ref.watch(supplierPartsForPartProvider(partId));
    final suppliersAsync = ref.watch(suppliersListProvider);

    return supplierPartsAsync.when(
      data: (supplierParts) {
        final suppliers = suppliersAsync.valueOrNull ?? [];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Supplier Link'),
                  onPressed: () =>
                      _showAddSupplierDialog(context, ref, suppliers),
                ),
              ),
            ),
            Expanded(
              child: supplierParts.isEmpty
                  ? const Center(
                      child: Text('No suppliers linked',
                          style:
                              TextStyle(color: SaturdayColors.secondaryGrey)))
                  : ListView.builder(
                      itemCount: supplierParts.length,
                      itemBuilder: (context, index) {
                        final sp = supplierParts[index];
                        final supplier = suppliers
                            .where((s) => s.id == sp.supplierId)
                            .firstOrNull;
                        return ListTile(
                          onTap: () => _editSupplierPart(
                              context, ref, sp, suppliers),
                          leading: sp.isPreferred
                              ? const Icon(Icons.star,
                                  color: Colors.amber, size: 20)
                              : const Icon(Icons.business,
                                  color: SaturdayColors.secondaryGrey,
                                  size: 20),
                          title: Text(supplier?.name ?? 'Unknown Supplier'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Clipboard.setData(
                                      ClipboardData(text: sp.supplierSku));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Copied "${sp.supplierSku}"'),
                                      duration: const Duration(seconds: 1),
                                    ),
                                  );
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('SKU: ${sp.supplierSku}'),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.copy,
                                        size: 12,
                                        color: SaturdayColors.secondaryGrey),
                                  ],
                                ),
                              ),
                              if (sp.barcodeValue != null)
                                GestureDetector(
                                  onTap: () {
                                    Clipboard.setData(
                                        ClipboardData(text: sp.barcodeValue!));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                            'Copied "${sp.barcodeValue}"'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Barcode: ${sp.barcodeValue}'),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.copy,
                                          size: 12,
                                          color: SaturdayColors.secondaryGrey),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => _editCost(context, ref, sp),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: sp.unitCost != null
                                        ? SaturdayColors.success
                                            .withValues(alpha: 0.1)
                                        : SaturdayColors.secondaryGrey
                                            .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    sp.unitCost != null
                                        ? '\$${sp.unitCost!.toStringAsFixed(4)}'
                                        : 'Set cost',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: sp.unitCost != null
                                          ? SaturdayColors.success
                                          : SaturdayColors.secondaryGrey,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete_outline, size: 20),
                                onPressed: () async {
                                  await SupplierPartsRepository()
                                      .deleteSupplierPart(sp.id);
                                  ref.invalidate(
                                      supplierPartsForPartProvider(partId));
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
      loading: () => const LoadingIndicator(message: 'Loading suppliers...'),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  void _showAddSupplierDialog(BuildContext context, WidgetRef ref,
      List<dynamic> suppliers) {
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Create a supplier first'),
            backgroundColor: SaturdayColors.warning),
      );
      return;
    }

    String? selectedSupplierId;
    final skuController = TextEditingController();
    final barcodeController = TextEditingController();
    bool isPreferred = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Supplier Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: suppliers
                    .map((s) => DropdownMenuItem(
                        value: s.id as String, child: Text(s.name as String)))
                    .toList(),
                onChanged: (v) => selectedSupplierId = v,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: skuController,
                decoration: const InputDecoration(
                  labelText: 'Supplier SKU / Part Number *',
                  helperText: 'e.g. DigiKey PN, Amazon ASIN',
                  helperMaxLines: 1,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: barcodeController,
                decoration: const InputDecoration(
                  labelText: 'Barcode Value (optional)',
                  helperText: 'Physical barcode on packaging (e.g. Amazon FNSKU)',
                  helperMaxLines: 1,
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                title: const Text('Preferred Supplier'),
                value: isPreferred,
                onChanged: (v) =>
                    setDialogState(() => isPreferred = v ?? false),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (selectedSupplierId == null ||
                    skuController.text.isEmpty) {
                  return;
                }
                try {
                  await SupplierPartsRepository().createSupplierPart(
                    partId: partId,
                    supplierId: selectedSupplierId!,
                    supplierSku: skuController.text,
                    barcodeValue: barcodeController.text.isNotEmpty
                        ? barcodeController.text
                        : null,
                    isPreferred: isPreferred,
                  );
                  ref.invalidate(supplierPartsForPartProvider(partId));
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _editSupplierPart(BuildContext context, WidgetRef ref,
      SupplierPart sp, List<dynamic> suppliers) {
    String selectedSupplierId = sp.supplierId;
    final skuController = TextEditingController(text: sp.supplierSku);
    final barcodeController =
        TextEditingController(text: sp.barcodeValue ?? '');
    final costController = TextEditingController(
      text: sp.unitCost?.toStringAsFixed(4) ?? '',
    );
    final urlController = TextEditingController(text: sp.url ?? '');
    bool isPreferred = sp.isPreferred;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Supplier Link'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Supplier *'),
                  isExpanded: true,
                  initialValue: suppliers.any((s) => s.id == selectedSupplierId)
                      ? selectedSupplierId
                      : null,
                  items: suppliers
                      .map((s) => DropdownMenuItem(
                          value: s.id as String,
                          child: Text(s.name as String)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) selectedSupplierId = v;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: skuController,
                  decoration: const InputDecoration(
                    labelText: 'Supplier SKU / Part Number *',
                    helperText: 'e.g. DigiKey PN, Amazon ASIN',
                    helperMaxLines: 1,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: barcodeController,
                  decoration: const InputDecoration(
                    labelText: 'Barcode Value',
                    helperText:
                        'Physical barcode on packaging (e.g. Amazon FNSKU)',
                    helperMaxLines: 1,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: costController,
                  decoration: const InputDecoration(
                    labelText: 'Unit Cost (USD)',
                    prefixText: '\$ ',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  decoration:
                      const InputDecoration(labelText: 'Product URL'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Preferred Supplier'),
                  value: isPreferred,
                  onChanged: (v) =>
                      setDialogState(() => isPreferred = v ?? false),
                  contentPadding: EdgeInsets.zero,
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
                if (skuController.text.isEmpty) return;
                try {
                  // Update supplier link (including supplier change)
                  final updates = <String, dynamic>{
                    'supplier_id': selectedSupplierId,
                    'supplier_sku': skuController.text,
                    'is_preferred': isPreferred,
                  };
                  if (barcodeController.text.isNotEmpty) {
                    updates['barcode_value'] = barcodeController.text;
                  }
                  if (costController.text.isNotEmpty) {
                    updates['unit_cost'] =
                        double.tryParse(costController.text);
                  }
                  if (urlController.text.isNotEmpty) {
                    updates['url'] = urlController.text;
                  }

                  await SupabaseService.instance.client
                      .from('supplier_parts')
                      .update(updates)
                      .eq('id', sp.id);

                  ref.invalidate(supplierPartsForPartProvider(partId));
                  ref.invalidate(allPreferredCostsProvider);
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _editCost(BuildContext context, WidgetRef ref, SupplierPart sp) {
    final costController = TextEditingController(
      text: sp.unitCost?.toStringAsFixed(4) ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Unit Cost'),
        content: TextField(
          controller: costController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Unit Cost (USD)',
            prefixText: '\$ ',
            hintText: '0.0000',
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final cost = double.tryParse(costController.text);
              try {
                await SupplierPartsRepository().updateSupplierPart(
                  sp.id,
                  unitCost: cost,
                );
                ref.invalidate(supplierPartsForPartProvider(partId));
                ref.invalidate(allPreferredCostsProvider);
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ComponentsTab extends ConsumerWidget {
  final String partId;
  const _ComponentsTab({required this.partId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linesAsync = ref.watch(subAssemblyLinesProvider(partId));
    final allPartsAsync = ref.watch(partsListProvider);
    final costsAsync = ref.watch(allPreferredCostsProvider);

    return linesAsync.when(
      data: (lines) {
        final allParts = allPartsAsync.valueOrNull ?? [];
        final costs = costsAsync.valueOrNull ?? {};

        // Calculate total sub-assembly cost (exclude board-assembled)
        double? totalCost;
        bool allHaveCosts = lines.isNotEmpty;
        int boardAssembledCount = 0;
        for (final line in lines) {
          if (line.isBoardAssembled) {
            boardAssembledCount++;
            continue;
          }
          final unitCost = costs[line.childPartId];
          if (unitCost != null) {
            totalCost = (totalCost ?? 0) + (unitCost * line.quantity);
          } else {
            allHaveCosts = false;
          }
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('${lines.length} components',
                          style: const TextStyle(
                              color: SaturdayColors.secondaryGrey)),
                      if (boardAssembledCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$boardAssembledCount board-assembled',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.purple,
                            ),
                          ),
                        ),
                      ],
                      if (totalCost != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                SaturdayColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${allHaveCosts ? '' : '~'}\$${totalCost.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: SaturdayColors.success,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Import BOM'),
                        onPressed: () async {
                          final partName = allParts
                                  .where((p) => p.id == partId)
                                  .firstOrNull
                                  ?.name ??
                              'Sub-Assembly';
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ImportBomScreen(
                                parentPartId: partId,
                                parentPartName: partName,
                              ),
                            ),
                          );
                          if (result == true) {
                            ref.invalidate(subAssemblyLinesProvider(partId));
                          }
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Component'),
                        onPressed: () =>
                            _addComponent(context, ref, allParts),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: lines.isEmpty
                  ? const Center(
                      child: Text(
                        'No components. Add components or import from EagleCAD.',
                        style: TextStyle(color: SaturdayColors.secondaryGrey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: lines.length,
                      itemBuilder: (context, index) {
                        final line = lines[index];
                        final childPart = allParts
                            .where((p) => p.id == line.childPartId)
                            .firstOrNull;

                        final lineCost = line.isBoardAssembled
                            ? null
                            : costs[line.childPartId];
                        final lineTotal = lineCost != null
                            ? lineCost * line.quantity
                            : null;

                        // Check if this child part has any supplier parts
                        final hasSupplierParts = ref
                                .watch(supplierPartsForPartProvider(
                                    line.childPartId))
                                .valueOrNull
                                ?.isNotEmpty ??
                            true; // default true to avoid false warnings while loading

                        return ListTile(
                          onTap: () => _editComponent(
                              context, ref, line, allParts),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: line.isBoardAssembled
                                ? Colors.purple.withValues(alpha: 0.1)
                                : Colors.blue.withValues(alpha: 0.1),
                            child: line.isBoardAssembled
                                ? const Icon(Icons.precision_manufacturing,
                                    size: 14, color: Colors.purple)
                                : Text(
                                    line.referenceDesignator ?? '#',
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.blue),
                                  ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  childPart?.name ?? 'Unknown Part',
                                  style: TextStyle(
                                    decoration: line.isBoardAssembled
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: line.isBoardAssembled
                                        ? SaturdayColors.secondaryGrey
                                        : null,
                                  ),
                                ),
                              ),
                              if (!hasSupplierParts)
                                Tooltip(
                                  message:
                                      'No supplier part number linked.\nAdd a supplier SKU, or update the Eagle BOM\nwith DIGIKEY_PART, AMAZON_PART, etc.',
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(Icons.warning_amber,
                                        size: 16, color: Colors.orange.shade700),
                                  ),
                                ),
                              if (line.isBoardAssembled)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.purple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text('Board',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.purple)),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            'Qty: ${line.quantity % 1 == 0 ? line.quantity.toInt() : line.quantity}'
                            '${line.referenceDesignator != null ? '  •  ${line.referenceDesignator}' : ''}'
                            '${lineTotal != null ? '  •  \$${lineTotal.toStringAsFixed(4)}' : ''}'
                            '${line.notes != null && line.notes!.isNotEmpty ? '  •  ${line.notes}' : ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              await SubAssemblyRepository()
                                  .deleteSubAssemblyLine(line.id);
                              ref.invalidate(
                                  subAssemblyLinesProvider(partId));
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
      loading: () =>
          const LoadingIndicator(message: 'Loading components...'),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  void _editComponent(BuildContext screenContext, WidgetRef ref,
      SubAssemblyLine line, List<Part> allParts) {
    final candidates = allParts
        .where((p) => p.id != partId && p.partType != PartType.rawMaterial)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    String selectedChildPartId = line.childPartId;
    final currentPart = allParts.where((p) => p.id == line.childPartId).firstOrNull;
    final searchController = TextEditingController(
      text: currentPart != null
          ? '${currentPart.name} (${currentPart.partNumber})'
          : '',
    );
    final qtyController = TextEditingController(
      text: line.quantity % 1 == 0
          ? line.quantity.toInt().toString()
          : line.quantity.toString(),
    );
    final refDesController =
        TextEditingController(text: line.referenceDesignator ?? '');
    final notesController = TextEditingController(text: line.notes ?? '');
    bool isBoardAssembled = line.isBoardAssembled;

    final hasSupplierParts = ref
            .read(supplierPartsForPartProvider(line.childPartId))
            .valueOrNull
            ?.isNotEmpty ??
        true;

    showDialog(
      context: screenContext,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit Component'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Autocomplete<Part>(
                        initialValue: searchController.value,
                        optionsBuilder: (textEditingValue) {
                          final query = textEditingValue.text.toLowerCase();
                          if (query.isEmpty) return candidates;
                          return candidates.where((p) =>
                              p.name.toLowerCase().contains(query) ||
                              p.partNumber.toLowerCase().contains(query));
                        },
                        displayStringForOption: (p) =>
                            '${p.name} (${p.partNumber})',
                        fieldViewBuilder: (context, controller, focusNode,
                            onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Part *',
                              suffixIcon: Icon(Icons.search, size: 20),
                            ),
                          );
                        },
                        onSelected: (part) {
                          setDialogState(() => selectedChildPartId = part.id);
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 20),
                      tooltip: 'Open part details',
                      onPressed: () {
                        Navigator.push(
                          screenContext,
                          MaterialPageRoute(
                            builder: (_) => PartDetailScreen(
                                partId: selectedChildPartId),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                if (!hasSupplierParts) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber,
                            size: 16, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No supplier part number. Add DIGIKEY_PART, AMAZON_PART, etc. to the Eagle BOM.',
                            style: TextStyle(fontSize: 12, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: qtyController,
                  decoration: const InputDecoration(labelText: 'Quantity *'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: refDesController,
                  decoration: const InputDecoration(
                      labelText: 'Reference Designator',
                      hintText: 'e.g. R1, C3'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Assembled by board maker'),
                  subtitle: const Text(
                    'Does not require our inventory',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: isBoardAssembled,
                  onChanged: (v) =>
                      setDialogState(() => isBoardAssembled = v ?? false),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final qty = double.tryParse(qtyController.text);
                if (qty == null || qty <= 0) return;

                final partChanged =
                    selectedChildPartId != line.childPartId;
                final oldChildPartId = line.childPartId;

                try {
                  await SubAssemblyRepository().updateSubAssemblyLine(
                    line.id,
                    childPartId: partChanged ? selectedChildPartId : null,
                    quantity: qty,
                    referenceDesignator: refDesController.text.isNotEmpty
                        ? refDesController.text
                        : null,
                    notes: notesController.text.isNotEmpty
                        ? notesController.text
                        : null,
                    isBoardAssembled: isBoardAssembled,
                  );
                  ref.invalidate(subAssemblyLinesProvider(partId));
                  if (dialogContext.mounted) Navigator.pop(dialogContext);

                  // If part was reassigned, offer to delete the old part
                  if (partChanged && screenContext.mounted) {
                    // Use a short delay so the edit dialog fully closes first
                    Future.delayed(const Duration(milliseconds: 200), () {
                      if (screenContext.mounted) {
                        _promptDeleteOldPart(
                            screenContext, ref, oldChildPartId, allParts);
                      }
                    });
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                          content: Text('Error: $e'),
                          backgroundColor: SaturdayColors.error),
                    );
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promptDeleteOldPart(BuildContext screenContext,
      WidgetRef ref, String oldPartId, List<Part> allParts) async {
    final oldPart = allParts.where((p) => p.id == oldPartId).firstOrNull;
    if (oldPart == null) return;

    // Check usage: other sub-assemblies and inventory
    final usageCount =
        await SubAssemblyRepository().countUsagesAsChild(oldPartId);
    final stockLevel =
        await ref.read(inventoryRepositoryProvider).getInventoryLevel(oldPartId);

    // Build context message
    final warnings = <String>[];
    if (usageCount > 0) {
      warnings.add('Used in $usageCount sub-assembl${usageCount == 1 ? 'y' : 'ies'}');
    }
    if (stockLevel > 0) {
      warnings.add('Has $stockLevel in inventory');
    }

    if (!screenContext.mounted) return;

    showDialog(
      context: screenContext,
      builder: (context) => AlertDialog(
        title: const Text('Delete old part?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${oldPart.name}" is no longer assigned to this sub-assembly.'),
            const SizedBox(height: 8),
            if (warnings.isEmpty)
              const Text('It is not used elsewhere and has no inventory.',
                  style: TextStyle(color: SaturdayColors.secondaryGrey,
                      fontSize: 13))
            else ...[
              const Text('Before deleting, note:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              ...warnings.map((w) => Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            size: 14, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(w, style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: SaturdayColors.error),
            onPressed: () async {
              try {
                await ref
                    .read(partsManagementProvider)
                    .deletePart(oldPartId);
                ref.invalidate(partsListProvider);
                if (context.mounted) Navigator.pop(context);
                if (screenContext.mounted) {
                  ScaffoldMessenger.of(screenContext).showSnackBar(
                    SnackBar(
                      content: Text('Deleted "${oldPart.name}"'),
                      backgroundColor: SaturdayColors.success,
                    ),
                  );
                }
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _addComponent(
      BuildContext context, WidgetRef ref, List<Part> allParts) {
    // Filter to components and other sub-assemblies (not self)
    final candidates = allParts
        .where((p) => p.id != partId && p.partType != PartType.rawMaterial)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No component parts available. Create component parts first.'),
            backgroundColor: SaturdayColors.warning),
      );
      return;
    }

    String? selectedPartId;
    final qtyController = TextEditingController(text: '1');
    final refDesController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Component'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<Part>(
                optionsBuilder: (textEditingValue) {
                  final query = textEditingValue.text.toLowerCase();
                  if (query.isEmpty) return candidates;
                  return candidates.where((p) =>
                      p.name.toLowerCase().contains(query) ||
                      p.partNumber.toLowerCase().contains(query));
                },
                displayStringForOption: (p) =>
                    '${p.name} (${p.partNumber})',
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Component *',
                      suffixIcon: Icon(Icons.search, size: 20),
                    ),
                  );
                },
                onSelected: (part) => selectedPartId = part.id,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                decoration: const InputDecoration(labelText: 'Quantity *'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: refDesController,
                decoration: const InputDecoration(
                  labelText: 'Reference Designator',
                  hintText: 'e.g., R1, C3, U2',
                ),
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
                await SubAssemblyRepository().createSubAssemblyLine(
                  parentPartId: partId,
                  childPartId: selectedPartId!,
                  quantity: qty,
                  referenceDesignator: refDesController.text.isNotEmpty
                      ? refDesController.text
                      : null,
                  notes: notesController.text.isNotEmpty
                      ? notesController.text
                      : null,
                );
                ref.invalidate(subAssemblyLinesProvider(partId));
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
}

class _HistoryTab extends ConsumerWidget {
  final String partId;
  const _HistoryTab({required this.partId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(transactionHistoryProvider(partId));

    return historyAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Center(
            child: Text('No transactions yet',
                style: TextStyle(color: SaturdayColors.secondaryGrey)),
          );
        }
        return ListView.builder(
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final tx = transactions[index];
            return ListTile(
              leading: _txIcon(tx.transactionType),
              title: Text(tx.transactionType.displayName),
              subtitle: Text(tx.reference ?? ''),
              trailing: Text(
                '${tx.quantity > 0 ? '+' : ''}${tx.quantity % 1 == 0 ? tx.quantity.toInt() : tx.quantity.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color:
                      tx.quantity > 0 ? SaturdayColors.success : SaturdayColors.error,
                ),
              ),
            );
          },
        );
      },
      loading: () => const LoadingIndicator(message: 'Loading history...'),
      error: (error, _) => Center(child: Text('Error: $error')),
    );
  }

  Widget _txIcon(TransactionType type) {
    switch (type) {
      case TransactionType.receive:
        return const Icon(Icons.add_circle, color: SaturdayColors.success);
      case TransactionType.consume:
        return const Icon(Icons.remove_circle, color: SaturdayColors.error);
      case TransactionType.build:
        return const Icon(Icons.build, color: Colors.deepPurple);
      case TransactionType.adjust:
        return const Icon(Icons.tune, color: Colors.orange);
      case TransactionType.returnStock:
        return const Icon(Icons.undo, color: Colors.blue);
    }
  }
}
