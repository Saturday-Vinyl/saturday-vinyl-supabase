import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/widgets/common/empty_state.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
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
        loading: () => const LoadingIndicator.medium(
          message: 'Loading devices...',
        ),
        error: (error, stack) => ErrorDisplay.fullScreen(
          message: error.toString(),
          onRetry: () => ref.invalidate(userDevicesProvider),
        ),
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
    // Use isEffectivelyOnline to account for heartbeat staleness
    final onlineCount = devices.where((d) => d.isEffectivelyOnline).length;
    final offlineCount = devices.where((d) => !d.isEffectivelyOnline).length;
    final lowBatteryCount = devices.where((d) => d.isLowBattery).length;
    final setupRequiredCount = devices.where((d) => d.needsSetup).length;

    final colors = SaturdayColorTokens.of(context);
    return Container(
      padding: Spacing.cardPadding,
      decoration: BoxDecoration(
        color: colors.paperElevated,
        borderRadius: AppRadius.largeRadius,
        border: Border.all(color: colors.borderQuiet),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatusItem(
            context,
            colors: colors,
            icon: Icons.check_circle,
            count: onlineCount,
            label: 'Online',
          ),
          _buildStatusItem(
            context,
            colors: colors,
            icon: Icons.cloud_off,
            count: offlineCount,
            label: 'Offline',
            muted: true,
          ),
          if (lowBatteryCount > 0)
            _buildStatusItem(
              context,
              colors: colors,
              icon: Icons.battery_alert,
              count: lowBatteryCount,
              label: 'Low battery',
            ),
          if (setupRequiredCount > 0)
            _buildStatusItem(
              context,
              colors: colors,
              icon: Icons.settings,
              count: setupRequiredCount,
              label: 'Setup',
            ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(
    BuildContext context, {
    required SaturdayColorTokens colors,
    required IconData icon,
    required int count,
    required String label,
    bool muted = false,
  }) {
    final tone = muted ? colors.inkTertiary : colors.ink;
    return Column(
      children: [
        Icon(icon, color: tone, size: 24),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tone,
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
    final colors = SaturdayColorTokens.of(context);
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
            color: colors.borderQuiet,
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
    return EmptyState.noDevices(
      onAddDevice: () => context.pushNamed(RouteNames.deviceSetup),
    );
  }

  void _navigateToDeviceDetail(BuildContext context, Device device) {
    context.pushNamed(
      RouteNames.deviceDetail,
      pathParameters: {'id': device.id},
    );
  }
}
