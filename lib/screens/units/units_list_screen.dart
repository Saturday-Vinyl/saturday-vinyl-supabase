import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/models/unit_filter.dart';
import 'package:saturday_app/models/unit_list_item.dart';
import 'package:saturday_app/providers/unit_dashboard_provider.dart';
import 'package:saturday_app/screens/units/unit_detail_screen.dart';
import 'package:saturday_app/widgets/units/unit_filter_sheet.dart';
import 'package:saturday_app/widgets/units/unit_list_tile.dart';

/// Screen showing all units with filtering and real-time updates
class UnitsListScreen extends ConsumerStatefulWidget {
  const UnitsListScreen({super.key});

  @override
  ConsumerState<UnitsListScreen> createState() => _UnitsListScreenState();
}

class _UnitsListScreenState extends ConsumerState<UnitsListScreen> {
  final _searchController = TextEditingController();
  bool _isRealtimeInitialized = false;
  List<String>? _lastInitializedUnitIds;

  @override
  void initState() {
    super.initState();
    // Start realtime subscriptions after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeRealtime();
    });
  }

  void _initializeRealtime() {
    if (!_isRealtimeInitialized) {
      ref.read(unitRealtimeUpdatesProvider.notifier).startListening();
      _isRealtimeInitialized = true;
    }
  }

  /// Initialize realtime state only when units data actually changes
  void _initializeFromUnitsIfNeeded(List<UnitListItem> units) {
    // Build a list of unit IDs to compare
    final currentUnitIds = units.map((u) => u.id).toList()..sort();

    // Only initialize if the unit list has changed
    if (_lastInitializedUnitIds == null ||
        !_listEquals(_lastInitializedUnitIds!, currentUnitIds)) {
      _lastInitializedUnitIds = currentUnitIds;
      ref.read(unitRealtimeUpdatesProvider.notifier).initializeFromUnits(units);
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _searchController.dispose();
    // Stop realtime subscriptions
    ref.read(unitRealtimeUpdatesProvider.notifier).stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unitsAsync = ref.watch(unitDashboardProvider);
    final filter = ref.watch(unitFilterProvider);
    final realtimeUpdates = ref.watch(unitRealtimeUpdatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Units'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          // Filter button with badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter',
                onPressed: () => _showFilterSheet(context),
              ),
              if (filter.hasActiveFilters)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: SaturdayColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${filter.activeFilterCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(unitDashboardProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(),

          // Filter chips
          if (filter.hasActiveFilters) _buildActiveFilterChips(filter),

          // Unit list
          Expanded(
            child: unitsAsync.when(
              data: (units) {
                // Initialize realtime state only when unit list changes
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _initializeFromUnitsIfNeeded(units);
                });

                return _buildUnitList(units, realtimeUpdates);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _buildErrorState(error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search by serial number or name...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(unitFilterProvider.notifier).setSearchQuery(null);
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Colors.grey.shade100,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (value) {
          ref.read(unitFilterProvider.notifier).setSearchQuery(
                value.isEmpty ? null : value,
              );
        },
      ),
    );
  }

  Widget _buildActiveFilterChips(UnitFilter filter) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (filter.status != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(_getStatusLabel(filter.status!)),
                onSelected: (_) =>
                    ref.read(unitFilterProvider.notifier).setStatus(null),
                onDeleted: () =>
                    ref.read(unitFilterProvider.notifier).setStatus(null),
                selected: true,
                selectedColor: SaturdayColors.info.withValues(alpha: 0.2),
              ),
            ),
          if (filter.isConnected != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(filter.isConnected! ? 'Connected' : 'Disconnected'),
                onSelected: (_) =>
                    ref.read(unitFilterProvider.notifier).setConnected(null),
                onDeleted: () =>
                    ref.read(unitFilterProvider.notifier).setConnected(null),
                selected: true,
                selectedColor: filter.isConnected!
                    ? SaturdayColors.success.withValues(alpha: 0.2)
                    : SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
              ),
            ),
          // Clear all button
          TextButton.icon(
            icon: const Icon(Icons.clear_all, size: 18),
            label: const Text('Clear all'),
            onPressed: () {
              ref.read(unitFilterProvider.notifier).reset();
              _searchController.clear();
            },
            style: TextButton.styleFrom(
              foregroundColor: SaturdayColors.secondaryGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitList(
      List<UnitListItem> units, Map<String, UnitListItem> realtimeUpdates) {
    if (units.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(unitDashboardProvider);
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: units.length,
        itemBuilder: (context, index) {
          final unit = units[index];
          // Use realtime update if available, otherwise use base data
          final displayUnit = realtimeUpdates[unit.id] ?? unit;

          return UnitListTile(
            unit: displayUnit,
            onTap: () => _navigateToDetail(displayUnit.id),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    final filter = ref.watch(unitFilterProvider);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            filter.hasActiveFilters ? Icons.filter_list_off : Icons.inventory_2,
            size: 64,
            color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            filter.hasActiveFilters
                ? 'No units match your filters'
                : 'No units found',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (filter.hasActiveFilters) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                ref.read(unitFilterProvider.notifier).reset();
                _searchController.clear();
              },
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: SaturdayColors.error),
          const SizedBox(height: 16),
          Text('Error loading units'),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: TextStyle(
              fontSize: 12,
              color: SaturdayColors.secondaryGrey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ref.invalidate(unitDashboardProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => const UnitFilterSheet(),
    );
  }

  String _getStatusLabel(UnitStatus status) {
    switch (status) {
      case UnitStatus.unprovisioned:
        return 'Unprovisioned';
      case UnitStatus.factoryProvisioned:
        return 'Factory Ready';
      case UnitStatus.userProvisioned:
        return 'User Claimed';
    }
  }

  void _navigateToDetail(String unitId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UnitDetailScreen(unitId: unitId),
      ),
    );
  }
}
