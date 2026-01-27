import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/providers/device_provider.dart';
import 'package:saturday_app/providers/unit_provider.dart';

/// Screen showing unit details and its associated devices
class UnitDetailScreen extends ConsumerWidget {
  final String unitId;

  const UnitDetailScreen({
    super.key,
    required this.unitId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitAsync = ref.watch(unitByIdProvider(unitId));
    final devicesAsync = ref.watch(devicesByUnitProvider(unitId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unit Details'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          unitAsync.whenOrNull(
            data: (unit) => PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) => _handleMenuAction(context, ref, value, unit),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'copy_serial',
                  child: ListTile(
                    leading: Icon(Icons.copy),
                    title: Text('Copy Serial Number'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (unit.status == UnitStatus.unprovisioned)
                  const PopupMenuItem(
                    value: 'mark_factory',
                    child: ListTile(
                      leading: Icon(Icons.factory),
                      title: Text('Mark Factory Provisioned'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('Delete Unit', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: unitAsync.when(
        data: (unit) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(unitByIdProvider(unitId));
            ref.invalidate(devicesByUnitProvider(unitId));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildUnitHeader(context, unit),
                const SizedBox(height: 24),
                _buildStatusSection(context, unit),
                const SizedBox(height: 24),
                _buildProvisioningSection(context, unit),
                const SizedBox(height: 24),
                _buildDevicesSection(context, devicesAsync),
                if (unit.consumerAttributes.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _buildAttributesSection(context, unit),
                ],
              ],
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: SaturdayColors.error),
              const SizedBox(height: 16),
              Text('Error loading unit: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(unitByIdProvider(unitId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnitHeader(BuildContext context, Unit unit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: SaturdayColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.devices,
                    size: 32,
                    color: SaturdayColors.info,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        unit.displayName,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (unit.serialNumber != null) ...[
                        const SizedBox(height: 4),
                        SelectableText(
                          unit.serialNumber!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                color: SaturdayColors.secondaryGrey,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildStatusChip(unit.status),
                if (unit.isClaimed)
                  Chip(
                    avatar: const Icon(Icons.person, size: 16),
                    label: const Text('Claimed'),
                    backgroundColor: SaturdayColors.success.withValues(alpha: 0.1),
                  ),
                if (unit.isInProduction)
                  Chip(
                    avatar: const Icon(Icons.build, size: 16),
                    label: const Text('In Production'),
                    backgroundColor: SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
                  ),
                if (unit.isCompleted)
                  Chip(
                    avatar: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Completed'),
                    backgroundColor: SaturdayColors.success.withValues(alpha: 0.1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(UnitStatus status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case UnitStatus.unprovisioned:
        color = SaturdayColors.secondaryGrey;
        label = 'Unprovisioned';
        icon = Icons.hourglass_empty;
        break;
      case UnitStatus.factoryProvisioned:
        color = SaturdayColors.info;
        label = 'Factory Provisioned';
        icon = Icons.factory;
        break;
      case UnitStatus.userProvisioned:
        color = SaturdayColors.success;
        label = 'User Provisioned';
        icon = Icons.check_circle;
        break;
    }

    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.1),
      labelStyle: TextStyle(color: color),
    );
  }

  Widget _buildStatusSection(BuildContext context, Unit unit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timeline',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildTimelineItem(
              context,
              'Created',
              unit.createdAt,
              Icons.add_circle_outline,
              isFirst: true,
            ),
            if (unit.productionStartedAt != null)
              _buildTimelineItem(
                context,
                'Production Started',
                unit.productionStartedAt!,
                Icons.play_circle_outline,
              ),
            if (unit.factoryProvisionedAt != null)
              _buildTimelineItem(
                context,
                'Factory Provisioned',
                unit.factoryProvisionedAt!,
                Icons.factory,
              ),
            if (unit.consumerProvisionedAt != null)
              _buildTimelineItem(
                context,
                'User Provisioned',
                unit.consumerProvisionedAt!,
                Icons.person,
              ),
            if (unit.productionCompletedAt != null)
              _buildTimelineItem(
                context,
                'Production Completed',
                unit.productionCompletedAt!,
                Icons.check_circle,
                isLast: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    String label,
    DateTime date,
    IconData icon, {
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            if (!isFirst)
              Container(
                width: 2,
                height: 12,
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
              ),
            Icon(icon, size: 20, color: SaturdayColors.info),
            if (!isLast)
              Container(
                width: 2,
                height: 12,
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label),
                Text(
                  _formatDateTime(date),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProvisioningSection(BuildContext context, Unit unit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Provisioning Info',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(context, 'Product ID', unit.productId ?? 'N/A'),
            _buildInfoRow(context, 'Variant ID', unit.variantId ?? 'N/A'),
            if (unit.orderId != null)
              _buildInfoRow(context, 'Order ID', unit.orderId!),
            if (unit.factoryProvisionedBy != null)
              _buildInfoRow(context, 'Factory Provisioned By', unit.factoryProvisionedBy!),
            if (unit.userId != null)
              _buildInfoRow(context, 'User ID', unit.userId!),
            if (unit.deviceName != null)
              _buildInfoRow(context, 'Device Name', unit.deviceName!),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesSection(
    BuildContext context,
    AsyncValue<List<Device>> devicesAsync,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Devices',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                devicesAsync.whenOrNull(
                  data: (devices) => Chip(
                    label: Text('${devices.length}'),
                    backgroundColor: SaturdayColors.info.withValues(alpha: 0.1),
                  ),
                ) ?? const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 16),
            devicesAsync.when(
              data: (devices) {
                if (devices.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.memory,
                            size: 48,
                            color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No devices assigned',
                            style: TextStyle(color: SaturdayColors.secondaryGrey),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: devices
                      .map((device) => _buildDeviceCard(context, device))
                      .toList(),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Center(
                child: Text('Error loading devices: $error'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context, Device device) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                device.isOnline ? Icons.wifi : Icons.wifi_off,
                size: 16,
                color: device.isOnline ? SaturdayColors.success : SaturdayColors.secondaryGrey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  device.formattedMacAddress,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildDeviceStatusChip(device.status),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (device.firmwareVersion != null) ...[
                const Icon(Icons.system_update, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'v${device.firmwareVersion}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 16),
              ],
              if (device.lastSeenAt != null) ...[
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: device.isOnline ? SaturdayColors.success : Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  'Last seen: ${_formatDateTime(device.lastSeenAt!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: device.isOnline ? SaturdayColors.success : Colors.grey,
                      ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceStatusChip(DeviceStatus status) {
    Color color;
    String label;

    switch (status) {
      case DeviceStatus.unprovisioned:
        color = SaturdayColors.secondaryGrey;
        label = 'Unprovisioned';
        break;
      case DeviceStatus.provisioned:
        color = SaturdayColors.info;
        label = 'Provisioned';
        break;
      case DeviceStatus.online:
        color = SaturdayColors.success;
        label = 'Online';
        break;
      case DeviceStatus.offline:
        color = SaturdayColors.secondaryGrey;
        label = 'Offline';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAttributesSection(BuildContext context, Unit unit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Consumer Attributes',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ...unit.consumerAttributes.entries.map((entry) {
              return _buildInfoRow(context, entry.key, entry.value.toString());
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _handleMenuAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    Unit unit,
  ) async {
    switch (action) {
      case 'copy_serial':
        if (unit.serialNumber != null) {
          await Clipboard.setData(ClipboardData(text: unit.serialNumber!));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Serial number copied to clipboard')),
            );
          }
        }
        break;

      case 'mark_factory':
        try {
          await ref.read(unitManagementProvider).markFactoryProvisioned(
                unitId: unit.id,
                userId: 'current_user', // TODO: Get from auth provider
              );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Unit marked as factory provisioned')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e')),
            );
          }
        }
        break;

      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Unit'),
            content: Text('Are you sure you want to delete ${unit.displayName}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
        );

        if (confirmed == true) {
          try {
            await ref.read(unitManagementProvider).deleteUnit(unit.id);
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Unit deleted')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error deleting unit: $e')),
              );
            }
          }
        }
        break;
    }
  }
}
