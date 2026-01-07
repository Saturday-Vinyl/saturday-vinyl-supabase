import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/screens/device_types/device_type_form_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for viewing device type details
class DeviceTypeDetailScreen extends ConsumerWidget {
  final DeviceType deviceType;

  const DeviceTypeDetailScreen({
    super.key,
    required this.deviceType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(currentUserProvider).value != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(deviceType.name),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _navigateToEdit(context, ref),
              tooltip: 'Edit',
            ),
          if (canManage)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _handleDelete(context, ref),
              tooltip: 'Delete',
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status badge
            Container(
              padding: const EdgeInsets.all(16),
              color: deviceType.isActive
                  ? SaturdayColors.success.withOpacity(0.1)
                  : SaturdayColors.secondaryGrey.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    deviceType.isActive ? Icons.check_circle : Icons.cancel,
                    color: deviceType.isActive
                        ? SaturdayColors.success
                        : SaturdayColors.secondaryGrey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    deviceType.status,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: deviceType.isActive
                              ? SaturdayColors.success
                              : SaturdayColors.secondaryGrey,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),

            // Basic Information
            _Section(
              title: 'Basic Information',
              children: [
                _InfoRow(
                  label: 'Name',
                  value: deviceType.name,
                ),
                if (deviceType.description != null)
                  _InfoRow(
                    label: 'Description',
                    value: deviceType.description!,
                  ),
                if (deviceType.currentFirmwareVersion != null)
                  _InfoRow(
                    label: 'Current Firmware',
                    value: deviceType.currentFirmwareVersion!,
                    icon: Icons.memory,
                  ),
                if (deviceType.specUrl != null)
                  _InfoRow(
                    label: 'Specification',
                    value: deviceType.specUrl!,
                    icon: Icons.link,
                    onTap: () => _launchUrl(deviceType.specUrl!),
                  ),
              ],
            ),

            // Capabilities
            if (deviceType.capabilities.isNotEmpty)
              _Section(
                title: 'Capabilities',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children:
                        deviceType.capabilities.map((capability) {
                      return Chip(
                        label: Text(
                            DeviceCapabilities.getDisplayName(capability)),
                        avatar: const Icon(Icons.check, size: 16),
                      );
                    }).toList(),
                  ),
                ],
              ),

            // Metadata
            _Section(
              title: 'Metadata',
              children: [
                _InfoRow(
                  label: 'Created',
                  value: _formatDate(deviceType.createdAt),
                ),
                _InfoRow(
                  label: 'Last Updated',
                  value: _formatDate(deviceType.updatedAt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToEdit(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceTypeFormScreen(deviceType: deviceType),
      ),
    );

    if (result == true && context.mounted) {
      ref.invalidate(deviceTypesProvider);
      Navigator.pop(context);
    }
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Device Type'),
        content: Text(
          'Are you sure you want to delete "${deviceType.name}"? This action cannot be undone.',
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

    if (confirmed == true && context.mounted) {
      try {
        final management = ref.read(deviceTypeManagementProvider);
        await management.deleteDeviceType(deviceType.id);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device type deleted'),
              backgroundColor: SaturdayColors.success,
            ),
          );
          Navigator.pop(context);
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $error'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
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
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: SaturdayColors.secondaryGrey),
            const SizedBox(width: 8),
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    decoration:
                        onTap != null ? TextDecoration.underline : null,
                    color: onTap != null ? SaturdayColors.info : null,
                  ),
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }
}
