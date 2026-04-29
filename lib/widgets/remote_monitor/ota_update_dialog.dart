import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/models/firmware.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
import 'package:saturday_app/providers/remote_monitor_provider.dart';

/// Dialog for selecting and pushing a firmware OTA update to a device.
class OtaUpdateDialog extends ConsumerStatefulWidget {
  final Device device;
  final String unitId;

  const OtaUpdateDialog({
    super.key,
    required this.device,
    required this.unitId,
  });

  /// Show the dialog.
  static Future<void> show({
    required BuildContext context,
    required Device device,
    required String unitId,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => OtaUpdateDialog(
        device: device,
        unitId: unitId,
      ),
    );
  }

  @override
  ConsumerState<OtaUpdateDialog> createState() => _OtaUpdateDialogState();
}

class _OtaUpdateDialogState extends ConsumerState<OtaUpdateDialog> {
  Firmware? _selectedFirmware;
  bool _isSending = false;

  /// Resolve the OTA-pushable URL.
  ///
  /// OTA requires an app-only binary (purpose='ota'). The merged factory
  /// binary is unsuitable — esp_https_ota expects an app header at offset 0
  /// and will fail validation against a merged image.
  String? _getFirmwareUrl(Firmware firmware) {
    return firmware.masterOtaFile?.fileUrl;
  }

  bool _isCurrentVersion(Firmware firmware) {
    return widget.device.firmwareVersion != null &&
        firmware.version == widget.device.firmwareVersion;
  }

  Future<void> _pushUpdate() async {
    final firmware = _selectedFirmware;
    if (firmware == null) return;

    final firmwareUrl = _getFirmwareUrl(firmware);
    if (firmwareUrl == null) return;

    setState(() => _isSending = true);

    final result =
        await ref.read(remoteMonitorProvider(widget.unitId).notifier).sendOtaUpdate(
              macAddress: widget.device.macAddress,
              firmwareId: firmware.id,
              targetVersion: firmware.version,
              firmwareUrl: firmwareUrl,
            );

    if (!mounted) return;

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('OTA update command sent: v${firmware.version}'),
          backgroundColor: SaturdayColors.success,
        ),
      );
      Navigator.of(context).pop();
    } else {
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send OTA update command'),
          backgroundColor: SaturdayColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.device.deviceTypeSlug;
    if (slug == null) {
      return AlertDialog(
        title: const Text('OTA Update'),
        content: const Text('Device has no device type assigned.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    }

    final deviceTypeAsync = ref.watch(deviceTypeBySlugProvider(slug));

    return deviceTypeAsync.when(
      loading: () => const AlertDialog(
        content: SizedBox(
          height: 100,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => AlertDialog(
        title: const Text('OTA Update'),
        content: Text('Error loading device type: $error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
      data: (deviceType) {
        if (deviceType == null) {
          return AlertDialog(
            title: const Text('OTA Update'),
            content: Text('Device type "$slug" not found.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        }

        final firmwareAsync =
            ref.watch(firmwareByDeviceTypeProvider(deviceType.id));

        return firmwareAsync.when(
          loading: () => const AlertDialog(
            content: SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, _) => AlertDialog(
            title: const Text('OTA Update'),
            content: Text('Error loading firmware: $error'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
          data: (firmwareList) => _buildDialog(context, firmwareList),
        );
      },
    );
  }

  Widget _buildDialog(BuildContext context, List<Firmware> firmwareList) {
    // Sort by version descending (newest first)
    final sorted = List<Firmware>.from(firmwareList)
      ..sort((a, b) => b.version.compareTo(a.version));

    final selected = _selectedFirmware;
    final firmwareUrl = selected != null ? _getFirmwareUrl(selected) : null;
    final canPush = selected != null && firmwareUrl != null && !_isSending;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update, size: 24),
          const SizedBox(width: 8),
          const Expanded(child: Text('OTA Update')),
          if (widget.device.firmwareVersion != null)
            Chip(
              label: Text(
                'Current: v${widget.device.firmwareVersion}',
                style: const TextStyle(fontSize: 11),
              ),
              backgroundColor: SaturdayColors.info.withValues(alpha: 0.15),
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select firmware to push to ${widget.device.formattedMacAddress}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 12),

            // Firmware list
            Expanded(
              child: sorted.isEmpty
                  ? Center(
                      child: Text(
                        'No firmware available for this device type.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    )
                  : ListView.separated(
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _buildFirmwareItem(sorted[index]),
                    ),
            ),

            // Selected firmware detail
            if (selected != null) ...[
              const Divider(),
              _buildSelectionDetail(selected, firmwareUrl),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: canPush ? _pushUpdate : null,
          icon: _isSending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.upload, size: 18),
          label: Text(_isSending
              ? 'Sending...'
              : selected != null && _isCurrentVersion(selected)
                  ? 'Re-install'
                  : 'Push Update'),
          style: ElevatedButton.styleFrom(
            backgroundColor: SaturdayColors.primaryDark,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildFirmwareItem(Firmware firmware) {
    final isSelected = _selectedFirmware?.id == firmware.id;
    final isCurrent = _isCurrentVersion(firmware);
    final otaFile = firmware.masterOtaFile;
    final hasOtaBinary = otaFile != null;

    return ListTile(
      selected: isSelected,
      selectedTileColor: SaturdayColors.primaryDark.withValues(alpha: 0.08),
      onTap: () => setState(() => _selectedFirmware = firmware),
      dense: true,
      title: Row(
        children: [
          Text(
            'v${firmware.version}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          if (isCurrent) _badge('Current', SaturdayColors.info),
          if (firmware.isReleased)
            _badge('Released', SaturdayColors.success)
          else
            _badge('Dev', SaturdayColors.warning),
          if (firmware.isCritical) _badge('Critical', SaturdayColors.error),
          if (!hasOtaBinary) _badge('No OTA binary', SaturdayColors.error),
        ],
      ),
      subtitle: Row(
        children: [
          if (otaFile != null) ...[
            Text(
              '${otaFile.socType} ${otaFile.formattedSize}',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
            const SizedBox(width: 8),
          ],
          if (firmware.releaseNotes != null &&
              firmware.releaseNotes!.isNotEmpty)
            Expanded(
              child: Text(
                firmware.releaseNotes!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ),
        ],
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: SaturdayColors.primaryDark)
          : null,
    );
  }

  Widget _buildSelectionDetail(Firmware firmware, String? firmwareUrl) {
    final isCurrent = _isCurrentVersion(firmware);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Version comparison
        Row(
          children: [
            if (widget.device.firmwareVersion != null) ...[
              Text(
                'v${widget.device.firmwareVersion}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  isCurrent ? Icons.refresh : Icons.arrow_forward,
                  size: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
            Text(
              'v${firmware.version}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: isCurrent ? SaturdayColors.info : SaturdayColors.success,
              ),
            ),
            if (isCurrent)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '(re-install)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),

        // Release notes
        if (firmware.releaseNotes != null &&
            firmware.releaseNotes!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            firmware.releaseNotes!,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],

        // Warning if no OTA-purpose binary exists
        if (firmwareUrl == null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: SaturdayColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: SaturdayColors.error.withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber,
                    size: 16, color: SaturdayColors.error),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'No OTA binary uploaded for this firmware. '
                    'Edit the firmware and upload the app-only binary '
                    '(purpose: ota) before pushing.',
                    style: TextStyle(
                      fontSize: 12,
                      color: SaturdayColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _badge(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
