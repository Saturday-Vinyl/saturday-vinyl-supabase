import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/firmware_provider.dart';

/// Widget for configuring firmware provisioning step parameters
///
/// Note: Provisioning manifests are now embedded in firmware binaries and
/// retrieved via the get_manifest command in Service Mode. This widget only
/// handles firmware version selection for the step.
class FirmwareProvisioningConfig extends ConsumerWidget {
  /// The product's device type ID (for filtering firmware versions)
  final String? deviceTypeId;

  /// Currently selected firmware version ID
  final String? selectedFirmwareVersionId;

  /// Callback when firmware version is changed
  final ValueChanged<String?> onFirmwareVersionChanged;

  const FirmwareProvisioningConfig({
    super.key,
    this.deviceTypeId,
    this.selectedFirmwareVersionId,
    required this.onFirmwareVersionChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Text(
          'Firmware Configuration',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select the firmware version to flash during this step. '
          'The provisioning manifest is embedded in the firmware and retrieved via Service Mode.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
        const SizedBox(height: 16),

        // Firmware Version Selector
        _buildFirmwareSelector(context, ref),

        // Selected firmware info
        if (selectedFirmwareVersionId != null) ...[
          const SizedBox(height: 16),
          _buildFirmwareInfo(context, ref),
        ],
      ],
    );
  }

  Widget _buildFirmwareSelector(BuildContext context, WidgetRef ref) {
    // Get firmware versions for the device type
    final firmwareAsync = deviceTypeId != null
        ? ref.watch(firmwareVersionsByDeviceTypeProvider(deviceTypeId!))
        : ref.watch(firmwareVersionsProvider);

    return firmwareAsync.when(
      data: (firmwareVersions) {
        final versions = firmwareVersions.toList();

        if (versions.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    deviceTypeId != null
                        ? 'No firmware versions available for this device type. Upload firmware in the Firmware section first.'
                        : 'No firmware versions available. Upload firmware in the Firmware section first.',
                    style: TextStyle(color: Colors.orange[900]),
                  ),
                ),
              ],
            ),
          );
        }

        return DropdownButtonFormField<String>(
          value: selectedFirmwareVersionId,
          decoration: const InputDecoration(
            labelText: 'Firmware Version',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.memory),
          ),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('-- Select Firmware --'),
            ),
            ...versions.map((fw) => DropdownMenuItem<String>(
                  value: fw.id,
                  child: Row(
                    children: [
                      Text(fw.version),
                      if (fw.isProductionReady) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: SaturdayColors.success,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PROD',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                )),
          ],
          onChanged: onFirmwareVersionChanged,
          validator: (value) {
            if (value == null) {
              return 'Please select a firmware version';
            }
            return null;
          },
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.error, color: Colors.red[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Failed to load firmware versions: $error',
                style: TextStyle(color: Colors.red[900]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirmwareInfo(BuildContext context, WidgetRef ref) {
    final firmwareAsync =
        ref.watch(firmwareVersionProvider(selectedFirmwareVersionId!));

    return firmwareAsync.when(
      data: (firmware) {
        if (firmware == null) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SaturdayColors.light,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SaturdayColors.secondaryGrey),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Firmware Details',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _infoRow(context, 'Version', firmware.version),
              if (firmware.releaseNotes != null && firmware.releaseNotes!.isNotEmpty)
                _infoRow(context, 'Release Notes', firmware.releaseNotes!),
              if (firmware.binarySize != null)
                _infoRow(context, 'Binary Size', _formatBytes(firmware.binarySize!)),
              _infoRow(
                context,
                'Production Ready',
                firmware.isProductionReady ? 'Yes' : 'No',
              ),

              // Device type info
              _buildDeviceTypeInfo(context, ref, firmware),

              const Divider(height: 24),

              // Info about manifest
              Row(
                children: [
                  Icon(Icons.code, size: 16, color: SaturdayColors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Provisioning manifest is embedded in firmware. '
                      'Use Service Mode to view and configure device.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.info,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildDeviceTypeInfo(
      BuildContext context, WidgetRef ref, FirmwareVersion firmware) {
    final deviceTypeAsync = ref.watch(deviceTypeProvider(firmware.deviceTypeId));

    return deviceTypeAsync.when(
      data: (deviceType) {
        if (deviceType == null) return const SizedBox.shrink();
        return Column(
          children: [
            _infoRow(context, 'Device Type', deviceType.name),
            if (deviceType.chipType != null)
              _infoRow(context, 'Chip Type', deviceType.chipType!.toUpperCase()),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
