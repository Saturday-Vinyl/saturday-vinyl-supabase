import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/inventory_provider.dart';
import 'package:saturday_app/screens/parts/inventory_dashboard_screen.dart';
import 'package:saturday_app/screens/parts/parts_list_screen.dart';
import 'package:saturday_app/screens/parts/receive_inventory_screen.dart';
import 'package:saturday_app/screens/parts/suppliers_list_screen.dart';

class PartsInventoryShell extends ConsumerStatefulWidget {
  const PartsInventoryShell({super.key});

  @override
  ConsumerState<PartsInventoryShell> createState() =>
      _PartsInventoryShellState();
}

class _PartsInventoryShellState extends ConsumerState<PartsInventoryShell>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lowStockCount = ref.watch(lowStockCountProvider).valueOrNull ?? 0;

    return Column(
      children: [
        Container(
          color: SaturdayColors.primaryDark,
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: SaturdayColors.light,
            indicatorColor: Colors.white,
            tabs: [
              Tab(
                icon: Badge(
                  isLabelVisible: lowStockCount > 0,
                  label: Text('$lowStockCount'),
                  child: const Icon(Icons.dashboard),
                ),
                text: 'Overview',
              ),
              const Tab(text: 'Parts', icon: Icon(Icons.widgets)),
              const Tab(text: 'Suppliers', icon: Icon(Icons.business)),
              const Tab(text: 'Receive', icon: Icon(Icons.add_shopping_cart)),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              InventoryDashboardScreen(),
              PartsListScreen(),
              SuppliersListScreen(),
              ReceiveInventoryScreen(),
            ],
          ),
        ),
      ],
    );
  }
}
