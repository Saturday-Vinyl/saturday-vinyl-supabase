import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/connected_device.dart';
import 'package:saturday_app/models/device_communication_state.dart';
import 'package:saturday_app/providers/device_communication_provider.dart';
import 'package:saturday_app/widgets/device_communication/device_command_panel.dart';
import 'package:saturday_app/widgets/device_communication/unit_selection_dialog.dart';
import 'package:saturday_app/widgets/common/log_display.dart';

/// Screen for communicating with a connected Saturday device.
///
/// This replaces the legacy Service Mode screen with a simplified UX
/// aligned with the Device Command Protocol (always-listening architecture).
class DeviceCommunicationScreen extends ConsumerStatefulWidget {
  /// Optional: Pre-selected device from USB indicator
  final ConnectedDevice? initialDevice;

  /// Optional: Port name to connect to
  final String? portName;

  const DeviceCommunicationScreen({
    super.key,
    this.initialDevice,
    this.portName,
  });

  @override
  ConsumerState<DeviceCommunicationScreen> createState() =>
      _DeviceCommunicationScreenState();
}

class _DeviceCommunicationScreenState
    extends ConsumerState<DeviceCommunicationScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Auto-connect if we have a device or port
      if (widget.initialDevice != null) {
        ref
            .read(deviceCommunicationStateProvider.notifier)
            .connectToDevice(widget.initialDevice!);
      } else if (widget.portName != null) {
        ref
            .read(deviceCommunicationStateProvider.notifier)
            .connectToPort(widget.portName!);
      }
    });
  }

  @override
  void dispose() {
    // Disconnect when leaving the screen
    ref.read(deviceCommunicationStateProvider.notifier).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceCommunicationStateProvider);
    final notifier = ref.read(deviceCommunicationStateProvider.notifier);
    final connectedDevices = ref.watch(connectedDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Communication'),
        actions: [
          if (state.isConnected)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: state.phase.isExecuting
                        ? SaturdayColors.warning
                        : SaturdayColors.success,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        state.phase.displayName,
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
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left panel - Controls
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Connection status and controls
                  if (state.isConnected || state.phase == DeviceCommunicationPhase.connecting)
                    _buildConnectionStatus(state, notifier)
                  else
                    _buildDeviceSelection(connectedDevices, state, notifier),

                  // Device info card
                  if (state.connectedDevice != null) ...[
                    const SizedBox(height: 16),
                    _DeviceInfoCard(
                      device: state.connectedDevice!,
                      unitNotFoundInDb: state.unitNotFoundInDb,
                    ),
                  ],

                  // Unit context card (with provision button if device is unprovisioned)
                  if (state.associatedUnit != null) ...[
                    const SizedBox(height: 16),
                    _UnitContextCard(
                      unit: state.associatedUnit!,
                      showProvisionButton: state.isUnprovisioned,
                      onProvision: state.isUnprovisioned
                          ? () => _startFactoryProvision(notifier, state.associatedUnit!)
                          : null,
                    ),
                  ] else if (state.isUnprovisioned) ...[
                    const SizedBox(height: 16),
                    _UnprovisionedCard(
                      onSelectUnit: () => _showUnitSelectionDialog(notifier),
                    ),
                  ],

                  // Device commands panel (capability-based)
                  if (state.isConnected && state.connectedDevice != null) ...[
                    const SizedBox(height: 16),
                    DeviceCommandPanel(
                      device: state.connectedDevice!,
                      state: state,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Right panel - Logs
          Expanded(
            flex: 1,
            child: Container(
              margin: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Logs',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: state.logLines.isNotEmpty
                            ? () => _copyLogsToClipboard(state.logLines)
                            : null,
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy All'),
                        style: TextButton.styleFrom(
                          foregroundColor: SaturdayColors.secondaryGrey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: state.logLines.isNotEmpty
                            ? () => notifier.clearLogs()
                            : null,
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Clear'),
                        style: TextButton.styleFrom(
                          foregroundColor: SaturdayColors.secondaryGrey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LogDisplay(
                      logLines: state.logLines,
                      hideBeacons: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelection(
    List<ConnectedDevice> devices,
    DeviceCommunicationState state,
    DeviceCommunicationNotifier notifier,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.usb, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Connect to Device',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No Saturday devices detected. Connect a device via USB.',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...devices.map((device) => _DeviceListTile(
                    device: device,
                    onConnect: () => notifier.connectToDevice(device),
                  )),

            // Manual port selector
            const Divider(height: 24),
            _ManualPortSelector(
              onConnect: (portName) => notifier.connectToPort(portName),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(
    DeviceCommunicationState state,
    DeviceCommunicationNotifier notifier,
  ) {
    final isConnecting = state.phase == DeviceCommunicationPhase.connecting;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isConnecting ? Icons.sync : Icons.check_circle,
                  size: 20,
                  color: isConnecting ? SaturdayColors.warning : SaturdayColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isConnecting ? 'Connecting...' : 'Connected',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Port:',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.portName ?? 'Unknown',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (state.connectedDevice != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Device:',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${state.connectedDevice!.deviceType} (${state.connectedDevice!.formattedMacAddress})',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => notifier.disconnect(),
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Disconnect'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SaturdayColors.error,
                  side: const BorderSide(color: SaturdayColors.error),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUnitSelectionDialog(
      DeviceCommunicationNotifier notifier) async {
    final state = ref.read(deviceCommunicationStateProvider);
    final connectedDevice = state.connectedDevice;

    if (connectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No device connected'),
          backgroundColor: SaturdayColors.error,
        ),
      );
      return;
    }

    // Get device type info
    final deviceTypeSlug = connectedDevice.deviceType;
    final deviceTypeName = _formatDeviceType(deviceTypeSlug);

    // Show the unit selection dialog
    final selectedUnit = await UnitSelectionDialog.show(
      context: context,
      deviceTypeSlug: deviceTypeSlug,
      deviceTypeName: deviceTypeName,
    );

    if (selectedUnit != null) {
      // Set the selected unit for provisioning
      notifier.setUnitForProvisioning(selectedUnit);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Selected unit: ${selectedUnit.serialNumber}'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    }
  }

  Future<void> _startFactoryProvision(
      DeviceCommunicationNotifier notifier, dynamic unit) async {
    // Confirm before provisioning
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Factory Provision'),
        content: Text(
          'This will provision the device with serial number:\n\n'
          '${unit.serialNumber}\n\n'
          'The device will be associated with this unit. Continue?',
        ),
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
            child: const Text('Provision'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // factoryProvision uses state.associatedUnit which is already set
      final success = await notifier.factoryProvision();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Device provisioned successfully!'
                : 'Provisioning failed. Check logs for details.'),
            backgroundColor: success ? SaturdayColors.success : SaturdayColors.error,
          ),
        );
      }
    }
  }

  String _formatDeviceType(String deviceType) {
    return deviceType
        .split('-')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
  }

  void _copyLogsToClipboard(List<String> logLines) {
    final text = logLines.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${logLines.length} log lines to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: SaturdayColors.success,
      ),
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  final ConnectedDevice device;
  final VoidCallback onConnect;

  const _DeviceListTile({
    required this.device,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        _getDeviceIcon(device.deviceType),
        color: SaturdayColors.info,
      ),
      title: Text(device.displayName),
      subtitle: Text(
        '${device.formattedMacAddress} - ${device.portName}',
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
      ),
      trailing: ElevatedButton(
        onPressed: onConnect,
        child: const Text('Connect'),
      ),
      contentPadding: EdgeInsets.zero,
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'hub':
      case 'hub-prototype':
        return Icons.router;
      case 'crate':
        return Icons.inventory_2;
      case 'speaker':
        return Icons.speaker;
      default:
        return Icons.developer_board;
    }
  }
}

/// Manual port selector for debugging when auto-detection fails
class _ManualPortSelector extends StatefulWidget {
  final void Function(String portName) onConnect;

  const _ManualPortSelector({required this.onConnect});

  @override
  State<_ManualPortSelector> createState() => _ManualPortSelectorState();
}

class _ManualPortSelectorState extends State<_ManualPortSelector> {
  List<String> _availablePorts = [];
  String? _selectedPort;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshPorts();
  }

  void _refreshPorts() {
    setState(() {
      _isLoading = true;
    });

    try {
      final ports = SerialPort.availablePorts;
      setState(() {
        _availablePorts = ports;
        _isLoading = false;
        // Auto-select first usbmodem port if available
        if (_selectedPort == null || !ports.contains(_selectedPort)) {
          _selectedPort = ports.firstWhere(
            (p) => p.contains('usbmodem') || p.contains('usbserial'),
            orElse: () => ports.isNotEmpty ? ports.first : '',
          );
          if (_selectedPort?.isEmpty ?? true) _selectedPort = null;
        }
      });
    } catch (e) {
      setState(() {
        _availablePorts = [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.settings_ethernet, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              'Manual Port Connection',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Colors.grey[700],
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _refreshPorts,
              icon: Icon(
                Icons.refresh,
                size: 18,
                color: Colors.grey[600],
              ),
              tooltip: 'Refresh port list',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Use this to connect to a port that wasn\'t auto-detected as a Saturday device.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        if (_isLoading)
          const Center(child: CircularProgressIndicator())
        else if (_availablePorts.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SaturdayColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: SaturdayColors.warning, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'No serial ports found. Make sure your device is connected.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedPort,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    labelText: 'Select Port',
                  ),
                  items: _availablePorts.map((port) {
                    // Highlight likely Saturday device ports
                    final isLikelySaturday =
                        port.contains('usbmodem') || port.contains('usbserial');
                    return DropdownMenuItem(
                      value: port,
                      child: Text(
                        port,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight:
                              isLikelySaturday ? FontWeight.bold : FontWeight.normal,
                          color: isLikelySaturday
                              ? SaturdayColors.info
                              : Colors.black87,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedPort = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _selectedPort != null
                    ? () => widget.onConnect(_selectedPort!)
                    : null,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Connect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SaturdayColors.primaryDark,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _DeviceInfoCard extends StatelessWidget {
  final ConnectedDevice device;
  final bool unitNotFoundInDb;

  const _DeviceInfoCard({
    required this.device,
    this.unitNotFoundInDb = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getDeviceIcon(device.deviceType),
                  size: 20,
                  color: SaturdayColors.info,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Device Info',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (device.isProvisioned)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: SaturdayColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SaturdayColors.success),
                    ),
                    child: const Text(
                      'PROVISIONED',
                      style: TextStyle(
                        color: SaturdayColors.success,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: SaturdayColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SaturdayColors.warning),
                    ),
                    child: const Text(
                      'UNPROVISIONED',
                      style: TextStyle(
                        color: SaturdayColors.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(context, 'Type', _formatDeviceType(device.deviceType),
                Icons.devices),
            _buildInfoRow(
                context, 'Firmware', 'v${device.firmwareVersion}', Icons.memory),
            _buildInfoRow(
                context, 'MAC Address', device.formattedMacAddress, Icons.router),
            if (device.serialNumber != null)
              _buildInfoRow(context, 'Serial Number', device.serialNumber!,
                  Icons.qr_code,
                  valueColor: unitNotFoundInDb ? SaturdayColors.error : SaturdayColors.success),

            // Warning if unit not found in database
            if (unitNotFoundInDb && device.serialNumber != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SaturdayColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: SaturdayColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Unit ${device.serialNumber} not found in database. It may have been deleted.',
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

            // System info from status data
            if (device.uptimeSec != null || device.freeHeap != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  if (device.uptimeSec != null)
                    Expanded(
                      child: _buildMiniInfo(
                        'Uptime',
                        _formatUptime(device.uptimeSec!),
                        Icons.timer,
                      ),
                    ),
                  if (device.freeHeap != null)
                    Expanded(
                      child: _buildMiniInfo(
                        'Free Heap',
                        _formatBytes(device.freeHeap!),
                        Icons.memory,
                      ),
                    ),
                  if (device.wifiRssi != null)
                    Expanded(
                      child: _buildMiniInfo(
                        'WiFi RSSI',
                        '${device.wifiRssi} dBm',
                        Icons.wifi,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfo(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
      ],
    );
  }

  IconData _getDeviceIcon(String deviceType) {
    switch (deviceType.toLowerCase()) {
      case 'hub':
      case 'hub-prototype':
        return Icons.router;
      case 'crate':
        return Icons.inventory_2;
      case 'speaker':
        return Icons.speaker;
      default:
        return Icons.developer_board;
    }
  }

  String _formatDeviceType(String deviceType) {
    return deviceType
        .split('-')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
  }

  String _formatUptime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${(seconds / 60).floor()}m';
    if (seconds < 86400) {
      return '${(seconds / 3600).floor()}h ${((seconds % 3600) / 60).floor()}m';
    }
    return '${(seconds / 86400).floor()}d ${((seconds % 86400) / 3600).floor()}h';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _UnitContextCard extends StatelessWidget {
  final dynamic unit; // Unit type
  final bool showProvisionButton;
  final VoidCallback? onProvision;

  const _UnitContextCard({
    required this.unit,
    this.showProvisionButton = false,
    this.onProvision,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  showProvisionButton ? Icons.inventory_2 : Icons.check_circle,
                  size: 20,
                  color: showProvisionButton
                      ? SaturdayColors.warning
                      : SaturdayColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    showProvisionButton ? 'Ready to Provision' : 'Unit Context',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text(
              unit.displayName ?? unit.serialNumber ?? 'Unknown Unit',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Serial: ${unit.serialNumber}',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
            if (showProvisionButton && onProvision != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onProvision,
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Factory Provision'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SaturdayColors.primaryDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnprovisionedCard extends StatelessWidget {
  final VoidCallback onSelectUnit;

  const _UnprovisionedCard({required this.onSelectUnit});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: SaturdayColors.warning.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, size: 20, color: SaturdayColors.warning),
                const SizedBox(width: 8),
                Text(
                  'Device Not Provisioned',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'This device needs to be associated with a unit before it can be provisioned.',
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onSelectUnit,
              icon: const Icon(Icons.add),
              label: const Text('Select Unit'),
            ),
          ],
        ),
      ),
    );
  }
}

