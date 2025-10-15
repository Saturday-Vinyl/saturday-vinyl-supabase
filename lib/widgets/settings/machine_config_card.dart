import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/services/machine_connection_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Card for configuring CNC and Laser machine connections
class MachineConfigCard extends StatefulWidget {
  const MachineConfigCard({super.key});

  @override
  State<MachineConfigCard> createState() => _MachineConfigCardState();
}

class _MachineConfigCardState extends State<MachineConfigCard> {
  final MachineConnectionService _connectionService = MachineConnectionService();

  // CNC Configuration
  String? _cncPort;
  int _cncBaudRate = 115200;

  // Laser Configuration
  String? _laserPort;
  int _laserBaudRate = 115200;

  List<String> _availablePorts = [];
  bool _isLoadingPorts = false;
  bool _isTesting = false;
  MachineType? _testingMachine;

  static const String _cncPortKey = 'machine_cnc_port';
  static const String _cncBaudRateKey = 'machine_cnc_baud_rate';
  static const String _laserPortKey = 'machine_laser_port';
  static const String _laserBaudRateKey = 'machine_laser_baud_rate';

  static const List<int> _baudRates = [9600, 19200, 38400, 57600, 115200, 230400];

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadAvailablePorts();
  }

  @override
  void dispose() {
    _connectionService.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      setState(() {
        _cncPort = prefs.getString(_cncPortKey);
        _cncBaudRate = prefs.getInt(_cncBaudRateKey) ?? 115200;
        _laserPort = prefs.getString(_laserPortKey);
        _laserBaudRate = prefs.getInt(_laserBaudRateKey) ?? 115200;
      });

      AppLogger.info('Loaded machine settings');
    } catch (error, stackTrace) {
      AppLogger.error('Error loading machine settings', error, stackTrace);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_cncPort != null) {
        await prefs.setString(_cncPortKey, _cncPort!);
      }
      await prefs.setInt(_cncBaudRateKey, _cncBaudRate);

      if (_laserPort != null) {
        await prefs.setString(_laserPortKey, _laserPort!);
      }
      await prefs.setInt(_laserBaudRateKey, _laserBaudRate);

      AppLogger.info('Saved machine settings');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Machine settings saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error saving machine settings', error, stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadAvailablePorts() async {
    setState(() => _isLoadingPorts = true);

    try {
      final ports = _connectionService.getAvailablePorts();

      setState(() {
        _availablePorts = ports;
        _isLoadingPorts = false;
      });

      AppLogger.info('Found ${ports.length} serial ports');
    } catch (error, stackTrace) {
      AppLogger.error('Error loading serial ports', error, stackTrace);

      setState(() => _isLoadingPorts = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading ports: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Build port dropdown items, including the selected port even if not currently available
  List<DropdownMenuItem<String>> _buildPortItems(String? selectedPort) {
    final Set<String> allPorts = {..._availablePorts};

    // Add selected port if it's not in the available ports
    // This handles the case where a previously configured port is no longer connected
    if (selectedPort != null && !allPorts.contains(selectedPort)) {
      allPorts.add(selectedPort);
    }

    // Convert to sorted list and build menu items
    final sortedPorts = allPorts.toList()..sort();

    return sortedPorts.map((port) {
      final isAvailable = _availablePorts.contains(port);
      return DropdownMenuItem(
        value: port,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(port),
            if (!isAvailable) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.warning,
                size: 16,
                color: Colors.orange,
              ),
            ],
          ],
        ),
      );
    }).toList();
  }

  Future<void> _testConnection(MachineType machineType) async {
    final port = machineType == MachineType.cnc ? _cncPort : _laserPort;
    final baudRate = machineType == MachineType.cnc ? _cncBaudRate : _laserBaudRate;

    if (port == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a port for ${machineType.displayName}'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testingMachine = machineType;
    });

    try {
      AppLogger.info('Testing ${machineType.displayName} connection on $port');

      final connected = await _connectionService.connect(
        portName: port,
        machineType: machineType,
        baudRate: baudRate,
      );

      if (connected) {
        // Send status query
        await Future.delayed(const Duration(milliseconds: 500));
        await _connectionService.requestStatus();

        // Wait for response
        await Future.delayed(const Duration(milliseconds: 1000));

        // Disconnect
        await _connectionService.disconnect();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${machineType.displayName} connection successful!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to connect to ${machineType.displayName}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error testing connection', error, stackTrace);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection test failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isTesting = false;
        _testingMachine = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.settings_input_component,
                  size: 24,
                  color: SaturdayColors.primaryDark,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Machine Configuration',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: _isLoadingPorts
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: _isLoadingPorts ? null : _loadAvailablePorts,
                  tooltip: 'Refresh ports',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Configure serial port connections for CNC and Laser machines',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),

            // Available Ports Info
            if (_availablePorts.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, size: 16, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'No serial ports found. Connect your machine and click refresh.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Found ${_availablePorts.length} serial ${_availablePorts.length == 1 ? 'port' : 'ports'}: ${_availablePorts.join(", ")}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // CNC Machine Configuration
            _buildMachineSection(
              machineType: MachineType.cnc,
              selectedPort: _cncPort,
              baudRate: _cncBaudRate,
              onPortChanged: (port) => setState(() => _cncPort = port),
              onBaudRateChanged: (rate) => setState(() => _cncBaudRate = rate),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Laser Machine Configuration
            _buildMachineSection(
              machineType: MachineType.laser,
              selectedPort: _laserPort,
              baudRate: _laserBaudRate,
              onPortChanged: (port) => setState(() => _laserPort = port),
              onBaudRateChanged: (rate) => setState(() => _laserBaudRate = rate),
            ),

            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: SaturdayColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.save),
                label: const Text('Save Machine Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineSection({
    required MachineType machineType,
    required String? selectedPort,
    required int baudRate,
    required ValueChanged<String?> onPortChanged,
    required ValueChanged<int> onBaudRateChanged,
  }) {
    final isTesting = _isTesting && _testingMachine == machineType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          machineType.displayName,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),

        // Port Selection
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: selectedPort,
                decoration: const InputDecoration(
                  labelText: 'Serial Port',
                  border: OutlineInputBorder(),
                ),
                items: _buildPortItems(selectedPort),
                onChanged: _availablePorts.isEmpty && selectedPort == null ? null : onPortChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                value: baudRate,
                decoration: const InputDecoration(
                  labelText: 'Baud Rate',
                  border: OutlineInputBorder(),
                ),
                items: _baudRates.map((rate) {
                  return DropdownMenuItem(
                    value: rate,
                    child: Text(rate.toString()),
                  );
                }).toList(),
                onChanged: (rate) {
                  if (rate != null) onBaudRateChanged(rate);
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Test Connection Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: isTesting || selectedPort == null
                ? null
                : () => _testConnection(machineType),
            icon: isTesting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cable),
            label: Text(isTesting ? 'Testing...' : 'Test Connection'),
          ),
        ),
      ],
    );
  }
}
