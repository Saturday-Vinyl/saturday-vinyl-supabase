import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/service_mode_manifest.dart';
import 'package:saturday_app/widgets/common/app_button.dart';
import 'package:uuid/uuid.dart';

/// Manifest Builder - Developer tool for creating Service Mode manifests
/// to embed in firmware. This generates JSON that gets compiled into the
/// firmware binary and is retrieved via the get_manifest command.
class ManifestEditorScreen extends ConsumerStatefulWidget {
  /// Optional: Existing manifest to edit
  final ServiceModeManifest? manifest;

  /// Firmware version string (for display)
  final String firmwareVersion;

  const ManifestEditorScreen({
    super.key,
    this.manifest,
    required this.firmwareVersion,
  });

  @override
  ConsumerState<ManifestEditorScreen> createState() =>
      _ManifestEditorScreenState();
}

class _ManifestEditorScreenState extends ConsumerState<ManifestEditorScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Basic info
  late TextEditingController _deviceTypeController;
  late TextEditingController _deviceNameController;
  late TextEditingController _firmwareIdController;
  late TextEditingController _firmwareVersionController;

  // Capabilities
  bool _wifiCapability = false;
  bool _bluetoothCapability = false;
  bool _threadCapability = false;
  bool _cloudCapability = false;
  bool _rfidCapability = false;
  bool _audioCapability = false;
  bool _displayCapability = false;
  bool _batteryCapability = false;
  bool _buttonCapability = false;

  // Provisioning fields
  List<String> _requiredFields = [];
  List<String> _optionalFields = [];

  // Supported tests
  List<String> _supportedTests = [];

  // Status fields
  List<String> _statusFields = [];

  // Custom commands
  List<CustomCommand> _customCommands = [];

  // LED patterns
  Map<String, LedPattern> _ledPatterns = {};

  // JSON preview
  bool _showJsonPreview = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);

    // Initialize controllers
    _deviceTypeController = TextEditingController();
    _deviceNameController = TextEditingController();
    _firmwareIdController = TextEditingController();
    _firmwareVersionController =
        TextEditingController(text: widget.firmwareVersion);

    // Initialize from existing manifest or create defaults
    if (widget.manifest != null) {
      final m = widget.manifest!;
      _deviceTypeController.text = m.deviceType;
      _deviceNameController.text = m.deviceName;
      _firmwareIdController.text = m.firmwareId ?? '';
      _firmwareVersionController.text = m.firmwareVersion;

      // Capabilities
      _wifiCapability = m.capabilities.wifi;
      _bluetoothCapability = m.capabilities.bluetooth;
      _threadCapability = m.capabilities.thread;
      _cloudCapability = m.capabilities.cloud;
      _rfidCapability = m.capabilities.rfid;
      _audioCapability = m.capabilities.audio;
      _displayCapability = m.capabilities.display;
      _batteryCapability = m.capabilities.battery;
      _buttonCapability = m.capabilities.button;

      // Provisioning fields
      _requiredFields = List.from(m.provisioningFields.required);
      _optionalFields = List.from(m.provisioningFields.optional);

      // Tests and status
      _supportedTests = List.from(m.supportedTests);
      _statusFields = List.from(m.statusFields);

      // Custom commands
      _customCommands = List.from(m.customCommands);

      // LED patterns
      _ledPatterns = Map.from(m.ledPatterns);
    } else {
      // Set defaults for new manifest
      _firmwareIdController.text = const Uuid().v4();
      _requiredFields = ['unit_id'];
      _optionalFields = ['wifi_ssid', 'wifi_password'];
      _supportedTests = ['wifi', 'cloud'];
      _statusFields = [
        'wifi_connected',
        'wifi_rssi',
        'cloud_connected',
        'uptime_ms',
        'free_heap'
      ];
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _deviceTypeController.dispose();
    _deviceNameController.dispose();
    _firmwareIdController.dispose();
    _firmwareVersionController.dispose();
    super.dispose();
  }

  ServiceModeManifest _buildManifest() {
    return ServiceModeManifest(
      manifestVersion: '1.0',
      deviceType: _deviceTypeController.text,
      deviceName: _deviceNameController.text,
      firmwareId: _firmwareIdController.text.isEmpty
          ? null
          : _firmwareIdController.text,
      firmwareVersion: _firmwareVersionController.text,
      capabilities: DeviceCapabilities(
        wifi: _wifiCapability,
        bluetooth: _bluetoothCapability,
        thread: _threadCapability,
        cloud: _cloudCapability,
        rfid: _rfidCapability,
        audio: _audioCapability,
        display: _displayCapability,
        battery: _batteryCapability,
        button: _buttonCapability,
      ),
      provisioningFields: ProvisioningFields(
        required: _requiredFields,
        optional: _optionalFields,
      ),
      supportedTests: _supportedTests,
      statusFields: _statusFields,
      customCommands: _customCommands,
      ledPatterns: _ledPatterns,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manifest Builder'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: SaturdayColors.white,
          unselectedLabelColor: SaturdayColors.secondaryGrey,
          indicatorColor: SaturdayColors.white,
          tabs: const [
            Tab(text: 'Basic Info'),
            Tab(text: 'Capabilities'),
            Tab(text: 'Provisioning'),
            Tab(text: 'Tests'),
            Tab(text: 'Advanced'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showJsonPreview ? Icons.edit : Icons.code),
            tooltip: _showJsonPreview ? 'Edit Mode' : 'JSON Preview',
            onPressed: () {
              setState(() {
                _showJsonPreview = !_showJsonPreview;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Info banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This tool generates JSON to embed in your firmware. '
                    'The manifest is retrieved via get_manifest command in Service Mode.',
                    style: TextStyle(color: Colors.blue[900], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: _showJsonPreview
                ? _buildJsonPreview()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildBasicInfoTab(),
                      _buildCapabilitiesTab(),
                      _buildProvisioningTab(),
                      _buildTestsTab(),
                      _buildAdvancedTab(),
                    ],
                  ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Copy JSON',
                    style: AppButtonStyle.secondary,
                    icon: Icons.copy,
                    onPressed: _copyJsonToClipboard,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppButton(
                    text: 'Download',
                    icon: Icons.download,
                    onPressed: _downloadJson,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copyJsonToClipboard() {
    final manifest = _buildManifest();
    final jsonString =
        const JsonEncoder.withIndent('  ').convert(manifest.toJson());
    Clipboard.setData(ClipboardData(text: jsonString));

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Manifest JSON copied to clipboard'),
        backgroundColor: SaturdayColors.success,
      ),
    );
  }

  void _downloadJson() {
    // For now, just copy to clipboard
    // In a full implementation, this would save to a file
    _copyJsonToClipboard();
  }

  Widget _buildJsonPreview() {
    final manifest = _buildManifest();
    final jsonString =
        const JsonEncoder.withIndent('  ').convert(manifest.toJson());

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.code, size: 20),
              const SizedBox(width: 8),
              Text(
                'JSON Output',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _copyJsonToClipboard,
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Embed this JSON in your firmware to be returned by get_manifest command.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondaryGrey,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  jsonString,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================
  // Tab 1: Basic Info
  // ===========================================
  Widget _buildBasicInfoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Device Identification',
            'Basic information about the device type and firmware',
          ),
          const SizedBox(height: 16),

          // Device Type
          TextFormField(
            controller: _deviceTypeController,
            decoration: const InputDecoration(
              labelText: 'Device Type *',
              border: OutlineInputBorder(),
              hintText: 'e.g., saturday_box, saturday_hub',
              helperText: 'Internal identifier used for matching',
            ),
          ),
          const SizedBox(height: 16),

          // Device Name
          TextFormField(
            controller: _deviceNameController,
            decoration: const InputDecoration(
              labelText: 'Device Name *',
              border: OutlineInputBorder(),
              hintText: 'e.g., Saturday Box, Saturday Hub',
              helperText: 'Human-readable name shown in UI',
            ),
          ),
          const SizedBox(height: 16),

          // Firmware ID
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firmwareIdController,
                  decoration: const InputDecoration(
                    labelText: 'Firmware ID (UUID)',
                    border: OutlineInputBorder(),
                    helperText: 'Links to firmware_versions table',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Generate new UUID',
                onPressed: () {
                  setState(() {
                    _firmwareIdController.text = const Uuid().v4();
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Firmware Version
          TextFormField(
            controller: _firmwareVersionController,
            decoration: const InputDecoration(
              labelText: 'Firmware Version *',
              border: OutlineInputBorder(),
              hintText: 'e.g., 1.0.0',
              helperText: 'Semantic version of the firmware',
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================
  // Tab 2: Capabilities
  // ===========================================
  Widget _buildCapabilitiesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Device Capabilities',
            'Hardware features available on this device',
          ),
          const SizedBox(height: 16),

          // Connectivity
          _buildCapabilitySection(
            'Connectivity',
            Icons.wifi,
            [
              _buildCapabilitySwitch('WiFi', _wifiCapability,
                  (v) => setState(() => _wifiCapability = v)),
              _buildCapabilitySwitch('Bluetooth', _bluetoothCapability,
                  (v) => setState(() => _bluetoothCapability = v)),
              _buildCapabilitySwitch('Thread', _threadCapability,
                  (v) => setState(() => _threadCapability = v)),
              _buildCapabilitySwitch('Cloud', _cloudCapability,
                  (v) => setState(() => _cloudCapability = v)),
            ],
          ),
          const SizedBox(height: 16),

          // Peripherals
          _buildCapabilitySection(
            'Peripherals',
            Icons.memory,
            [
              _buildCapabilitySwitch('RFID', _rfidCapability,
                  (v) => setState(() => _rfidCapability = v)),
              _buildCapabilitySwitch('Audio', _audioCapability,
                  (v) => setState(() => _audioCapability = v)),
              _buildCapabilitySwitch('Display', _displayCapability,
                  (v) => setState(() => _displayCapability = v)),
            ],
          ),
          const SizedBox(height: 16),

          // Power
          _buildCapabilitySection(
            'Power & Input',
            Icons.battery_charging_full,
            [
              _buildCapabilitySwitch('Battery', _batteryCapability,
                  (v) => setState(() => _batteryCapability = v)),
              _buildCapabilitySwitch('Button', _buttonCapability,
                  (v) => setState(() => _buttonCapability = v)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilitySection(
      String title, IconData icon, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilitySwitch(
      String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  // ===========================================
  // Tab 3: Provisioning
  // ===========================================
  Widget _buildProvisioningTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Required Provisioning Fields',
            'Fields that must be provided during provisioning',
          ),
          const SizedBox(height: 12),
          _buildStringListEditor(
            items: _requiredFields,
            onChanged: (items) => setState(() => _requiredFields = items),
            addLabel: 'Add Required Field',
            hintText: 'e.g., unit_id',
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(
            'Optional Provisioning Fields',
            'Fields that can optionally be provided',
          ),
          const SizedBox(height: 12),
          _buildStringListEditor(
            items: _optionalFields,
            onChanged: (items) => setState(() => _optionalFields = items),
            addLabel: 'Add Optional Field',
            hintText: 'e.g., wifi_ssid',
          ),

          const SizedBox(height: 24),

          // Common fields helper
          _buildHelperChips(
            'Common Provisioning Fields',
            Icons.assignment,
            Colors.green,
            [
              ('unit_id', () => _addToListIfNotExists('unit_id', _requiredFields,
                  (l) => setState(() => _requiredFields = l))),
              ('wifi_ssid', () => _addToListIfNotExists('wifi_ssid', _optionalFields,
                  (l) => setState(() => _optionalFields = l))),
              ('wifi_password', () => _addToListIfNotExists('wifi_password', _optionalFields,
                  (l) => setState(() => _optionalFields = l))),
              ('device_secret', () => _addToListIfNotExists('device_secret', _optionalFields,
                  (l) => setState(() => _optionalFields = l))),
            ],
          ),
        ],
      ),
    );
  }

  void _addToListIfNotExists(
      String item, List<String> list, void Function(List<String>) setter) {
    if (!list.contains(item)) {
      setter([...list, item]);
    }
  }

  // ===========================================
  // Tab 4: Tests
  // ===========================================
  Widget _buildTestsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Supported Tests',
            'Tests that can be run via test_* commands',
          ),
          const SizedBox(height: 12),
          _buildStringListEditor(
            items: _supportedTests,
            onChanged: (items) => setState(() => _supportedTests = items),
            addLabel: 'Add Test',
            hintText: 'e.g., wifi, cloud, rfid',
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(
            'Status Fields',
            'Fields returned in get_status response',
          ),
          const SizedBox(height: 12),
          _buildStringListEditor(
            items: _statusFields,
            onChanged: (items) => setState(() => _statusFields = items),
            addLabel: 'Add Status Field',
            hintText: 'e.g., wifi_connected, uptime_ms',
          ),

          const SizedBox(height: 24),

          // Common tests helper
          _buildHelperChips(
            'Common Tests',
            Icons.science,
            Colors.purple,
            [
              ('wifi', () => _addToListIfNotExists('wifi', _supportedTests,
                  (l) => setState(() => _supportedTests = l))),
              ('cloud', () => _addToListIfNotExists('cloud', _supportedTests,
                  (l) => setState(() => _supportedTests = l))),
              ('rfid', () => _addToListIfNotExists('rfid', _supportedTests,
                  (l) => setState(() => _supportedTests = l))),
              ('audio', () => _addToListIfNotExists('audio', _supportedTests,
                  (l) => setState(() => _supportedTests = l))),
              ('all', () => _addToListIfNotExists('all', _supportedTests,
                  (l) => setState(() => _supportedTests = l))),
            ],
          ),

          const SizedBox(height: 16),

          _buildHelperChips(
            'Common Status Fields',
            Icons.info_outline,
            Colors.blue,
            [
              ('wifi_connected', () => _addToListIfNotExists('wifi_connected', _statusFields,
                  (l) => setState(() => _statusFields = l))),
              ('wifi_rssi', () => _addToListIfNotExists('wifi_rssi', _statusFields,
                  (l) => setState(() => _statusFields = l))),
              ('cloud_connected', () => _addToListIfNotExists('cloud_connected', _statusFields,
                  (l) => setState(() => _statusFields = l))),
              ('uptime_ms', () => _addToListIfNotExists('uptime_ms', _statusFields,
                  (l) => setState(() => _statusFields = l))),
              ('free_heap', () => _addToListIfNotExists('free_heap', _statusFields,
                  (l) => setState(() => _statusFields = l))),
              ('battery_level', () => _addToListIfNotExists('battery_level', _statusFields,
                  (l) => setState(() => _statusFields = l))),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================
  // Tab 5: Advanced
  // ===========================================
  Widget _buildAdvancedTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Custom Commands',
            'Device-specific commands beyond standard protocol',
          ),
          const SizedBox(height: 12),

          // Custom commands list
          ..._customCommands.asMap().entries.map((entry) {
            return _buildCustomCommandEditor(entry.key, entry.value);
          }),

          OutlinedButton.icon(
            onPressed: _addCustomCommand,
            icon: const Icon(Icons.add),
            label: const Text('Add Custom Command'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),

          const SizedBox(height: 24),

          _buildSectionHeader(
            'LED Patterns',
            'Named LED patterns for visual feedback',
          ),
          const SizedBox(height: 12),

          // LED patterns list
          ..._ledPatterns.entries.map((entry) {
            return _buildLedPatternEditor(entry.key, entry.value);
          }),

          OutlinedButton.icon(
            onPressed: _addLedPattern,
            icon: const Icon(Icons.add),
            label: const Text('Add LED Pattern'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  void _addCustomCommand() {
    setState(() {
      _customCommands.add(
        const CustomCommand(
          name: '',
          description: '',
        ),
      );
    });
  }

  Widget _buildCustomCommandEditor(int index, CustomCommand command) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: command.name,
                    decoration: const InputDecoration(
                      labelText: 'Command Name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _customCommands[index] = CustomCommand(
                          name: value,
                          description: command.description,
                          parameters: command.parameters,
                        );
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: SaturdayColors.error,
                  onPressed: () {
                    setState(() {
                      _customCommands.removeAt(index);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: command.description,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _customCommands[index] = CustomCommand(
                    name: command.name,
                    description: value,
                    parameters: command.parameters,
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addLedPattern() {
    _showAddLedPatternDialog();
  }

  void _showAddLedPatternDialog() {
    final nameController = TextEditingController();
    String selectedColor = 'white';
    String selectedPattern = 'solid';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add LED Pattern'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Pattern Name',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., idle, provisioning, error',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedColor,
                decoration: const InputDecoration(
                  labelText: 'Color',
                  border: OutlineInputBorder(),
                ),
                items: ['white', 'red', 'green', 'blue', 'yellow', 'cyan', 'magenta']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedColor = v!),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedPattern,
                decoration: const InputDecoration(
                  labelText: 'Pattern',
                  border: OutlineInputBorder(),
                ),
                items: ['solid', 'blink', 'pulse', 'chase']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedPattern = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  setState(() {
                    _ledPatterns[nameController.text] = LedPattern(
                      color: selectedColor,
                      pattern: selectedPattern,
                    );
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedPatternEditor(String name, LedPattern pattern) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _getColorForName(pattern.color),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey),
          ),
        ),
        title: Text(name),
        subtitle: Text('${pattern.color} - ${pattern.pattern}'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          color: SaturdayColors.error,
          onPressed: () {
            setState(() {
              _ledPatterns.remove(name);
            });
          },
        ),
      ),
    );
  }

  Color _getColorForName(String name) {
    switch (name) {
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      case 'yellow':
        return Colors.yellow;
      case 'cyan':
        return Colors.cyan;
      case 'magenta':
        return Colors.purple;
      default:
        return Colors.white;
    }
  }

  // ===========================================
  // Helper Widgets
  // ===========================================
  Widget _buildSectionHeader(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
      ],
    );
  }

  Widget _buildStringListEditor({
    required List<String> items,
    required ValueChanged<List<String>> onChanged,
    required String addLabel,
    required String hintText,
  }) {
    return Column(
      children: [
        ...items.asMap().entries.map((entry) {
          final index = entry.key;
          final value = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: value,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: hintText,
                    ),
                    onChanged: (newValue) {
                      final newItems = List<String>.from(items);
                      newItems[index] = newValue;
                      onChanged(newItems);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: SaturdayColors.error,
                  onPressed: () {
                    final newItems = List<String>.from(items);
                    newItems.removeAt(index);
                    onChanged(newItems);
                  },
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {
            final newItems = List<String>.from(items);
            newItems.add('');
            onChanged(newItems);
          },
          icon: const Icon(Icons.add),
          label: Text(addLabel),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _buildHelperChips(
    String title,
    IconData icon,
    Color color,
    List<(String, VoidCallback)> items,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((item) {
              return ActionChip(
                label: Text(item.$1),
                onPressed: item.$2,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
