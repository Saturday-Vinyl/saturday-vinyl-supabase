import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/models/production_unit_with_consumer_info.dart';
import 'package:saturday_app/providers/production_unit_provider.dart';
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

  Future<void> _handleUnitSelection(ProductionUnitWithConsumerInfo unitInfo) async {
    if (unitInfo.hasConsumerDevice) {
      // Show confirmation dialog for re-provisioning
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Text('Re-provision Unit?'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This unit (${unitInfo.unit.unitId}) is already linked to a consumer device.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'Re-provisioning will delete the existing consumer device '
                  'association. The user will need to set up this device again '
                  'via the consumer app.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('Re-provision'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;

      // Delete the consumer device record
      try {
        final repository = ref.read(productionUnitRepositoryProvider);
        await repository.deleteConsumerDevice(unitInfo.consumerDeviceId!);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete consumer device: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(unitInfo.unit);
  }

  @override
  Widget build(BuildContext context) {
    // Get all units for provisioning (includes consumer device info)
    final unitsAsync = ref.watch(unitsForProvisioningProvider(null));

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
                        'Units with ⚠️ are linked to consumer devices and will require re-provisioning',
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
                child: unitsAsync.when(
                  data: (units) {
                    final filteredUnits = _searchQuery.isEmpty
                        ? units
                        : units
                            .where((u) =>
                                u.unit.unitId
                                    .toLowerCase()
                                    .contains(_searchQuery) ||
                                (u.unit.customerName
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
                        final unitInfo = filteredUnits[index];
                        return _UnitListTile(
                          unitInfo: unitInfo,
                          onTap: () => _handleUnitSelection(unitInfo),
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
                              ref.invalidate(unitsForProvisioningProvider(null)),
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
  final ProductionUnitWithConsumerInfo unitInfo;
  final VoidCallback onTap;

  const _UnitListTile({
    required this.unitInfo,
    required this.onTap,
  });

  ProductionUnit get unit => unitInfo.unit;

  @override
  Widget build(BuildContext context) {
    final hasConsumer = unitInfo.hasConsumerDevice;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: hasConsumer
              ? Colors.orange.withValues(alpha: 0.1)
              : SaturdayColors.info.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          hasConsumer ? Icons.warning_amber_rounded : Icons.qr_code,
          color: hasConsumer ? Colors.orange : SaturdayColors.info,
          size: 20,
        ),
      ),
      title: Row(
        children: [
          Text(
            unit.unitId,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          if (hasConsumer) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'In Use',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange,
                ),
              ),
            ),
          ],
        ],
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
