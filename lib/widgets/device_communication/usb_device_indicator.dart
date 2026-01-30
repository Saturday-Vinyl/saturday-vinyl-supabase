import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/connected_device.dart';
import 'package:saturday_app/providers/device_communication_provider.dart';

/// Global USB device indicator for the AppBar.
///
/// Shows when Saturday devices are connected via USB and provides quick
/// access to communicate with them or navigate to their unit details.
class USBDeviceIndicator extends ConsumerWidget {
  /// Callback when user wants to navigate to a unit
  final void Function(String serialNumber)? onNavigateToUnit;

  /// Callback when user wants to communicate with a device
  final void Function(ConnectedDevice device)? onCommunicateWithDevice;

  /// Callback when user wants to provision an unprovisioned device
  final void Function(ConnectedDevice device)? onProvisionDevice;

  const USBDeviceIndicator({
    super.key,
    this.onNavigateToUnit,
    this.onCommunicateWithDevice,
    this.onProvisionDevice,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasDevices = ref.watch(hasConnectedDevicesProvider);
    final deviceCount = ref.watch(connectedDeviceCountProvider);

    // Don't show anything if no devices connected
    if (!hasDevices) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<void>(
        tooltip: '$deviceCount device${deviceCount > 1 ? 's' : ''} connected',
        offset: const Offset(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        itemBuilder: (context) => _buildMenuItems(context, ref),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: SaturdayColors.success.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.usb,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                '$deviceCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<void>> _buildMenuItems(
      BuildContext context, WidgetRef ref) {
    final devices = ref.read(connectedDevicesProvider);
    final items = <PopupMenuEntry<void>>[];

    // Header
    items.add(
      PopupMenuItem<void>(
        enabled: false,
        height: 32,
        child: Text(
          '${devices.length} device${devices.length > 1 ? 's' : ''} connected',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: SaturdayColors.primaryDark.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ),
    );

    items.add(const PopupMenuDivider());

    // Device items
    for (final device in devices) {
      items.add(
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _DeviceMenuItem(
            device: device,
            onNavigateToUnit: onNavigateToUnit,
            onCommunicateWithDevice: onCommunicateWithDevice,
            onProvisionDevice: onProvisionDevice,
          ),
        ),
      );
    }

    return items;
  }
}

class _DeviceMenuItem extends StatelessWidget {
  final ConnectedDevice device;
  final void Function(String serialNumber)? onNavigateToUnit;
  final void Function(ConnectedDevice device)? onCommunicateWithDevice;
  final void Function(ConnectedDevice device)? onProvisionDevice;

  const _DeviceMenuItem({
    required this.device,
    this.onNavigateToUnit,
    this.onCommunicateWithDevice,
    this.onProvisionDevice,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Device info row
          Row(
            children: [
              _DeviceTypeIcon(deviceType: device.deviceType),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.isProvisioned
                          ? device.displayName
                          : '${_formatDeviceType(device.deviceType)} (Unprovisioned)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.formattedMacAddress,
                      style: TextStyle(
                        color: SaturdayColors.secondaryGrey,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      'v${device.firmwareVersion}',
                      style: TextStyle(
                        color: SaturdayColors.secondaryGrey,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Action buttons
          Row(
            children: [
              if (device.isProvisioned && device.serialNumber != null) ...[
                _ActionButton(
                  label: 'View Unit',
                  icon: Icons.open_in_new,
                  onPressed: () {
                    Navigator.pop(context);
                    onNavigateToUnit?.call(device.serialNumber!);
                  },
                ),
                const SizedBox(width: 8),
              ],
              _ActionButton(
                label: device.isProvisioned ? 'Communicate' : 'Provision',
                icon: device.isProvisioned
                    ? Icons.terminal
                    : Icons.add_circle_outline,
                primary: !device.isProvisioned,
                onPressed: () {
                  Navigator.pop(context);
                  if (device.isProvisioned) {
                    onCommunicateWithDevice?.call(device);
                  } else {
                    onProvisionDevice?.call(device);
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDeviceType(String type) {
    // Convert slug to title case (e.g., "hub-prototype" -> "Hub Prototype")
    return type
        .split('-')
        .map((word) =>
            word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
        .join(' ');
  }
}

class _DeviceTypeIcon extends StatelessWidget {
  final String deviceType;

  const _DeviceTypeIcon({required this.deviceType});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    // Map device type to icon
    switch (deviceType.toLowerCase()) {
      case 'hub':
      case 'hub-prototype':
        icon = Icons.router;
        color = SaturdayColors.info;
        break;
      case 'crate':
        icon = Icons.inventory_2;
        color = SaturdayColors.success;
        break;
      case 'speaker':
        icon = Icons.speaker;
        color = SaturdayColors.warning;
        break;
      default:
        icon = Icons.developer_board;
        color = SaturdayColors.secondaryGrey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        size: 24,
        color: color,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    if (primary) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: SaturdayColors.primaryDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(0, 32),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: SaturdayColors.primaryDark,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
        side: const BorderSide(color: SaturdayColors.secondaryGrey),
      ),
    );
  }
}
