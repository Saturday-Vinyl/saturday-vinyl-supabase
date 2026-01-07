import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/screens/firmware/firmware_edit_screen.dart';
import 'package:saturday_app/screens/firmware/manifest_editor_screen.dart';
import 'package:saturday_app/screens/device_types/device_type_detail_screen.dart';
import 'package:saturday_app/services/storage_service.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for viewing firmware version details
class FirmwareDetailScreen extends ConsumerWidget {
  /// Initial firmware data (used as fallback and for ID)
  final FirmwareVersion firmware;

  const FirmwareDetailScreen({
    super.key,
    required this.firmware,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(currentUserProvider).value != null;

    // Watch the provider to get live updates
    final firmwareAsync = ref.watch(firmwareVersionProvider(firmware.id));
    final currentFirmware = firmwareAsync.valueOrNull ?? firmware;

    final deviceTypeAsync = ref.watch(deviceTypeProvider(currentFirmware.deviceTypeId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Firmware v${currentFirmware.version}'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _navigateToEdit(context, ref, currentFirmware),
              tooltip: 'Edit',
            ),
          if (canManage)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'toggle_production') {
                  _toggleProductionReady(context, ref, currentFirmware);
                } else if (value == 'delete') {
                  _handleDelete(context, ref, currentFirmware);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'toggle_production',
                  child: Row(
                    children: [
                      Icon(
                        currentFirmware.isProductionReady
                            ? Icons.remove_circle_outline
                            : Icons.check_circle_outline,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currentFirmware.isProductionReady
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
              color: currentFirmware.isProductionReady
                  ? SaturdayColors.success.withValues(alpha: 0.1)
                  : SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    currentFirmware.isProductionReady
                        ? Icons.check_circle
                        : Icons.build_circle,
                    color: currentFirmware.isProductionReady
                        ? SaturdayColors.success
                        : SaturdayColors.secondaryGrey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    currentFirmware.isProductionReady ? 'Production Ready' : 'Testing',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: currentFirmware.isProductionReady
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
                    'v${currentFirmware.version}',
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
                      'Device Type: ${currentFirmware.deviceTypeId}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),

            // Release Notes
            if (currentFirmware.releaseNotes != null) ...[
              _Section(
                title: 'Release Notes',
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      currentFirmware.releaseNotes!,
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
                  value: currentFirmware.binaryFilename,
                  icon: Icons.insert_drive_file,
                ),
                if (currentFirmware.binarySize != null)
                  _InfoRow(
                    label: 'File Size',
                    value: StorageService.formatFileSize(currentFirmware.binarySize!),
                    icon: Icons.data_usage,
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _downloadBinary(context, currentFirmware),
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

            // Manifest Builder (Developer Tool)
            _Section(
              title: 'Manifest Builder',
              children: [
                _ManifestBuilderCard(
                  canManage: canManage,
                  onOpenBuilder: () => _openManifestBuilder(context, currentFirmware),
                ),
              ],
            ),

            // Upload Information
            _Section(
              title: 'Upload Information',
              children: [
                _InfoRow(
                  label: 'Upload Date',
                  value: _formatDate(currentFirmware.createdAt),
                  icon: Icons.calendar_today,
                ),
                if (currentFirmware.createdBy != null)
                  _InfoRow(
                    label: 'Uploaded By',
                    value: currentFirmware.createdBy!,
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

  void _navigateToEdit(BuildContext context, WidgetRef ref, FirmwareVersion fw) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FirmwareEditScreen(firmware: fw),
      ),
    );

    if (result == true) {
      // Refresh firmware data
      ref.invalidate(firmwareVersionProvider(fw.id));
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

  void _toggleProductionReady(BuildContext context, WidgetRef ref, FirmwareVersion fw) async {
    final newStatus = !fw.isProductionReady;
    final action = newStatus ? 'production ready' : 'testing';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Mark as ${newStatus ? 'Production' : 'Testing'}?'),
        content: Text(
          'Are you sure you want to mark firmware v${fw.version} as $action?',
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
      await management.toggleProductionReady(fw.id, newStatus);

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

  void _handleDelete(BuildContext context, WidgetRef ref, FirmwareVersion fw) async {
    // TODO: Check if units are using this firmware (Prompt 25)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Firmware'),
        content: Text(
          'Are you sure you want to delete firmware v${fw.version}?\n\n'
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
      await management.deleteFirmware(fw.id);

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

  void _downloadBinary(BuildContext context, FirmwareVersion fw) async {
    try {
      final uri = Uri.parse(fw.binaryUrl);
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

  void _openManifestBuilder(BuildContext context, FirmwareVersion fw) {
    // Open the manifest builder as a developer tool
    // This generates JSON to embed in firmware, not stored in DB
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ManifestEditorScreen(
          firmwareVersion: fw.version,
        ),
      ),
    );
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

/// Card widget for manifest builder developer tool
class _ManifestBuilderCard extends StatelessWidget {
  final bool canManage;
  final VoidCallback onOpenBuilder;

  const _ManifestBuilderCard({
    required this.canManage,
    required this.onOpenBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SaturdayColors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: SaturdayColors.info.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.code,
                  color: SaturdayColors.info,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Manifest Builder',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Use this developer tool to generate manifest JSON for embedding in firmware. '
                        'The manifest is retrieved from devices via the get_manifest command in Service Mode.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (canManage) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onOpenBuilder,
                icon: const Icon(Icons.build),
                label: const Text('Open Manifest Builder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SaturdayColors.info,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
