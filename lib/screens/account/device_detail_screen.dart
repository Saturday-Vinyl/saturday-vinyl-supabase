import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/widgets/devices/devices.dart';

/// Screen displaying detailed information about a device.
class DeviceDetailScreen extends ConsumerStatefulWidget {
  final String deviceId;

  const DeviceDetailScreen({
    super.key,
    required this.deviceId,
  });

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  bool _isEditing = false;
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceAsync = ref.watch(deviceByIdProvider(widget.deviceId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Details'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(context, ref, value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('Rename'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'remove',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: SaturdayColors.error),
                  title: Text('Remove Device', style: TextStyle(color: SaturdayColors.error)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: deviceAsync.when(
        data: (device) {
          if (device == null) {
            return _buildNotFound(context);
          }
          return _buildContent(context, ref, device);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildError(context, ref, error),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, Device device) {
    return ListView(
      padding: Spacing.pagePadding,
      children: [
        // Device header
        _buildDeviceHeader(context, device),
        Spacing.sectionGap,
        // Status section
        _buildSection(
          context,
          title: 'Status',
          child: _buildStatusContent(context, device),
        ),
        Spacing.sectionGap,
        // Device info section
        _buildSection(
          context,
          title: 'Device Information',
          child: _buildDeviceInfo(context, device),
        ),
        if (device.isCrate) ...[
          Spacing.sectionGap,
          // Battery section for crates
          _buildSection(
            context,
            title: 'Battery',
            child: BatteryProgress(level: device.batteryLevel),
          ),
        ],
        Spacing.sectionGap,
        // Actions section
        _buildActionsSection(context, ref, device),
      ],
    );
  }

  Color _getConnectivityColor(ConnectivityStatus status) {
    switch (status) {
      case ConnectivityStatus.online:
        return SaturdayColors.success;
      case ConnectivityStatus.uncertain:
        return SaturdayColors.warning;
      case ConnectivityStatus.offline:
      case ConnectivityStatus.setupRequired:
        return SaturdayColors.secondary;
    }
  }

  Widget _buildDeviceHeader(BuildContext context, Device device) {
    final connectivityColor = _getConnectivityColor(device.connectivityStatus);

    return Container(
      padding: Spacing.cardPadding,
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: connectivityColor.withValues(alpha: 0.1),
              borderRadius: AppRadius.mediumRadius,
            ),
            child: Icon(
              device.isHub ? Icons.router : Icons.inventory_2_outlined,
              color: connectivityColor,
              size: 32,
            ),
          ),
          Spacing.horizontalGapLg,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isEditing)
                  TextField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Device name',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _saveName(ref, device),
                  )
                else
                  Text(
                    device.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                const SizedBox(height: 4),
                Text(
                  device.isHub ? 'Saturday Hub' : 'Saturday Crate',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SaturdayColors.secondary,
                      ),
                ),
              ],
            ),
          ),
          ConnectivityStatusChip.fromDevice(device: device),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: Spacing.cardPadding,
          decoration: BoxDecoration(
            color: SaturdayColors.white,
            borderRadius: AppRadius.largeRadius,
            boxShadow: AppShadows.card,
          ),
          child: child,
        ),
      ],
    );
  }

  String _getConnectivityLabel(ConnectivityStatus status) {
    switch (status) {
      case ConnectivityStatus.online:
        return 'Online';
      case ConnectivityStatus.uncertain:
        return 'Connecting...';
      case ConnectivityStatus.offline:
        return 'Offline';
      case ConnectivityStatus.setupRequired:
        return 'Setup Required';
    }
  }

  Widget _buildStatusContent(BuildContext context, Device device) {
    final connectivityColor = _getConnectivityColor(device.connectivityStatus);
    final connectivityLabel = _getConnectivityLabel(device.connectivityStatus);

    return Column(
      children: [
        _buildInfoRow(
          context,
          icon: Icons.circle,
          iconColor: connectivityColor,
          label: 'Connection',
          value: connectivityLabel,
        ),
        const Divider(height: 24),
        _buildInfoRow(
          context,
          icon: Icons.access_time,
          label: 'Last Seen',
          value: _formatLastSeen(device.lastSeenAt),
        ),
      ],
    );
  }

  Widget _buildDeviceInfo(BuildContext context, Device device) {
    return Column(
      children: [
        _buildInfoRow(
          context,
          icon: Icons.qr_code,
          label: 'Serial Number',
          value: device.serialNumber,
        ),
        const Divider(height: 24),
        _buildInfoRow(
          context,
          icon: Icons.system_update,
          label: 'Firmware Version',
          value: device.firmwareVersion ?? 'Unknown',
        ),
        const Divider(height: 24),
        _buildInfoRow(
          context,
          icon: Icons.category,
          label: 'Device Type',
          value: device.isHub ? 'Hub' : 'Crate',
        ),
        const Divider(height: 24),
        _buildInfoRow(
          context,
          icon: Icons.calendar_today,
          label: 'Added',
          value: _formatDate(device.createdAt),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: iconColor ?? SaturdayColors.secondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionsSection(BuildContext context, WidgetRef ref, Device device) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (device.needsSetup)
          ElevatedButton.icon(
            onPressed: () {
              // TODO: Navigate to device setup continuation
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Continue setup coming soon')),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('Complete Setup'),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _showRemoveConfirmation(context, ref, device),
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove Device'),
          style: OutlinedButton.styleFrom(
            foregroundColor: SaturdayColors.error,
            side: const BorderSide(color: SaturdayColors.error),
          ),
        ),
      ],
    );
  }

  Widget _buildNotFound(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.device_unknown,
            size: 64,
            color: SaturdayColors.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            'Device not found',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => context.pop(),
            child: const Text('Go Back'),
          ),
        ],
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
              'Failed to load device',
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
              onPressed: () => ref.invalidate(deviceByIdProvider(widget.deviceId)),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, WidgetRef ref, String action) {
    final device = ref.read(deviceByIdProvider(widget.deviceId)).valueOrNull;
    if (device == null) return;

    switch (action) {
      case 'rename':
        setState(() {
          _isEditing = true;
          _nameController.text = device.name;
        });
        break;
      case 'remove':
        _showRemoveConfirmation(context, ref, device);
        break;
    }
  }

  Future<void> _saveName(WidgetRef ref, Device device) async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty || newName == device.name) {
      setState(() => _isEditing = false);
      return;
    }

    try {
      final deviceRepo = ref.read(deviceRepositoryProvider);
      await deviceRepo.updateDevice(device.copyWith(name: newName));
      ref.invalidate(deviceByIdProvider(widget.deviceId));
      ref.invalidate(userDevicesProvider);
      setState(() => _isEditing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device renamed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename: $e')),
        );
      }
    }
  }

  Future<void> _showRemoveConfirmation(
    BuildContext context,
    WidgetRef ref,
    Device device,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Device?'),
        content: Text(
          'Are you sure you want to remove "${device.name}" from your account? '
          'You can add it again later by going through the setup process.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: SaturdayColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeDevice(ref, device);
    }
  }

  Future<void> _removeDevice(WidgetRef ref, Device device) async {
    try {
      final deviceRepo = ref.read(deviceRepositoryProvider);
      await deviceRepo.deleteDevice(device.id);
      ref.invalidate(userDevicesProvider);
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove device: $e')),
        );
      }
    }
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return 'Never';

    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';

    return '${lastSeen.month}/${lastSeen.day}/${lastSeen.year}';
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}
