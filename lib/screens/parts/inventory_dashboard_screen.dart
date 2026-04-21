import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/inventory_provider.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/providers/supplier_parts_provider.dart';
import 'package:saturday_app/screens/parts/part_detail_screen.dart';
import 'package:saturday_app/screens/parts/receive_inventory_screen.dart';

/// Inventory overview dashboard with at-a-glance stats and low-stock alerts.
class InventoryDashboardScreen extends ConsumerWidget {
  const InventoryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partsAsync = ref.watch(partsListProvider);
    final levelsAsync = ref.watch(allInventoryLevelsProvider);
    final lowStockAsync = ref.watch(lowStockPartsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          partsAsync.when(
            data: (parts) {
              final levels = levelsAsync.valueOrNull ?? {};
              final totalParts = parts.where((p) => p.isActive).length;
              final trackedParts =
                  parts.where((p) => p.isActive && levels.containsKey(p.id)).length;
              final lowCount = lowStockAsync.valueOrNull?.length ?? 0;

              return Row(
                children: [
                  _StatCard(
                    icon: Icons.widgets,
                    label: 'Total Parts',
                    value: '$totalParts',
                    color: SaturdayColors.primaryDark,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    icon: Icons.inventory,
                    label: 'With Stock',
                    value: '$trackedParts',
                    color: SaturdayColors.success,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    icon: Icons.warning_amber,
                    label: 'Low Stock',
                    value: '$lowCount',
                    color: lowCount > 0 ? SaturdayColors.error : SaturdayColors.success,
                  ),
                ],
              );
            },
            loading: () => const SizedBox(height: 80),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),

          // Quick actions
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ReceiveInventoryScreen(),
                  ),
                ),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Receive Inventory'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => _exportCsv(context, ref),
                icon: const Icon(Icons.download),
                label: const Text('Export CSV'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Low stock alerts
          const Text('Low Stock Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          lowStockAsync.when(
            data: (lowStock) {
              if (lowStock.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: SaturdayColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: SaturdayColors.success),
                      SizedBox(width: 12),
                      Text('All parts are sufficiently stocked',
                          style: TextStyle(color: SaturdayColors.success)),
                    ],
                  ),
                );
              }

              return Card(
                child: Column(
                  children: lowStock.map((ls) {
                    final isZero = ls.quantityOnHand <= 0;
                    return ListTile(
                      leading: Icon(
                        isZero ? Icons.error : Icons.warning_amber,
                        color: isZero ? SaturdayColors.error : Colors.orange,
                      ),
                      title: Text(ls.part.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(ls.part.partNumber),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${ls.quantityOnHand % 1 == 0 ? ls.quantityOnHand.toInt() : ls.quantityOnHand.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isZero
                                  ? SaturdayColors.error
                                  : Colors.orange,
                            ),
                          ),
                          if (ls.part.reorderThreshold != null)
                            Text(
                              'threshold: ${ls.part.reorderThreshold! % 1 == 0 ? ls.part.reorderThreshold!.toInt() : ls.part.reorderThreshold!.toStringAsFixed(1)}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: SaturdayColors.secondaryGrey),
                            ),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              PartDetailScreen(partId: ls.part.id),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }
}

Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
  try {
    final parts = ref.read(partsListProvider).valueOrNull ?? [];
    final levels = ref.read(allInventoryLevelsProvider).valueOrNull ?? {};
    final costs = ref.read(allPreferredCostsProvider).valueOrNull ?? {};

    if (parts.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No parts to export')),
        );
      }
      return;
    }

    final buf = StringBuffer();
    buf.writeln(
        'Part Number,Name,Type,Category,Unit of Measure,Stock On Hand,Reorder Threshold,Unit Cost (USD),Stock Value (USD)');

    for (final part in parts) {
      if (!part.isActive) continue;
      final stock = levels[part.id] ?? 0.0;
      final unitCost = costs[part.id];
      final stockValue =
          unitCost != null ? (stock * unitCost).toStringAsFixed(2) : '';

      // Escape CSV fields that might contain commas
      String esc(String s) =>
          s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;

      buf.writeln(
        '${esc(part.partNumber)},${esc(part.name)},${part.partType.displayName},${part.category.displayName},${part.unitOfMeasure.displayName},'
        '${stock % 1 == 0 ? stock.toInt() : stock.toStringAsFixed(2)},'
        '${part.reorderThreshold != null ? (part.reorderThreshold! % 1 == 0 ? part.reorderThreshold!.toInt() : part.reorderThreshold!.toStringAsFixed(1)) : ''},'
        '${unitCost?.toStringAsFixed(4) ?? ''},'
        '$stockValue',
      );
    }

    final csvContent = buf.toString();

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Parts Inventory',
      fileName: 'parts_inventory_${DateTime.now().toIso8601String().split('T').first}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (savePath != null) {
      await File(savePath).writeAsString(csvContent);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to $savePath'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: SaturdayColors.error),
      );
    }
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(value,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: SaturdayColors.secondaryGrey)),
            ],
          ),
        ),
      ),
    );
  }
}
