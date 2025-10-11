import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/screens/firmware/firmware_edit_screen.dart';
import 'package:saturday_app/screens/device_types/device_type_detail_screen.dart';
import 'package:saturday_app/services/storage_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for viewing firmware version details
class FirmwareDetailScreen extends ConsumerWidget {
  final FirmwareVersion firmware;

  const FirmwareDetailScreen({
    super.key,
    required this.firmware,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(currentUserProvider).value != null;
    final deviceTypeAsync = ref.watch(deviceTypeProvider(firmware.deviceTypeId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Firmware v${firmware.version}'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _navigateToEdit(context, ref),
              tooltip: 'Edit',
            ),
          if (canManage)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'toggle_production') {
                  _toggleProductionReady(context, ref);
                } else if (value == 'delete') {
                  _handleDelete(context, ref);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_production',
                  child: Row(
                    children: [
                      Icon(
                        firmware.isProductionReady
                            ? Icons.remove_circle_outline
                            : Icons.check_circle_outline,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        firmware.isProductionReady
                            ? 'Mark as Testing'
                            : 'Mark as Production',
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20, color: SaturdayColors.error),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: SaturdayColors.error)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Production Ready Status Banner
            Container(
              padding: const EdgeInsets.all(16),
              color: firmware.isProductionReady
                  ? SaturdayColors.success.withValues(alpha: 0.1)
                  : SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    firmware.isProductionReady
                        ? Icons.check_circle
                        : Icons.build_circle,
                    color: firmware.isProductionReady
                        ? SaturdayColors.success
                        : SaturdayColors.secondaryGrey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    firmware.isProductionReady ? 'Production Ready' : 'Testing',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: firmware.isProductionReady
                              ? SaturdayColors.success
                              : SaturdayColors.secondaryGrey,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),

            // Version Number (Large, Prominent)
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'v${firmware.version}',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: SaturdayColors.primaryDark,
                        ),
                  ),
                  const SizedBox(height: 8),
                  deviceTypeAsync.when(
                    data: (deviceType) => InkWell(
                      onTap: () => _navigateToDeviceType(context, deviceType),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.devices_other,
                            size: 16,
                            color: SaturdayColors.secondaryGrey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            deviceType.name,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: SaturdayColors.info,
                                      decoration: TextDecoration.underline,
                                    ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward,
                            size: 14,
                            color: SaturdayColors.info,
                          ),
                        ],
                      ),
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (_, __) => Text(
                      'Device Type: ${firmware.deviceTypeId}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),

            // Release Notes
            if (firmware.releaseNotes != null) ...[
              _Section(
                title: 'Release Notes',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      firmware.releaseNotes!,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ],

            // Binary File Information
            _Section(
              title: 'Binary File',
              children: [
                _InfoRow(
                  label: 'Filename',
                  value: firmware.binaryFilename,
                  icon: Icons.insert_drive_file,
                ),
                if (firmware.binarySize != null)
                  _InfoRow(
                    label: 'File Size',
                    value: StorageService.formatFileSize(firmware.binarySize!),
                    icon: Icons.data_usage,
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _downloadBinary(context),
                      icon: const Icon(Icons.download),
                      label: const Text('Download Binary'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SaturdayColors.info,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Upload Information
            _Section(
              title: 'Upload Information',
              children: [
                _InfoRow(
                  label: 'Upload Date',
                  value: _formatDate(firmware.createdAt),
                  icon: Icons.calendar_today,
                ),
                if (firmware.createdBy != null)
                  _InfoRow(
                    label: 'Uploaded By',
                    value: firmware.createdBy!,
                    icon: Icons.person,
                  ),
              ],
            ),

            // Units Using This Firmware (TODO: Implement in Prompt 25)
            // This will show count and list of production units using this firmware
          ],
        ),
      ),
    );
  }

  void _navigateToEdit(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FirmwareEditScreen(firmware: firmware),
      ),
    );

    if (result == true) {
      // Refresh firmware data
      ref.invalidate(firmwareVersionProvider(firmware.id));
    }
  }

  void _navigateToDeviceType(BuildContext context, DeviceType deviceType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceTypeDetailScreen(deviceType: deviceType),
      ),
    );
  }

  void _toggleProductionReady(BuildContext context, WidgetRef ref) async {
    final newStatus = !firmware.isProductionReady;
    final action = newStatus ? 'production ready' : 'testing';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark as ${newStatus ? 'Production' : 'Testing'}?'),
        content: Text(
          'Are you sure you want to mark firmware v${firmware.version} as $action?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final management = ref.read(firmwareManagementProvider);
      await management.toggleProductionReady(firmware.id, newStatus);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Firmware marked as $action',
            ),
          ),
        );
        // Pop back to list
        Navigator.pop(context);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update firmware: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  void _handleDelete(BuildContext context, WidgetRef ref) async {
    // TODO: Check if units are using this firmware (Prompt 25)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Firmware'),
        content: Text(
          'Are you sure you want to delete firmware v${firmware.version}?\n\n'
          'This will also delete the binary file from storage and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: SaturdayColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final management = ref.read(firmwareManagementProvider);
      await management.deleteFirmware(firmware.id);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firmware deleted successfully')),
        );
        // Pop back to list
        Navigator.pop(context);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete firmware: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  void _downloadBinary(BuildContext context) async {
    try {
      final uri = Uri.parse(firmware.binaryUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open download URL'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download binary: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// Section widget for grouping related information
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: SaturdayColors.primaryDark,
                ),
          ),
        ),
        const Divider(height: 1),
        ...children,
      ],
    );
  }
}

/// Info row widget for displaying label-value pairs
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.label,
    required this.value,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 20,
              color: SaturdayColors.secondaryGrey,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: onTap != null ? SaturdayColors.info : null,
                    decoration:
                        onTap != null ? TextDecoration.underline : null,
                  ),
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        child: row,
      );
    }

    return row;
  }
}
