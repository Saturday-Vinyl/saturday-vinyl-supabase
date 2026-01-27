import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/capability.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/models/firmware.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/capability_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
import 'package:saturday_app/screens/device_types/device_type_form_screen.dart';
import 'package:saturday_app/screens/firmware/firmware_form_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for viewing device type details with capabilities and firmware
class DeviceTypeDetailScreen extends ConsumerWidget {
  final DeviceType deviceType;

  const DeviceTypeDetailScreen({
    super.key,
    required this.deviceType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(currentUserProvider).value != null;

    // Watch dynamic capabilities for this device type
    final capabilitiesAsync =
        ref.watch(capabilitiesForDeviceTypeProvider(deviceType.id));

    // Watch firmware versions for this device type
    final firmwareAsync =
        ref.watch(firmwareByDeviceTypeProvider(deviceType.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(deviceType.name),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(capabilitiesForDeviceTypeProvider(deviceType.id));
          ref.invalidate(firmwareByDeviceTypeProvider(deviceType.id));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status badge
              _buildStatusBanner(context),

              // Basic Information
              _buildBasicInfoSection(context),

              // SoC Configuration
              _buildSocConfigSection(context),

              // Capabilities (dynamic from database)
              _buildCapabilitiesSection(context, capabilitiesAsync),

              // Firmware Versions
              _buildFirmwareSection(context, ref, firmwareAsync, canManage),

              // Metadata
              _buildMetadataSection(context),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: deviceType.isActive
          ? SaturdayColors.success.withValues(alpha: 0.1)
          : SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
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
    );
  }

  Widget _buildBasicInfoSection(BuildContext context) {
    return _Section(
      title: 'Basic Information',
      children: [
        _InfoRow(
          label: 'Name',
          value: deviceType.name,
        ),
        if (deviceType.description != null &&
            deviceType.description!.isNotEmpty)
          _InfoRow(
            label: 'Description',
            value: deviceType.description!,
          ),
        if (deviceType.specUrl != null)
          _InfoRow(
            label: 'Specification',
            value: deviceType.specUrl!,
            icon: Icons.link,
            onTap: () => _launchUrl(deviceType.specUrl!),
          ),
      ],
    );
  }

  Widget _buildSocConfigSection(BuildContext context) {
    final socTypes = deviceType.effectiveSocTypes;
    if (socTypes.isEmpty) {
      return const SizedBox.shrink();
    }

    return _Section(
      title: 'SoC Configuration',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: socTypes.map((soc) {
            final isMaster = soc == deviceType.effectiveMasterSoc;
            return Chip(
              avatar: Icon(
                isMaster ? Icons.wifi : Icons.memory,
                size: 16,
                color: isMaster ? SaturdayColors.info : null,
              ),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(soc.toUpperCase()),
                  if (isMaster) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: SaturdayColors.info,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'MASTER',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              backgroundColor: isMaster
                  ? SaturdayColors.info.withValues(alpha: 0.1)
                  : null,
            );
          }).toList(),
        ),
        if (socTypes.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            'Multi-SoC device: Master handles OTA and pulls firmware for secondary SoCs',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondaryGrey,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildCapabilitiesSection(
      BuildContext context, AsyncValue<List<Capability>> capabilitiesAsync) {
    return _Section(
      title: 'Capabilities',
      children: [
        capabilitiesAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SaturdayColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Error loading capabilities: $error',
              style: TextStyle(color: SaturdayColors.error),
            ),
          ),
          data: (capabilities) {
            if (capabilities.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline,
                        color: SaturdayColors.secondaryGrey),
                    const SizedBox(width: 8),
                    const Text('No capabilities assigned'),
                  ],
                ),
              );
            }

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: capabilities.map((capability) {
                return ActionChip(
                  avatar: Icon(
                    Icons.check,
                    size: 16,
                    color: SaturdayColors.primaryDark,
                  ),
                  label: Text(capability.displayName),
                  backgroundColor: SaturdayColors.info.withValues(alpha: 0.1),
                  onPressed: () => _showCapabilityDetails(context, capability),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFirmwareSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Firmware>> firmwareAsync,
    bool canManage,
  ) {
    return _Section(
      title: 'Firmware Versions',
      trailing: canManage
          ? TextButton.icon(
              onPressed: () => _showCreateFirmwareDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            )
          : null,
      children: [
        // Current firmware assignments
        if (deviceType.productionFirmwareId != null ||
            deviceType.devFirmwareId != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: SaturdayColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: SaturdayColors.success.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Assignments',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                if (deviceType.productionFirmwareId != null)
                  _buildFirmwareAssignmentRow(
                    context,
                    ref,
                    'Production',
                    deviceType.productionFirmwareId!,
                    Icons.verified,
                    SaturdayColors.success,
                  ),
                if (deviceType.devFirmwareId != null)
                  _buildFirmwareAssignmentRow(
                    context,
                    ref,
                    'Development',
                    deviceType.devFirmwareId!,
                    Icons.developer_mode,
                    SaturdayColors.info,
                  ),
              ],
            ),
          ),
        ],

        // All firmware versions
        firmwareAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SaturdayColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Error loading firmware: $error',
              style: TextStyle(color: SaturdayColors.error),
            ),
          ),
          data: (firmwareList) {
            if (firmwareList.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(Icons.memory,
                        size: 48, color: SaturdayColors.secondaryGrey),
                    const SizedBox(height: 8),
                    const Text('No firmware versions yet'),
                    if (canManage) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _showCreateFirmwareDialog(context, ref),
                        icon: const Icon(Icons.add),
                        label: const Text('Create First Version'),
                      ),
                    ],
                  ],
                ),
              );
            }

            // Sort by version (newest first) and released status
            final sorted = List<Firmware>.from(firmwareList)
              ..sort((a, b) {
                // Released first, then by created date
                if (a.releasedAt != null && b.releasedAt == null) return -1;
                if (a.releasedAt == null && b.releasedAt != null) return 1;
                return b.createdAt.compareTo(a.createdAt);
              });

            return Column(
              children: sorted.map((firmware) {
                final isProduction =
                    firmware.id == deviceType.productionFirmwareId;
                final isDev = firmware.id == deviceType.devFirmwareId;
                final isReleased = firmware.releasedAt != null;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: isProduction
                      ? SaturdayColors.success.withValues(alpha: 0.05)
                      : isDev
                          ? SaturdayColors.info.withValues(alpha: 0.05)
                          : null,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isReleased
                          ? SaturdayColors.success.withValues(alpha: 0.1)
                          : SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
                      child: Icon(
                        isReleased ? Icons.verified : Icons.developer_mode,
                        color: isReleased
                            ? SaturdayColors.success
                            : SaturdayColors.secondaryGrey,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          firmware.version,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (firmware.isCritical) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: SaturdayColors.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'CRITICAL',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 9),
                            ),
                          ),
                        ],
                        if (isProduction) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: SaturdayColors.success,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'PROD',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 9),
                            ),
                          ),
                        ],
                        if (isDev && !isProduction) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: SaturdayColors.info,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'DEV',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 9),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isReleased
                              ? 'Released ${_formatDate(firmware.releasedAt!)}'
                              : 'Development',
                          style: TextStyle(
                            color: isReleased
                                ? SaturdayColors.success
                                : SaturdayColors.secondaryGrey,
                            fontSize: 12,
                          ),
                        ),
                        if (firmware.files.isNotEmpty)
                          Text(
                            '${firmware.files.length} file(s): ${firmware.files.map((f) => f.socType.toUpperCase()).join(', ')}',
                            style: TextStyle(
                              color: SaturdayColors.secondaryGrey,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showFirmwareDetails(context, ref, firmware),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFirmwareAssignmentRow(
    BuildContext context,
    WidgetRef ref,
    String label,
    String firmwareId,
    IconData icon,
    Color color,
  ) {
    final firmwareAsync = ref.watch(firmwareByIdProvider(firmwareId));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text('$label: '),
          firmwareAsync.when(
            loading: () => const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (_, __) => const Text('Error'),
            data: (firmware) => Text(
              firmware?.version ?? 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataSection(BuildContext context) {
    return _Section(
      title: 'Metadata',
      children: [
        _InfoRow(
          label: 'ID',
          value: deviceType.id,
          icon: Icons.fingerprint,
        ),
        _InfoRow(
          label: 'Created',
          value: _formatDate(deviceType.createdAt),
        ),
        _InfoRow(
          label: 'Last Updated',
          value: _formatDate(deviceType.updatedAt),
        ),
      ],
    );
  }

  void _showCapabilityDetails(BuildContext context, Capability capability) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.extension, color: SaturdayColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      capability.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              if (capability.description != null) ...[
                const SizedBox(height: 8),
                Text(capability.description!),
              ],
              const SizedBox(height: 24),
              if (capability.tests.isNotEmpty) ...[
                Text(
                  'Tests (${capability.tests.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...capability.tests.map((test) => Card(
                      child: ListTile(
                        leading:
                            Icon(Icons.science, color: SaturdayColors.info),
                        title: Text(test.displayName),
                        subtitle: test.description != null
                            ? Text(test.description!)
                            : null,
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showFirmwareDetails(
      BuildContext context, WidgetRef ref, Firmware firmware) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    firmware.releasedAt != null
                        ? Icons.verified
                        : Icons.developer_mode,
                    color: firmware.releasedAt != null
                        ? SaturdayColors.success
                        : SaturdayColors.secondaryGrey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Firmware ${firmware.version}',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    onPressed: () =>
                        _downloadFirmwareJson(sheetContext, ref, firmware),
                    tooltip: 'Download Firmware JSON',
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () =>
                        _navigateToEditFirmware(sheetContext, ref, firmware),
                    tooltip: 'Edit Firmware',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _InfoRow(
                label: 'Status',
                value: firmware.releasedAt != null ? 'Released' : 'Development',
              ),
              if (firmware.releasedAt != null)
                _InfoRow(
                  label: 'Released',
                  value: _formatDate(firmware.releasedAt!),
                ),
              _InfoRow(
                label: 'Critical Update',
                value: firmware.isCritical ? 'Yes' : 'No',
              ),
              _InfoRow(
                label: 'Created',
                value: _formatDate(firmware.createdAt),
              ),
              const SizedBox(height: 16),
              Text(
                'Files (${firmware.files.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (firmware.files.isEmpty)
                const Text('No files uploaded yet')
              else
                ...firmware.files.map((file) => Card(
                      child: ListTile(
                        leading: Icon(
                          file.isMaster ? Icons.star : Icons.memory,
                          color: file.isMaster
                              ? Colors.orange
                              : SaturdayColors.secondaryGrey,
                        ),
                        title: Text(file.socType.toUpperCase()),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (file.isMaster)
                              Text(
                                'Master (pushed via OTA)',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11,
                                ),
                              ),
                            if (file.fileSize != null)
                              Text(
                                  '${(file.fileSize! / 1024).toStringAsFixed(1)} KB'),
                          ],
                        ),
                        trailing: file.fileUrl.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.download),
                                onPressed: () => _launchUrl(file.fileUrl),
                              )
                            : null,
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateFirmwareDialog(BuildContext context, WidgetRef ref) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FirmwareFormScreen(deviceTypeId: deviceType.id),
      ),
    );

    if (result == true) {
      ref.invalidate(firmwareByDeviceTypeProvider(deviceType.id));
    }
  }

  void _navigateToEditFirmware(
      BuildContext context, WidgetRef ref, Firmware firmware) async {
    Navigator.pop(context); // Close the bottom sheet

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => FirmwareFormScreen(firmware: firmware),
      ),
    );

    if (result == true) {
      ref.invalidate(firmwareByDeviceTypeProvider(deviceType.id));
    }
  }

  Future<void> _downloadFirmwareJson(
      BuildContext context, WidgetRef ref, Firmware firmware) async {
    try {
      // Refresh capabilities to get latest schema changes
      ref.invalidate(capabilitiesForDeviceTypeProvider(deviceType.id));
      final capabilities =
          await ref.read(capabilitiesForDeviceTypeProvider(deviceType.id).future);

      // Build the firmware JSON
      final firmwareJson = _buildFirmwareJson(firmware, capabilities);
      final jsonString = const JsonEncoder.withIndent('  ').convert(firmwareJson);

      // Show options dialog
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Firmware ${firmware.version} JSON'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: SaturdayColors.primaryDark.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SaturdayColors.secondaryGrey),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        jsonString,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: jsonString));
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _saveFirmwareJson(context, firmware, jsonString);
              },
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to generate firmware JSON: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  /// Build simplified firmware JSON schema for firmware developers
  ///
  /// Output format:
  /// {
  ///   "version": "0.5.1",
  ///   "device_type": "hub-prototype",
  ///   "capabilities": {
  ///     "wifi": {
  ///       "factory_input": { ... },
  ///       "consumer_input": { ... },
  ///       "tests": { "connect": { "params": {...}, "result": {...} } }
  ///     }
  ///   }
  /// }
  Map<String, dynamic> _buildFirmwareJson(
      Firmware firmware, List<Capability> capabilities) {
    // Build capabilities map with schemas only (no display_name/description)
    final capabilitiesMap = <String, dynamic>{};
    for (final cap in capabilities) {
      final capData = <String, dynamic>{};

      if (cap.factoryInputSchema.isNotEmpty) {
        capData['factory_input'] = cap.factoryInputSchema;
      }
      if (cap.factoryOutputSchema.isNotEmpty) {
        capData['factory_output'] = cap.factoryOutputSchema;
      }
      if (cap.consumerInputSchema.isNotEmpty) {
        capData['consumer_input'] = cap.consumerInputSchema;
      }
      if (cap.consumerOutputSchema.isNotEmpty) {
        capData['consumer_output'] = cap.consumerOutputSchema;
      }
      if (cap.heartbeatSchema.isNotEmpty) {
        capData['heartbeat'] = cap.heartbeatSchema;
      }
      if (cap.tests.isNotEmpty) {
        // Tests as object keyed by name (more compact, direct access)
        final testsMap = <String, dynamic>{};
        for (final t in cap.tests) {
          final testData = <String, dynamic>{};
          if (t.parametersSchema.isNotEmpty) {
            testData['params'] = t.parametersSchema;
          }
          if (t.resultSchema.isNotEmpty) {
            testData['result'] = t.resultSchema;
          }
          testsMap[t.name] = testData;
        }
        capData['tests'] = testsMap;
      }

      if (capData.isNotEmpty) {
        capabilitiesMap[cap.name] = capData;
      }
    }

    // Simplified 3-field schema
    return {
      'version': firmware.version,
      'device_type': deviceType.slug,
      'capabilities': capabilitiesMap,
    };
  }

  Future<void> _saveFirmwareJson(
      BuildContext context, Firmware firmware, String jsonString) async {
    try {
      final fileName =
          '${deviceType.slug}_v${firmware.version.replaceAll('.', '_')}.json';

      // Use file picker to get save location
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Firmware JSON',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsString(jsonString);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved to $result'),
              backgroundColor: SaturdayColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
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
  final Widget? trailing;

  const _Section({
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (trailing != null) trailing!,
            ],
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
                    decoration: onTap != null ? TextDecoration.underline : null,
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
