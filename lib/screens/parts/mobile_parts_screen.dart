import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/providers/inventory_provider.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/screens/parts/part_detail_screen.dart';
import 'package:saturday_app/screens/parts/build_batch_screen.dart';
import 'package:saturday_app/screens/parts/receive_inventory_screen.dart';

class MobilePartsScreen extends ConsumerStatefulWidget {
  const MobilePartsScreen({super.key});

  @override
  ConsumerState<MobilePartsScreen> createState() => _MobilePartsScreenState();
}

class _MobilePartsScreenState extends ConsumerState<MobilePartsScreen> {
  bool _showSearch = false;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parts & Inventory'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: _showSearch ? _buildSearchView() : _buildHomeView(),
    );
  }

  Widget _buildHomeView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.add_shopping_cart,
                  label: 'Receive',
                  color: SaturdayColors.success,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ReceiveInventoryScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.search,
                  label: 'Look Up',
                  color: SaturdayColors.primaryDark,
                  onTap: () => setState(() => _showSearch = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickActionCard(
                  icon: Icons.build,
                  label: 'Build',
                  color: Colors.orange,
                  onTap: () => _showBuildPicker(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text('Low Stock Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: _buildLowStockSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildLowStockSection() {
    final lowStockAsync = ref.watch(lowStockPartsProvider);

    return lowStockAsync.when(
      data: (lowStock) {
        if (lowStock.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle,
                    size: 48, color: SaturdayColors.success),
                SizedBox(height: 8),
                Text('All parts sufficiently stocked',
                    style: TextStyle(color: SaturdayColors.success)),
              ],
            ),
          );
        }
        return ListView.builder(
          itemCount: lowStock.length,
          itemBuilder: (context, index) {
            final ls = lowStock[index];
            final isZero = ls.quantityOnHand <= 0;
            return ListTile(
              leading: Icon(
                isZero ? Icons.error : Icons.warning_amber,
                color: isZero ? SaturdayColors.error : Colors.orange,
              ),
              title: Text(ls.part.name),
              subtitle: Text(ls.part.partNumber),
              trailing: Text(
                '${ls.quantityOnHand % 1 == 0 ? ls.quantityOnHand.toInt() : ls.quantityOnHand.toStringAsFixed(1)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isZero ? SaturdayColors.error : Colors.orange,
                ),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      PartDetailScreen(partId: ls.part.id),
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  void _showBuildPicker(BuildContext context) {
    final partsAsync = ref.read(partsByTypeProvider(PartType.subAssembly));
    partsAsync.when(
      data: (subAssemblies) {
        if (subAssemblies.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('No sub-assembly parts defined yet'),
                backgroundColor: SaturdayColors.warning),
          );
          return;
        }
        showModalBottomSheet(
          context: context,
          builder: (context) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Select Sub-Assembly to Build',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              ...subAssemblies.map((part) => ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x1A673AB7),
                      child: Icon(Icons.developer_board,
                          color: Colors.deepPurple, size: 20),
                    ),
                    title: Text(part.name),
                    subtitle: Text(part.partNumber),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              BuildBatchScreen(partId: part.id),
                        ),
                      );
                    },
                  )),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
      loading: () {},
      error: (_, __) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Failed to load sub-assemblies'),
              backgroundColor: SaturdayColors.error),
        );
      },
    );
  }

  Widget _buildSearchView() {
    final partsAsync = _searchQuery.isNotEmpty
        ? ref.watch(partSearchProvider(_searchQuery))
        : ref.watch(partsListProvider);
    final levelsAsync = ref.watch(allInventoryLevelsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _showSearch = false;
                    _searchQuery = '';
                  });
                },
              ),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search parts...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: partsAsync.when(
            data: (parts) {
              if (parts.isEmpty) {
                return const Center(
                  child: Text('No parts found',
                      style: TextStyle(color: SaturdayColors.secondaryGrey)),
                );
              }
              final levels = levelsAsync.valueOrNull ?? {};
              return ListView.builder(
                itemCount: parts.length,
                itemBuilder: (context, index) {
                  final part = parts[index];
                  final stock = levels[part.id] ?? 0.0;
                  return ListTile(
                    leading: _partTypeIcon(part.partType),
                    title: Text(part.name),
                    subtitle: Text(part.partNumber),
                    trailing: Text(
                      '${stock % 1 == 0 ? stock.toInt() : stock.toStringAsFixed(2)} ${part.unitOfMeasure.displayName}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: stock > 0
                            ? SaturdayColors.success
                            : SaturdayColors.error,
                      ),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            PartDetailScreen(partId: part.id),
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }

  Widget _partTypeIcon(PartType type) {
    switch (type) {
      case PartType.rawMaterial:
        return const CircleAvatar(
          backgroundColor: Color(0x1A795548),
          child: Icon(Icons.forest, color: Colors.brown, size: 20),
        );
      case PartType.component:
        return const CircleAvatar(
          backgroundColor: Color(0x1A2196F3),
          child: Icon(Icons.memory, color: Colors.blue, size: 20),
        );
      case PartType.subAssembly:
        return const CircleAvatar(
          backgroundColor: Color(0x1A673AB7),
          child:
              Icon(Icons.developer_board, color: Colors.deepPurple, size: 20),
        );
      case PartType.pcbBlank:
        return const CircleAvatar(
          backgroundColor: Color(0x1A009688),
          child: Icon(Icons.grid_on, color: Colors.teal, size: 20),
        );
    }
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Column(
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
