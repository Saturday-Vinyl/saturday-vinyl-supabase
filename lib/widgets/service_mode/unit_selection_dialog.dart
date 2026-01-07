import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/providers/service_mode_provider.dart';

/// Dialog for selecting a production unit for a fresh device
class UnitSelectionDialog extends ConsumerStatefulWidget {
  final String? firmwareId;
  final String? deviceTypeId;

  const UnitSelectionDialog({
    super.key,
    this.firmwareId,
    this.deviceTypeId,
  });

  @override
  ConsumerState<UnitSelectionDialog> createState() =>
      _UnitSelectionDialogState();
}

class _UnitSelectionDialogState extends ConsumerState<UnitSelectionDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get units without MAC address (prioritize these)
    final unitsWithoutMacAsync = ref.watch(unitsWithoutMacProvider(null));

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 500,
          maxHeight: 600,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.qr_code, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Production Unit',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        Text(
                          'Choose a unit to associate with this device',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Search field
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by unit ID...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },
              ),
              const SizedBox(height: 16),

              // Info banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: SaturdayColors.info.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: SaturdayColors.info,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Showing units without MAC address (not yet provisioned)',
                        style: TextStyle(
                          color: SaturdayColors.info,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Unit list
              Expanded(
                child: unitsWithoutMacAsync.when(
                  data: (units) {
                    final filteredUnits = _searchQuery.isEmpty
                        ? units
                        : units
                            .where((u) =>
                                u.unitId.toLowerCase().contains(_searchQuery) ||
                                (u.customerName
                                        ?.toLowerCase()
                                        .contains(_searchQuery) ??
                                    false))
                            .toList();

                    if (filteredUnits.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No units available'
                                  : 'No units match your search',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      itemCount: filteredUnits.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final unit = filteredUnits[index];
                        return _UnitListTile(
                          unit: unit,
                          onTap: () => Navigator.of(context).pop(unit),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: SaturdayColors.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load units',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(unitsWithoutMacProvider(null)),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitListTile extends StatelessWidget {
  final ProductionUnit unit;
  final VoidCallback onTap;

  const _UnitListTile({
    required this.unit,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SaturdayColors.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.qr_code,
          color: SaturdayColors.info,
          size: 20,
        ),
      ),
      title: Text(
        unit.unitId,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
        ),
      ),
      subtitle: Row(
        children: [
          if (unit.customerName != null && unit.customerName!.isNotEmpty) ...[
            Icon(Icons.person, size: 12, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                unit.customerName!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Icon(Icons.calendar_today, size: 12, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            _formatDate(unit.createdAt),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Show the unit selection dialog
Future<ProductionUnit?> showUnitSelectionDialog(
  BuildContext context, {
  String? firmwareId,
  String? deviceTypeId,
}) {
  return showDialog<ProductionUnit>(
    context: context,
    builder: (context) => UnitSelectionDialog(
      firmwareId: firmwareId,
      deviceTypeId: deviceTypeId,
    ),
  );
}
