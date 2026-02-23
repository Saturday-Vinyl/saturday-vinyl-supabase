import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/capability.dart';
import 'package:saturday_app/models/connected_device.dart';
import 'package:saturday_app/models/device_communication_state.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/models/firmware.dart';
import 'package:saturday_app/providers/capability_provider.dart';
import 'package:saturday_app/providers/device_communication_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/firmware_provider.dart';

/// Panel displaying device commands based on capabilities.
///
/// Sections:
/// - Global commands (reboot, factory reset, consumer reset)
/// - OTA update (if firmware version mismatch)
/// - Device-specific variables (factory_input from capabilities)
/// - Device-specific commands (commands from capabilities)
class DeviceCommandPanel extends ConsumerStatefulWidget {
  final ConnectedDevice device;
  final DeviceCommunicationState state;

  const DeviceCommandPanel({
    super.key,
    required this.device,
    required this.state,
  });

  @override
  ConsumerState<DeviceCommandPanel> createState() => _DeviceCommandPanelState();
}

enum _FirmwareChannel { production, development }

class _DeviceCommandPanelState extends ConsumerState<DeviceCommandPanel> {
  bool _isExecuting = false;
  String? _lastCommandResult;
  _FirmwareChannel _selectedChannel = _FirmwareChannel.production;

  @override
  Widget build(BuildContext context) {
    // Get device type by slug
    final deviceTypeAsync = ref.watch(
      deviceTypeBySlugProvider(widget.device.deviceType),
    );

    return deviceTypeAsync.when(
      data: (deviceType) {
        if (deviceType == null) {
          return _buildNoDeviceType();
        }
        return _buildCommandSections(deviceType);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildError('Failed to load device type: $e'),
    );
  }

  Widget _buildNoDeviceType() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: SaturdayColors.warning),
                const SizedBox(width: 8),
                const Text(
                  'Unknown Device Type',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Device type "${widget.device.deviceType}" not found in database. '
              'Only global commands are available.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 16),
            _buildGlobalCommands(),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Card(
      color: SaturdayColors.error.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: SaturdayColors.error),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandSections(DeviceType deviceType) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Global Commands
        _buildSection(
          title: 'Global Commands',
          icon: Icons.settings,
          child: _buildGlobalCommands(),
        ),

        const SizedBox(height: 16),

        // OTA Update
        _buildOtaSection(deviceType),

        const SizedBox(height: 16),

        // Capability-based sections
        _buildCapabilitySections(deviceType),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
    Color? iconColor,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: iconColor ?? SaturdayColors.info),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalCommands() {
    final notifier = ref.read(deviceCommunicationStateProvider.notifier);
    final canExecute = widget.state.phase.canSendCommands && !_isExecuting;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _CommandButton(
          label: 'Refresh Status',
          icon: Icons.refresh,
          onPressed: canExecute ? () => notifier.refreshStatus() : null,
        ),
        _CommandButton(
          label: 'Reboot',
          icon: Icons.restart_alt,
          onPressed: canExecute ? () => _confirmAndExecute(
            'Reboot Device',
            'This will restart the device. Continue?',
            () => notifier.reboot(),
          ) : null,
        ),
        _CommandButton(
          label: 'Consumer Reset',
          icon: Icons.person_off,
          color: SaturdayColors.warning,
          onPressed: canExecute ? () => _confirmAndExecute(
            'Consumer Reset',
            'This will clear consumer data but preserve factory settings. Continue?',
            () => notifier.consumerReset(),
          ) : null,
        ),
        _CommandButton(
          label: 'Factory Reset',
          icon: Icons.warning,
          color: SaturdayColors.error,
          onPressed: canExecute ? () => _confirmAndExecute(
            'Factory Reset',
            'WARNING: This will erase ALL device data including factory settings. '
            'The device will need to be re-provisioned. Continue?',
            () => notifier.factoryReset(),
          ) : null,
        ),
      ],
    );
  }

  Widget _buildOtaSection(DeviceType deviceType) {
    final prodFirmwareAsync = ref.watch(
      latestReleasedFirmwareProvider(deviceType.id),
    );
    final devFirmwareAsync = ref.watch(
      latestDevFirmwareProvider(deviceType.id),
    );

    final isDev = _selectedChannel == _FirmwareChannel.development;
    final firmwareAsync = isDev ? devFirmwareAsync : prodFirmwareAsync;

    return _buildSection(
      title: 'OTA Update',
      icon: Icons.system_update,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Channel selector
          SegmentedButton<_FirmwareChannel>(
            segments: const [
              ButtonSegment(
                value: _FirmwareChannel.production,
                label: Text('Production'),
                icon: Icon(Icons.verified, size: 16),
              ),
              ButtonSegment(
                value: _FirmwareChannel.development,
                label: Text('Development'),
                icon: Icon(Icons.science, size: 16),
              ),
            ],
            selected: {_selectedChannel},
            onSelectionChanged: (selection) {
              setState(() => _selectedChannel = selection.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Firmware details
          firmwareAsync.when(
            data: (firmware) => _buildFirmwareDetails(firmware, isDev),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error loading firmware: $e'),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmwareDetails(Firmware? firmware, bool isDev) {
    if (firmware == null) {
      return Text(
        isDev
            ? 'No development firmware available for this device type.'
            : 'No production firmware available for this device type.',
        style: TextStyle(color: Colors.grey[600], fontSize: 13),
      );
    }

    final currentVersion = widget.device.firmwareVersion;
    final targetVersion = firmware.version;
    final isUpToDate = currentVersion == targetVersion;
    final channelColor = isDev ? SaturdayColors.warning : SaturdayColors.info;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dev firmware warning
        if (isDev)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: SaturdayColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: SaturdayColors.warning),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber,
                  color: SaturdayColors.warning, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Development firmware - not released for production',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Version comparison
        Row(
          children: [
            _buildVersionChip('Current', currentVersion,
              isUpToDate ? SaturdayColors.success : Colors.grey),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 16),
            const SizedBox(width: 8),
            _buildVersionChip(
              isDev ? 'Dev' : 'Latest',
              targetVersion,
              channelColor,
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (isUpToDate)
          Row(
            children: [
              Icon(Icons.check_circle,
                color: SaturdayColors.success, size: 18),
              const SizedBox(width: 8),
              Text(isDev
                ? 'Device is running this dev version'
                : 'Device is up to date'),
            ],
          )
        else ...[
          // Critical update banner (production only)
          if (!isDev && firmware.isCritical)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: SaturdayColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: SaturdayColors.error),
              ),
              child: Row(
                children: [
                  Icon(Icons.priority_high,
                    color: SaturdayColors.error, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Critical update available!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // Release notes
          if (firmware.releaseNotes != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                firmware.releaseNotes!,
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // Update button
          ElevatedButton.icon(
            onPressed: widget.state.phase.canSendCommands && !_isExecuting
                ? () => _startOtaUpdate(firmware)
                : null,
            icon: const Icon(Icons.download, size: 18),
            label: Text(isDev
                ? 'Flash dev v$targetVersion'
                : 'Update to v$targetVersion'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDev
                  ? SaturdayColors.warning
                  : SaturdayColors.primaryDark,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVersionChip(String label, String version, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        '$label: v$version',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCapabilitySections(DeviceType deviceType) {
    final capabilitiesAsync = ref.watch(
      capabilitiesForDeviceTypeProvider(deviceType.id),
    );

    return capabilitiesAsync.when(
      data: (capabilities) {
        if (capabilities.isEmpty) {
          return const SizedBox.shrink();
        }

        final commandsSection = _buildCommandsSection(capabilities);
        final variablesSection = _buildVariablesSection(capabilities);

        return Column(
          children: [
            if (commandsSection != null) ...[
              commandsSection,
              const SizedBox(height: 16),
            ],
            if (variablesSection != null) variablesSection,
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _buildError('Failed to load capabilities: $e'),
    );
  }

  Widget? _buildCommandsSection(List<Capability> capabilities) {
    // Collect all commands from all capabilities
    final allCommands = <CapabilityCommand>[];
    for (final cap in capabilities) {
      for (final command in cap.commands) {
        allCommands.add(command);
      }
    }

    if (allCommands.isEmpty) {
      return null;
    }

    return _buildSection(
      title: 'Device Commands',
      icon: Icons.terminal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_lastCommandResult != null)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _lastCommandResult!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: allCommands.map((command) {
              return _CommandButton(
                label: command.displayName,
                icon: Icons.play_arrow,
                color: SaturdayColors.info,
                onPressed: widget.state.phase.canSendCommands && !_isExecuting
                    ? () => _runCommand(command)
                    : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget? _buildVariablesSection(List<Capability> capabilities) {
    // Collect capabilities that have factory input schemas
    final capsWithInput = capabilities
        .where((c) => c.hasFactoryInput)
        .toList();

    if (capsWithInput.isEmpty) {
      return null;
    }

    return _buildSection(
      title: 'Device Variables',
      icon: Icons.tune,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Variables can be set via the factory_provision or set_provision_data commands.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          const SizedBox(height: 12),
          ...capsWithInput.map((cap) => _buildCapabilityVariables(cap)),
        ],
      ),
    );
  }

  Widget _buildCapabilityVariables(Capability capability) {
    final schema = capability.factoryInputSchema;
    final properties = schema['properties'] as Map<String, dynamic>?;
    if (properties == null || properties.isEmpty) {
      return const SizedBox.shrink();
    }

    return ExpansionTile(
      title: Text(
        capability.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
      children: properties.entries.map((entry) {
        final propName = entry.key;
        final propSchema = entry.value as Map<String, dynamic>;
        final type = propSchema['type'] as String? ?? 'unknown';
        final description = propSchema['description'] as String?;

        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            propName,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
          subtitle: description != null
              ? Text(description, style: const TextStyle(fontSize: 11))
              : null,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              type,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[700],
                fontFamily: 'monospace',
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _confirmAndExecute(
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SaturdayColors.primaryDark,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isExecuting = true);
      try {
        await action();
      } finally {
        if (mounted) {
          setState(() => _isExecuting = false);
        }
      }
    }
  }

  Future<void> _runCommand(CapabilityCommand command) async {
    setState(() {
      _isExecuting = true;
      _lastCommandResult = null;
    });

    try {
      final notifier = ref.read(deviceCommunicationStateProvider.notifier);
      final result = await notifier.runCommand(command.name);

      if (mounted) {
        setState(() {
          _lastCommandResult = result.passed
              ? 'PASSED: ${command.displayName}\n${result.message ?? ''}'
              : 'FAILED: ${command.displayName}\n${result.message ?? 'Unknown error'}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isExecuting = false);
      }
    }
  }

  Future<void> _startOtaUpdate(Firmware firmware) async {
    // TODO: Implement OTA update
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OTA update not yet implemented'),
        backgroundColor: SaturdayColors.warning,
      ),
    );
  }
}

/// Reusable command button widget
class _CommandButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  const _CommandButton({
    required this.label,
    required this.icon,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final buttonColor = color ?? SaturdayColors.primaryDark;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: onPressed != null ? buttonColor : Colors.grey,
        side: BorderSide(
          color: onPressed != null ? buttonColor : Colors.grey[300]!,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
