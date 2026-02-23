import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/capability.dart';
import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/providers/capability_provider.dart';
import 'package:saturday_app/providers/remote_monitor_provider.dart';

/// Panel for sending commands to remote devices
///
/// Shows capability-based commands for devices with websocket capability.
class RemoteCommandPanel extends ConsumerWidget {
  final String unitId;
  final List<Device> devices;

  const RemoteCommandPanel({
    super.key,
    required this.unitId,
    required this.devices,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitorState = ref.watch(remoteMonitorProvider(unitId));

    // Get the primary device for sending commands
    final primaryDevice = devices.isNotEmpty ? devices.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.terminal, size: 16),
            const SizedBox(width: 8),
            Text(
              'Commands',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const Spacer(),
            if (monitorState.pendingCommandIds.isNotEmpty)
              Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Pending: ${monitorState.pendingCommandIds.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.info,
                        ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Global commands
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CommandButton(
              label: 'Refresh Status',
              icon: Icons.refresh,
              onPressed: primaryDevice != null
                  ? () => _sendGetStatus(ref, primaryDevice)
                  : null,
            ),
            _CommandButton(
              label: 'Reboot',
              icon: Icons.restart_alt,
              color: Colors.orange,
              onPressed: primaryDevice != null
                  ? () => _showConfirmDialog(
                        context,
                        title: 'Reboot Device',
                        message:
                            'Are you sure you want to reboot the device? This will interrupt any current operations.',
                        onConfirm: () => _sendReboot(ref, primaryDevice),
                      )
                  : null,
            ),
            _CommandButton(
              label: 'Consumer Reset',
              icon: Icons.person_remove,
              color: Colors.orange,
              onPressed: primaryDevice != null
                  ? () => _showConfirmDialog(
                        context,
                        title: 'Consumer Reset',
                        message:
                            'This will clear all consumer data (WiFi credentials, user preferences). Factory data will be preserved.',
                        onConfirm: () => _sendConsumerReset(ref, primaryDevice),
                      )
                  : null,
            ),
            _CommandButton(
              label: 'Factory Reset',
              icon: Icons.warning,
              color: SaturdayColors.error,
              onPressed: primaryDevice != null
                  ? () => _showConfirmDialog(
                        context,
                        title: 'Factory Reset',
                        message:
                            'WARNING: This will erase ALL data including serial number. The device will need to be re-provisioned.',
                        isDestructive: true,
                        onConfirm: () => _sendFactoryReset(ref, primaryDevice),
                      )
                  : null,
            ),
          ],
        ),

        // Device-specific commands (if device type has commands)
        if (primaryDevice?.deviceTypeSlug != null) ...[
          const SizedBox(height: 16),
          _DeviceCommandsSection(
            unitId: unitId,
            device: primaryDevice!,
          ),
        ],
      ],
    );
  }

  void _sendGetStatus(WidgetRef ref, Device device) {
    ref.read(remoteMonitorProvider(unitId).notifier).sendCommand(
          macAddress: device.macAddress,
          command: 'get_status',
        );
  }

  void _sendReboot(WidgetRef ref, Device device) {
    ref.read(remoteMonitorProvider(unitId).notifier).sendReboot(
          device.macAddress,
        );
  }

  void _sendConsumerReset(WidgetRef ref, Device device) {
    ref.read(remoteMonitorProvider(unitId).notifier).sendConsumerReset(
          device.macAddress,
        );
  }

  void _sendFactoryReset(WidgetRef ref, Device device) {
    ref.read(remoteMonitorProvider(unitId).notifier).sendFactoryReset(
          device.macAddress,
        );
  }

  void _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
    bool isDestructive = false,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            style: isDestructive
                ? TextButton.styleFrom(foregroundColor: SaturdayColors.error)
                : null,
            child: Text(isDestructive ? 'Reset' : 'Confirm'),
          ),
        ],
      ),
    );
  }
}

/// Section showing capability commands for a device
class _DeviceCommandsSection extends ConsumerWidget {
  final String unitId;
  final Device device;

  const _DeviceCommandsSection({
    required this.unitId,
    required this.device,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commandsAsync =
        ref.watch(commandsForDeviceTypeSlugProvider(device.deviceTypeSlug!));

    return commandsAsync.when(
      data: (commands) {
        if (commands.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Device Commands',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: commands.map((command) {
                return _CommandButton(
                  label: command.displayName,
                  icon: Icons.terminal,
                  onPressed: () => _runCommand(ref, command),
                );
              }).toList(),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _runCommand(WidgetRef ref, CapabilityCommand command) {
    ref.read(remoteMonitorProvider(unitId).notifier).sendCapabilityCommand(
          macAddress: device.macAddress,
          commandName: command.name,
        );
  }
}

/// Styled command button
class _CommandButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  final VoidCallback? onPressed;

  const _CommandButton({
    required this.label,
    required this.icon,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? SaturdayColors.info;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: onPressed != null ? buttonColor : Colors.grey,
        side: BorderSide(
          color: onPressed != null
              ? buttonColor.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12),
      ),
    );
  }
}
