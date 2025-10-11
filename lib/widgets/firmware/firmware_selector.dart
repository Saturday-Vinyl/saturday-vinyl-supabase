import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/providers/firmware_provider.dart';

/// Dropdown widget for selecting firmware version for a device type
class FirmwareSelector extends ConsumerWidget {
  final String deviceTypeId;
  final String? selectedFirmwareId;
  final ValueChanged<String?> onChanged;
  final String? recommendedFirmwareId;

  const FirmwareSelector({
    super.key,
    required this.deviceTypeId,
    required this.selectedFirmwareId,
    required this.onChanged,
    this.recommendedFirmwareId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firmwareAsync = ref.watch(
      firmwareVersionsByDeviceTypeProvider(deviceTypeId),
    );

    return firmwareAsync.when(
      data: (firmwareVersions) {
        if (firmwareVersions.isEmpty) {
          return Card(
            color: SaturdayColors.error.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning,
                    color: SaturdayColors.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No firmware versions available for this device type',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: SaturdayColors.error,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Sort firmware versions by version number (descending)
        final sortedFirmware = List<FirmwareVersion>.from(firmwareVersions)
          ..sort((a, b) => b.version.compareTo(a.version));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: selectedFirmwareId,
              decoration: const InputDecoration(
                labelText: 'Firmware Version',
                border: OutlineInputBorder(),
              ),
              items: sortedFirmware.map((firmware) {
                final isRecommended = firmware.id == recommendedFirmwareId;
                return DropdownMenuItem<String>(
                  value: firmware.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'v${firmware.version}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        fontWeight: isRecommended
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                ),
                                const SizedBox(width: 8),
                                if (firmware.isProductionReady)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: SaturdayColors.success
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Production',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: SaturdayColors.success,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                if (isRecommended)
                                  Container(
                                    margin: const EdgeInsets.only(left: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: SaturdayColors.info
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Recommended',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: SaturdayColors.info,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatDate(firmware.createdAt),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: SaturdayColors.secondaryGrey,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
            if (recommendedFirmwareId != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: SaturdayColors.info,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'The recommended version is the latest production-ready firmware',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, stack) => Card(
        color: SaturdayColors.error.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.error,
                color: SaturdayColors.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Failed to load firmware versions: $error',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SaturdayColors.error,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
