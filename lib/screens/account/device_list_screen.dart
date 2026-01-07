import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/widgets/devices/devices.dart';

/// Screen displaying the user's devices with status indicators.
class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(userDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Device',
            onPressed: () => context.pushNamed(RouteNames.deviceSetup),
          ),
        ],
      ),
      body: devicesAsync.when(
        data: (devices) => _buildDeviceList(context, ref, devices),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildError(context, ref, error),
      ),
    );
  }

  Widget _buildDeviceList(
    BuildContext context,
    WidgetRef ref,
    List<Device> devices,
  ) {
    if (devices.isEmpty) {
      return _buildEmptyState(context);
    }

    // Sort devices: hubs first, then by status (online first), then by name
    final sortedDevices = List<Device>.from(devices)
      ..sort((a, b) {
        // Hubs first
        if (a.isHub && !b.isHub) return -1;
        if (!a.isHub && b.isHub) return 1;
        // Online first
        if (a.isOnline && !b.isOnline) return -1;
        if (!a.isOnline && b.isOnline) return 1;
        // Then by name
        return a.name.compareTo(b.name);
      });

    // Group devices by type
    final hubs = sortedDevices.where((d) => d.isHub).toList();
    final crates = sortedDevices.where((d) => d.isCrate).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(userDevicesProvider);
      },
      child: ListView(
        padding: Spacing.pagePadding,
        children: [
          // Status summary
          _buildStatusSummary(context, devices),
          Spacing.sectionGap,
          // Hubs section
          if (hubs.isNotEmpty) ...[
            _buildSectionHeader(context, 'Hubs', hubs.length),
            const SizedBox(height: 8),
            ...hubs.map((device) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DeviceCard(
                    device: device,
                    onTap: () => _navigateToDeviceDetail(context, device),
                  ),
                )),
          ],
          if (hubs.isNotEmpty && crates.isNotEmpty) Spacing.sectionGap,
          // Crates section
          if (crates.isNotEmpty) ...[
            _buildSectionHeader(context, 'Crates', crates.length),
            const SizedBox(height: 8),
            ...crates.map((device) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: DeviceCard(
                    device: device,
                    onTap: () => _navigateToDeviceDetail(context, device),
                  ),
                )),
          ],
          // Bottom padding for add button
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildStatusSummary(BuildContext context, List<Device> devices) {
    final onlineCount = devices.where((d) => d.isOnline).length;
    final offlineCount = devices.where((d) => !d.isOnline).length;
    final lowBatteryCount = devices.where((d) => d.isLowBattery).length;
    final setupRequiredCount = devices.where((d) => d.needsSetup).length;

    return Container(
      padding: Spacing.cardPadding,
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.card,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatusItem(
            context,
            icon: Icons.check_circle,
            color: SaturdayColors.success,
            count: onlineCount,
            label: 'Online',
          ),
          _buildStatusItem(
            context,
            icon: Icons.cloud_off,
            color: SaturdayColors.secondary,
            count: offlineCount,
            label: 'Offline',
          ),
          if (lowBatteryCount > 0)
            _buildStatusItem(
              context,
              icon: Icons.battery_alert,
              color: SaturdayColors.warning,
              count: lowBatteryCount,
              label: 'Low Battery',
            ),
          if (setupRequiredCount > 0)
            _buildStatusItem(
              context,
              icon: Icons.settings,
              color: SaturdayColors.warning,
              count: setupRequiredCount,
              label: 'Setup',
            ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required int count,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: SaturdayColors.secondary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.devices,
              size: 80,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: 24),
            Text(
              'No Devices Yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add your Saturday Hub or Crate to get started.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => context.pushNamed(RouteNames.deviceSetup),
              icon: const Icon(Icons.add),
              label: const Text('Add Device'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, Object error) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: SaturdayColors.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load devices',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(userDevicesProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDeviceDetail(BuildContext context, Device device) {
    context.pushNamed(
      RouteNames.deviceDetail,
      pathParameters: {'id': device.id},
    );
  }
}
