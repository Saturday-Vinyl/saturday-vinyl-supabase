import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/providers/inventory_provider.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/providers/sub_assembly_provider.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:uuid/uuid.dart';

class BuildBatchScreen extends ConsumerStatefulWidget {
  final String partId;

  const BuildBatchScreen({super.key, required this.partId});

  @override
  ConsumerState<BuildBatchScreen> createState() => _BuildBatchScreenState();
}

class _BuildBatchScreenState extends ConsumerState<BuildBatchScreen> {
  final _qtyController = TextEditingController(text: '1');
  int _buildQty = 1;
  bool _isBuilding = false;
  bool _built = false;
  double? _newStockLevel;

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final partAsync = ref.watch(partDetailProvider(widget.partId));
    final linesAsync = ref.watch(subAssemblyLinesProvider(widget.partId));
    final allPartsAsync = ref.watch(partsListProvider);
    final levelsAsync = ref.watch(allInventoryLevelsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Build Sub-Assembly'),
      ),
      body: partAsync.when(
        data: (part) {
          if (part == null) {
            return const Center(child: Text('Part not found'));
          }
          if (_built) {
            return _buildSuccessView(part);
          }
          return linesAsync.when(
            data: (lines) {
              final allParts = allPartsAsync.valueOrNull ?? [];
              final levels = levelsAsync.valueOrNull ?? {};
              return _buildMainView(part, lines, allParts, levels);
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error loading components: $e')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildSuccessView(Part part) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle,
                  size: 64, color: SaturdayColors.success),
              const SizedBox(height: 16),
              Text('Built $_buildQty x ${part.name}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_newStockLevel != null)
                Text(
                  'New stock: ${_newStockLevel! % 1 == 0 ? _newStockLevel!.toInt() : _newStockLevel!.toStringAsFixed(2)} ${part.unitOfMeasure.displayName}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: SaturdayColors.success),
                ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Done'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => setState(() {
                      _built = false;
                      _qtyController.text = '1';
                      _buildQty = 1;
                    }),
                    child: const Text('Build More'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainView(
    Part part,
    List<dynamic> lines,
    List<Part> allParts,
    Map<String, double> levels,
  ) {
    final currentStock = levels[widget.partId] ?? 0.0;

    if (lines.isEmpty || lines.every((l) => l.isBoardAssembled)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber,
                size: 48, color: SaturdayColors.warning),
            const SizedBox(height: 12),
            const Text('No components defined for this sub-assembly.'),
            const SizedBox(height: 8),
            const Text('Add components on the part detail screen first.',
                style: TextStyle(color: SaturdayColors.secondaryGrey)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
    }

    // Filter out board-assembled components (handled by PCB maker, not our inventory)
    final buildableLines = lines.where((l) => !l.isBoardAssembled).toList();

    // Calculate requirements
    final requirements = <_ComponentRequirement>[];
    bool anySufficient = true;
    for (final line in buildableLines) {
      final childPart =
          allParts.where((p) => p.id == line.childPartId).firstOrNull;
      final needed = line.quantity * _buildQty;
      final onHand = levels[line.childPartId] ?? 0.0;
      final sufficient = onHand >= needed;
      if (!sufficient) anySufficient = false;
      requirements.add(_ComponentRequirement(
        childPartId: line.childPartId,
        name: childPart?.name ?? 'Unknown',
        unitOfMeasure: childPart?.unitOfMeasure.displayName ?? 'each',
        neededPerUnit: line.quantity,
        needed: needed,
        onHand: onHand,
        sufficient: sufficient,
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Part info
          Card(
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
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(part.partNumber,
                            style: const TextStyle(
                                color: SaturdayColors.secondaryGrey)),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        currentStock % 1 == 0
                            ? '${currentStock.toInt()}'
                            : currentStock.toStringAsFixed(2),
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      Text('${part.unitOfMeasure.displayName} on hand',
                          style: const TextStyle(
                              fontSize: 12,
                              color: SaturdayColors.secondaryGrey)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Build quantity
          Row(
            children: [
              const Text('Build Quantity:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _buildQty > 1
                    ? () => setState(() {
                          _buildQty--;
                          _qtyController.text = '$_buildQty';
                        })
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _qtyController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (v) {
                    final qty = int.tryParse(v);
                    if (qty != null && qty > 0) {
                      setState(() => _buildQty = qty);
                    }
                  },
                ),
              ),
              IconButton(
                onPressed: () => setState(() {
                  _buildQty++;
                  _qtyController.text = '$_buildQty';
                }),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Components table
          const Text('Required Components',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          Card(
            child: DataTable(
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('Component')),
                DataColumn(label: Text('Needed'), numeric: true),
                DataColumn(label: Text('On Hand'), numeric: true),
                DataColumn(label: Text('OK')),
              ],
              rows: requirements.map((r) {
                return DataRow(cells: [
                  DataCell(Text(r.name, overflow: TextOverflow.ellipsis)),
                  DataCell(Text(
                      '${r.needed % 1 == 0 ? r.needed.toInt() : r.needed.toStringAsFixed(2)}')),
                  DataCell(Text(
                      '${r.onHand % 1 == 0 ? r.onHand.toInt() : r.onHand.toStringAsFixed(2)}')),
                  DataCell(Icon(
                    r.sufficient ? Icons.check_circle : Icons.warning,
                    color: r.sufficient
                        ? SaturdayColors.success
                        : Colors.orange,
                    size: 20,
                  )),
                ]);
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Warning if insufficient
          if (!anySufficient || requirements.any((r) => !r.sufficient))
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Some components have insufficient stock. '
                      'You can still proceed, but inventory will go negative.',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),

          // Build button
          FilledButton.icon(
            onPressed: _isBuilding ? null : () => _executeBuild(requirements),
            icon: _isBuilding
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.build),
            label: Text(_isBuilding
                ? 'Building...'
                : 'Build $_buildQty ${part.unitOfMeasure.displayName}'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeBuild(List<_ComponentRequirement> requirements) async {
    // Confirm if any insufficient
    if (requirements.any((r) => !r.sufficient)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Insufficient Stock'),
          content: const Text(
              'Some components don\'t have enough stock. '
              'Proceeding will result in negative inventory for those parts. Continue?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange),
              child: const Text('Build Anyway'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _isBuilding = true);

    try {
      final userId =
          SupabaseService.instance.client.auth.currentUser!.id;
      final batchId = const Uuid().v4();
      final repo = ref.read(inventoryRepositoryProvider);

      // Build the batch of transactions
      final transactions = <Map<String, dynamic>>[];

      // Consume each component (negative quantity)
      for (final r in requirements) {
        transactions.add({
          'part_id': r.childPartId,
          'transaction_type': 'consume',
          'quantity': -r.needed,
          'build_batch_id': batchId,
          'reference': 'Build batch: $_buildQty x ${widget.partId}',
          'performed_by': userId,
        });
      }

      // Produce the sub-assembly (positive quantity)
      transactions.add({
        'part_id': widget.partId,
        'transaction_type': 'build',
        'quantity': _buildQty.toDouble(),
        'build_batch_id': batchId,
        'reference': 'Built $_buildQty units',
        'performed_by': userId,
      });

      await repo.createTransactions(transactions);

      // Invalidate all affected inventory levels
      ref.invalidate(allInventoryLevelsProvider);
      ref.invalidate(inventoryLevelProvider(widget.partId));
      ref.invalidate(transactionHistoryProvider(widget.partId));
      for (final r in requirements) {
        ref.invalidate(inventoryLevelProvider(r.childPartId));
        ref.invalidate(transactionHistoryProvider(r.childPartId));
      }

      // Get updated stock level
      final newLevel = await repo.getInventoryLevel(widget.partId);

      if (mounted) {
        setState(() {
          _isBuilding = false;
          _built = true;
          _newStockLevel = newLevel;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBuilding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Build failed: $e'),
              backgroundColor: SaturdayColors.error),
        );
      }
    }
  }
}

class _ComponentRequirement {
  final String childPartId;
  final String name;
  final String unitOfMeasure;
  final double neededPerUnit;
  final double needed;
  final double onHand;
  final bool sufficient;

  _ComponentRequirement({
    required this.childPartId,
    required this.name,
    required this.unitOfMeasure,
    required this.neededPerUnit,
    required this.needed,
    required this.onHand,
    required this.sufficient,
  });
}
