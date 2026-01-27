import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/models/product_device_type.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';

/// Dialog for assigning device types to a product with quantities
class DeviceTypeAssignmentDialog extends ConsumerStatefulWidget {
  final String productId;
  final String productName;

  const DeviceTypeAssignmentDialog({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  ConsumerState<DeviceTypeAssignmentDialog> createState() =>
      _DeviceTypeAssignmentDialogState();
}

class _DeviceTypeAssignmentDialogState
    extends ConsumerState<DeviceTypeAssignmentDialog> {
  /// Map of device type ID to quantity
  final Map<String, int> _assignments = {};
  bool _isLoading = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentAssignments();
  }

  Future<void> _loadCurrentAssignments() async {
    final currentAssignments =
        await ref.read(productDeviceTypesProvider(widget.productId).future);

    if (mounted) {
      setState(() {
        for (final pdt in currentAssignments) {
          _assignments[pdt.deviceType.id] = pdt.quantity;
        }
        _isInitialized = true;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

    try {
      final deviceTypes = _assignments.entries
          .where((e) => e.value > 0)
          .map((e) => ProductDeviceType(
                productId: widget.productId,
                deviceTypeId: e.key,
                quantity: e.value,
              ))
          .toList();

      await ref.read(deviceTypeManagementProvider).setDeviceTypesForProduct(
            productId: widget.productId,
            deviceTypes: deviceTypes,
          );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device types updated successfully'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update device types: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deviceTypesAsync = ref.watch(activeDeviceTypesProvider);

    return AlertDialog(
      title: const Text('Assign Device Types'),
      content: SizedBox(
        width: 500,
        height: 400,
        child: !_isInitialized
            ? const Center(child: CircularProgressIndicator())
            : deviceTypesAsync.when(
                data: (deviceTypes) {
                  if (deviceTypes.isEmpty) {
                    return const Center(
                      child: Text('No device types available'),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configure device types for "${widget.productName}"',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          itemCount: deviceTypes.length,
                          itemBuilder: (context, index) {
                            final deviceType = deviceTypes[index];
                            final quantity = _assignments[deviceType.id] ?? 0;

                            return _DeviceTypeRow(
                              deviceType: deviceType,
                              quantity: quantity,
                              onQuantityChanged: (newQuantity) {
                                setState(() {
                                  if (newQuantity > 0) {
                                    _assignments[deviceType.id] = newQuantity;
                                  } else {
                                    _assignments.remove(deviceType.id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Summary
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: SaturdayColors.light,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total device types:',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            Text(
                              '${_assignments.values.where((q) => q > 0).length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const LoadingIndicator(
                  message: 'Loading device types...',
                ),
                error: (error, stack) => Center(
                  child: Text(
                    'Failed to load device types: $error',
                    style: const TextStyle(color: SaturdayColors.error),
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Row widget for a single device type with quantity controls
class _DeviceTypeRow extends StatelessWidget {
  final DeviceType deviceType;
  final int quantity;
  final ValueChanged<int> onQuantityChanged;

  const _DeviceTypeRow({
    required this.deviceType,
    required this.quantity,
    required this.onQuantityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isAssigned = quantity > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isAssigned
            ? SaturdayColors.info.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAssigned
              ? SaturdayColors.info
              : SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Checkbox to toggle assignment
          Checkbox(
            value: isAssigned,
            onChanged: (checked) {
              onQuantityChanged(checked == true ? 1 : 0);
            },
          ),
          const SizedBox(width: 8),
          // Device type info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceType.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (deviceType.description != null &&
                    deviceType.description!.isNotEmpty)
                  Text(
                    deviceType.description!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.secondaryGrey,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Quantity controls
          if (isAssigned) ...[
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: quantity > 1 ? () => onQuantityChanged(quantity - 1) : null,
              iconSize: 20,
              visualDensity: VisualDensity.compact,
            ),
            Container(
              width: 40,
              alignment: Alignment.center,
              child: Text(
                '$quantity',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => onQuantityChanged(quantity + 1),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }
}
