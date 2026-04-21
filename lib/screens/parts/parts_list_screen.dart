import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/providers/inventory_provider.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/providers/sub_assembly_provider.dart';
import 'package:saturday_app/repositories/inventory_repository.dart';
import 'package:saturday_app/repositories/parts_repository.dart';
import 'package:saturday_app/repositories/sub_assembly_repository.dart';
import 'package:saturday_app/repositories/supplier_parts_repository.dart';
import 'package:saturday_app/screens/parts/part_detail_screen.dart';
import 'package:saturday_app/screens/parts/part_form_screen.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

/// Screen displaying searchable, filterable list of parts
class PartsListScreen extends ConsumerStatefulWidget {
  const PartsListScreen({super.key});

  @override
  ConsumerState<PartsListScreen> createState() => _PartsListScreenState();
}

class _PartsListScreenState extends ConsumerState<PartsListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  PartType? _typeFilter;
  PartCategory? _categoryFilter;

  // Selection mode for merge
  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleSelection(String partId) {
    setState(() {
      if (_selectedIds.contains(partId)) {
        _selectedIds.remove(partId);
      } else {
        _selectedIds.add(partId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final partsAsync = _searchQuery.isNotEmpty
        ? ref.watch(partSearchProvider(_searchQuery))
        : ref.watch(partsListProvider);
    final levelsAsync = ref.watch(allInventoryLevelsProvider);
    final boardAssembledOnly =
        ref.watch(boardAssembledOnlyPartIdsProvider).valueOrNull ?? {};

    return Scaffold(
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search parts by name or part number...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),

          // Add button + Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (!_selectMode) ...[
                  OutlinedButton.icon(
                    onPressed: () => _createPart(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Part'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _toggleSelectMode,
                    icon: const Icon(Icons.merge, size: 18),
                    label: const Text('Merge'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: _selectedIds.length >= 2
                        ? () => _showMergeDialog(context, partsAsync)
                        : null,
                    icon: const Icon(Icons.merge, size: 18),
                    label: Text('Merge ${_selectedIds.length} parts'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _toggleSelectMode,
                    child: const Text('Cancel'),
                  ),
                ],
                const SizedBox(width: 12),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        const Text('Type: ',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  FilterChip(
                    label: const Text('All'),
                    selected: _typeFilter == null,
                    onSelected: (_) => setState(() => _typeFilter = null),
                  ),
                  const SizedBox(width: 4),
                  ...PartType.values.map((type) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(type.displayName),
                          selected: _typeFilter == type,
                          onSelected: (_) => setState(
                              () => _typeFilter = _typeFilter == type ? null : type),
                        ),
                      )),
                  const SizedBox(width: 12),
                  const Text('Category: ',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  ...PartCategory.values.map((cat) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: FilterChip(
                          label: Text(cat.displayName),
                          selected: _categoryFilter == cat,
                          onSelected: (_) => setState(() =>
                              _categoryFilter = _categoryFilter == cat ? null : cat),
                        ),
                      )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Selection hint
          if (_selectMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Select 2 or more parts to merge into a single entry.',
                        style: TextStyle(fontSize: 13, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_selectMode) const SizedBox(height: 8),

          // Parts list
          Expanded(
            child: partsAsync.when(
              data: (parts) {
                // Hide parts that are only used as board-assembled components
                var filtered = boardAssembledOnly.isEmpty
                    ? parts
                    : parts
                        .where((p) => !boardAssembledOnly.contains(p.id))
                        .toList();
                if (_typeFilter != null) {
                  filtered = filtered
                      .where((p) => p.partType == _typeFilter)
                      .toList();
                }
                if (_categoryFilter != null) {
                  filtered = filtered
                      .where((p) => p.category == _categoryFilter)
                      .toList();
                }

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.widgets_outlined,
                    message: parts.isEmpty
                        ? 'No parts yet.\nCreate your first part to get started.'
                        : 'No parts match your filters.',
                    actionLabel: parts.isEmpty ? 'Create Part' : null,
                    onAction: parts.isEmpty ? () => _createPart(context) : null,
                  );
                }

                final levels = levelsAsync.valueOrNull ?? {};

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(partsListProvider);
                    ref.invalidate(allInventoryLevelsProvider);
                  },
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final part = filtered[index];
                      final stock = levels[part.id] ?? 0.0;
                      if (_selectMode) {
                        return _SelectablePartTile(
                          part: part,
                          stockLevel: stock,
                          selected: _selectedIds.contains(part.id),
                          onToggle: () => _toggleSelection(part.id),
                        );
                      }
                      return _PartListTile(
                        part: part,
                        stockLevel: stock,
                        onTap: () => _navigateToDetail(context, part.id),
                      );
                    },
                  ),
                );
              },
              loading: () =>
                  const LoadingIndicator(message: 'Loading parts...'),
              error: (error, stack) => ErrorState(
                message: 'Failed to load parts',
                details: error.toString(),
                onRetry: () => ref.invalidate(partsListProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMergeDialog(
      BuildContext context, AsyncValue<List<Part>> partsAsync) {
    final allParts = partsAsync.valueOrNull ?? [];
    final selected =
        allParts.where((p) => _selectedIds.contains(p.id)).toList();
    if (selected.length < 2) return;

    // Default to first selected part's name/number
    final nameController = TextEditingController(text: selected.first.name);
    final numberController =
        TextEditingController(text: selected.first.partNumber);
    var primaryIndex = 0;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Merge Parts'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Merging ${selected.length} parts into one. '
                    'Supplier links, sub-assembly references, and inventory '
                    'history will be consolidated.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  const Text('Select primary part to keep:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  // ignore: deprecated_member_use
                  ...List.generate(selected.length, (i) {
                    final p = selected[i];
                    final isSelected = i == primaryIndex;
                    return ListTile(
                      leading: Radio<int>(
                        value: i,
                        // ignore: deprecated_member_use
                        groupValue: primaryIndex,
                        // ignore: deprecated_member_use
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(() {
                            primaryIndex = v;
                            nameController.text = selected[v].name;
                            numberController.text = selected[v].partNumber;
                          });
                        },
                      ),
                      title: Text(p.name,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                      subtitle: Text(p.partNumber,
                          style: const TextStyle(fontSize: 12)),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        setDialogState(() {
                          primaryIndex = i;
                          nameController.text = selected[i].name;
                          numberController.text = selected[i].partNumber;
                        });
                      },
                    );
                  }),
                  const Divider(),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Merged Part Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: numberController,
                    decoration: const InputDecoration(
                      labelText: 'Merged Part Number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final number = numberController.text.trim();
                if (name.isEmpty || number.isEmpty) return;

                Navigator.pop(dialogContext);
                await _executeMerge(
                  selected,
                  primaryIndex,
                  name,
                  number,
                );
              },
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeMerge(
    List<Part> selected,
    int primaryIndex,
    String name,
    String partNumber,
  ) async {
    final primary = selected[primaryIndex];
    final others = [
      for (var i = 0; i < selected.length; i++)
        if (i != primaryIndex) selected[i],
    ];

    try {
      final partsRepo = PartsRepository();
      final supplierPartsRepo = SupplierPartsRepository();
      final subAssemblyRepo = SubAssemblyRepository();
      final inventoryRepo = InventoryRepository();

      // Update the primary part's name/number
      await partsRepo.updatePart(primary.id,
          name: name, partNumber: partNumber);

      // Reassign all references from each "other" part to the primary
      for (final other in others) {
        await supplierPartsRepo.reassignSupplierParts(other.id, primary.id);
        await subAssemblyRepo.reassignChildPart(other.id, primary.id);
        await inventoryRepo.reassignTransactions(other.id, primary.id);
        // Soft-delete the merged-away part
        await partsRepo.deletePart(other.id);
      }

      AppLogger.info(
          'Merged ${others.length} parts into ${primary.id} ($name)');

      // Refresh and exit select mode
      ref.invalidate(partsListProvider);
      if (_searchQuery.isNotEmpty) {
        ref.invalidate(partSearchProvider(_searchQuery));
      }
      ref.invalidate(allInventoryLevelsProvider);
      setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Merged ${selected.length} parts into "$name"'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Merge failed', e, StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Merge failed: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  void _createPart(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const PartFormScreen()),
    );
    if (result == true) {
      ref.invalidate(partsListProvider);
    }
  }

  void _navigateToDetail(BuildContext context, String partId) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => PartDetailScreen(partId: partId)),
    );
  }
}

class _SelectablePartTile extends StatelessWidget {
  final Part part;
  final double stockLevel;
  final bool selected;
  final VoidCallback onToggle;

  const _SelectablePartTile({
    required this.part,
    required this.stockLevel,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onToggle,
      leading: Checkbox(
        value: selected,
        onChanged: (_) => onToggle(),
      ),
      title:
          Text(part.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(part.partNumber),
      trailing: Chip(
        label: Text(part.category.displayName),
        visualDensity: VisualDensity.compact,
      ),
      selected: selected,
      selectedTileColor: Colors.blue.withValues(alpha: 0.05),
    );
  }
}

class _PartListTile extends StatelessWidget {
  final Part part;
  final double stockLevel;
  final VoidCallback onTap;

  const _PartListTile({
    required this.part,
    required this.stockLevel,
    required this.onTap,
  });

  Color get _stockColor {
    if (stockLevel <= 0) return SaturdayColors.error;
    if (part.reorderThreshold != null && stockLevel <= part.reorderThreshold!) {
      return Colors.orange;
    }
    return SaturdayColors.success;
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: _buildTypeIcon(),
      title: Text(part.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(part.partNumber),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Chip(
            label: Text(part.category.displayName),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stockLevel % 1 == 0 ? stockLevel.toInt() : stockLevel.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _stockColor,
                ),
              ),
              Text(
                part.unitOfMeasure.displayName,
                style: const TextStyle(
                    fontSize: 11, color: SaturdayColors.secondaryGrey),
              ),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }

  Widget _buildTypeIcon() {
    IconData icon;
    Color color;
    switch (part.partType) {
      case PartType.rawMaterial:
        icon = Icons.forest;
        color = Colors.brown;
      case PartType.component:
        icon = Icons.memory;
        color = Colors.blue;
      case PartType.subAssembly:
        icon = Icons.developer_board;
        color = Colors.deepPurple;
      case PartType.pcbBlank:
        icon = Icons.grid_on;
        color = Colors.teal;
    }
    return CircleAvatar(
      backgroundColor: color.withValues(alpha: 0.1),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
