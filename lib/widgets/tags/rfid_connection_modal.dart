import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/rfid_config.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_settings.dart';
import 'package:saturday_app/models/serial_connection_state.dart';
import 'package:saturday_app/providers/rfid_settings_provider.dart';
import 'package:saturday_app/providers/uhf_rfid_provider.dart';

/// Modal dialog for configuring RFID module connection settings
class RfidConnectionModal extends ConsumerStatefulWidget {
  const RfidConnectionModal({super.key});

  /// Show the modal dialog
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const RfidConnectionModal(),
    );
  }

  @override
  ConsumerState<RfidConnectionModal> createState() =>
      _RfidConnectionModalState();
}

class _RfidConnectionModalState extends ConsumerState<RfidConnectionModal> {
  String? _selectedPort;
  int _selectedBaudRate = RfidConfig.defaultBaudRate;
  double _rfPower = RfidConfig.defaultRfPower.toDouble();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _passwordError;
  bool _isTestingConnection = false;
  String? _testResult;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _loadSavedSettings() {
    final settings = ref.read(currentRfidSettingsProvider);
    setState(() {
      _selectedPort = settings.port;
      _selectedBaudRate = settings.baudRate;
      _rfPower = settings.rfPower.toDouble();
      if (settings.accessPassword != null) {
        _passwordController.text = settings.accessPassword!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Only show on desktop platforms
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return AlertDialog(
        title: const Text('Not Available'),
        content: const Text(
            'RFID module connection is only available on desktop platforms.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }

    final connectionState = ref.watch(uhfCurrentConnectionStateProvider);
    final portsAsync = ref.watch(refreshablePortsProvider);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(connectionState),
              const SizedBox(height: 24),

              // Content (scrollable)
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Port Selection
                      _buildPortSelection(portsAsync),
                      const SizedBox(height: 20),

                      // Baud Rate Selection
                      _buildBaudRateSelection(),
                      const SizedBox(height: 20),

                      // RF Power Slider
                      _buildRfPowerSlider(),
                      const SizedBox(height: 20),

                      // Access Password
                      _buildPasswordField(),
                      const SizedBox(height: 24),

                      // Test Connection
                      _buildTestConnection(connectionState),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              _buildActionButtons(connectionState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(SerialConnectionState connectionState) {
    return Row(
      children: [
        Icon(
          Icons.settings_input_antenna,
          color: SaturdayColors.primaryDark,
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RFID Module Settings',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: SaturdayColors.primaryDark,
                    ),
              ),
              const SizedBox(height: 4),
              _buildStatusChip(connectionState),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildStatusChip(SerialConnectionState connectionState) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (connectionState.status) {
      case SerialConnectionStatus.connected:
        statusColor = SaturdayColors.success;
        statusText = 'Connected';
        statusIcon = Icons.check_circle;
        break;
      case SerialConnectionStatus.connecting:
        statusColor = Colors.orange;
        statusText = 'Connecting...';
        statusIcon = Icons.sync;
        break;
      case SerialConnectionStatus.error:
        statusColor = SaturdayColors.error;
        statusText = 'Error';
        statusIcon = Icons.error;
        break;
      case SerialConnectionStatus.disconnected:
        statusColor = SaturdayColors.secondaryGrey;
        statusText = 'Disconnected';
        statusIcon = Icons.power_off;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: statusColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortSelection(AsyncValue<List<String>> portsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Serial Port',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                ref.invalidate(refreshablePortsProvider);
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Scan Ports'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        portsAsync.when(
          data: (ports) {
            if (ports.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SaturdayColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SaturdayColors.error),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: SaturdayColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No serial ports found. Please connect your RFID module and click "Scan Ports".',
                        style: TextStyle(
                          color: SaturdayColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            // Auto-select first port if none selected
            if (_selectedPort == null && ports.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                setState(() => _selectedPort = ports.first);
              });
            }

            return DropdownButtonFormField<String>(
              value: ports.contains(_selectedPort) ? _selectedPort : null,
              decoration: const InputDecoration(
                hintText: 'Select a port',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              items: ports.map((port) {
                return DropdownMenuItem(
                  value: port,
                  child: Text(port, style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedPort = value);
              },
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, _) => Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SaturdayColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Error scanning ports: $error',
              style: TextStyle(color: SaturdayColors.error),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBaudRateSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Baud Rate',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: _selectedBaudRate,
          decoration: const InputDecoration(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          items: RfidConfig.availableBaudRates.map((rate) {
            return DropdownMenuItem(
              value: rate,
              child: Text(
                '$rate bps${rate == RfidConfig.defaultBaudRate ? ' (default)' : ''}',
                style: const TextStyle(fontSize: 14),
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _selectedBaudRate = value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildRfPowerSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RF Power',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: SaturdayColors.primaryDark,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_rfPower.round()} dBm',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: _rfPower,
          min: RfidConfig.minRfPower.toDouble(),
          max: RfidConfig.maxRfPower.toDouble(),
          divisions: RfidConfig.maxRfPower - RfidConfig.minRfPower,
          label: '${_rfPower.round()} dBm',
          onChanged: (value) {
            setState(() => _rfPower = value);
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${RfidConfig.minRfPower} dBm',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              Text(
                '${RfidConfig.maxRfPower} dBm',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: SaturdayColors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: SaturdayColors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lower power = shorter range, easier single-tag writes. '
                  'Higher power = longer range, may read multiple tags.',
                  style: TextStyle(
                    fontSize: 12,
                    color: SaturdayColors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Access Password (optional)',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Fa-f]')),
            LengthLimitingTextInputFormatter(8),
          ],
          decoration: InputDecoration(
            hintText: '00000000',
            helperText: '8 hex characters (e.g., 00000000)',
            errorText: _passwordError,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
                if (_passwordController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      setState(() {
                        _passwordController.clear();
                        _passwordError = null;
                      });
                    },
                  ),
              ],
            ),
          ),
          onChanged: (value) {
            setState(() {
              if (value.isEmpty) {
                _passwordError = null;
              } else if (value.length != 8) {
                _passwordError = 'Must be exactly 8 hex characters';
              } else if (!RfidSettings.isValidAccessPassword(value)) {
                _passwordError = 'Invalid hex characters';
              } else {
                _passwordError = null;
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildTestConnection(SerialConnectionState connectionState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Test Connection',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _selectedPort != null && !_isTestingConnection
                    ? _testConnection
                    : null,
                icon: _isTestingConnection
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.flash_on, size: 20),
                label: Text(_isTestingConnection ? 'Testing...' : 'Test'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SaturdayColors.info,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_testSuccess
                      ? SaturdayColors.success
                      : SaturdayColors.error)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _testSuccess
                    ? SaturdayColors.success
                    : SaturdayColors.error,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _testSuccess ? Icons.check_circle : Icons.error,
                  color:
                      _testSuccess ? SaturdayColors.success : SaturdayColors.error,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      color: _testSuccess
                          ? SaturdayColors.success
                          : SaturdayColors.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (connectionState.hasError) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: SaturdayColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SaturdayColors.error),
            ),
            child: Row(
              children: [
                Icon(Icons.error, color: SaturdayColors.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    connectionState.errorMessage ?? 'Unknown error',
                    style: TextStyle(
                      color: SaturdayColors.error,
                      fontSize: 13,
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

  Widget _buildActionButtons(SerialConnectionState connectionState) {
    final isConnected = connectionState.status == SerialConnectionStatus.connected;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isConnected)
          OutlinedButton.icon(
            onPressed: _disconnect,
            icon: const Icon(Icons.power_off, size: 18),
            label: const Text('Disconnect'),
            style: OutlinedButton.styleFrom(
              foregroundColor: SaturdayColors.error,
              side: BorderSide(color: SaturdayColors.error),
            ),
          ),
        if (isConnected) const SizedBox(width: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _selectedPort != null && !_hasValidationErrors
              ? _saveAndConnect
              : null,
          icon: const Icon(Icons.save, size: 18),
          label: Text(isConnected ? 'Save' : 'Save & Connect'),
          style: ElevatedButton.styleFrom(
            backgroundColor: SaturdayColors.success,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  bool get _hasValidationErrors =>
      _passwordError != null ||
      (_passwordController.text.isNotEmpty &&
          _passwordController.text.length != 8);

  Future<void> _testConnection() async {
    if (_selectedPort == null) return;

    setState(() {
      _isTestingConnection = true;
      _testResult = null;
    });

    try {
      final uhfService = ref.read(uhfRfidServiceProvider);

      // Disconnect first if already connected (to test with new settings)
      if (uhfService.isConnected) {
        await uhfService.disconnect();
      }

      // Test at 115200 only (confirmed working baud rate from C++ code)
      const baudRate = 115200;

      setState(() {
        _testResult = 'Testing at $baudRate baud...';
      });

      final connected = await uhfService.connect(
        _selectedPort!,
        baudRate: baudRate,
      );

      String? firmware;
      int? workingBaudRate;

      if (connected) {
        // Wait longer for module to be fully ready
        // C++ code waits 100ms after EN, then more time for uart setup
        setState(() {
          _testResult = 'Connected, waiting for module...';
        });
        await Future.delayed(const Duration(milliseconds: 500));

        firmware = await uhfService.getFirmwareVersion();

        if (firmware != null) {
          workingBaudRate = baudRate;
        } else {
          await uhfService.disconnect();
        }
      }

      if (firmware != null && workingBaudRate != null) {
        setState(() {
          _testResult = 'Connection successful at $workingBaudRate baud!\nFirmware: $firmware';
          _testSuccess = true;
        });
      } else {
        setState(() {
          _testResult = 'Module not responding at any baud rate.\n'
              'Check:\n'
              '• Wiring: TX→RX, RX→TX (crossed)\n'
              '• EN pin: Connect to GND to enable\n'
              '• Power: Module needs 5V with adequate current';
          _testSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _testResult = 'Error: $e';
        _testSuccess = false;
      });
    } finally {
      setState(() {
        _isTestingConnection = false;
      });
    }
  }

  Future<void> _disconnect() async {
    final uhfService = ref.read(uhfRfidServiceProvider);
    await uhfService.disconnect();

    setState(() {
      _testResult = null;
    });
  }

  Future<void> _saveAndConnect() async {
    if (_selectedPort == null) return;

    // Save settings
    final settingsNotifier = ref.read(rfidSettingsProvider.notifier);
    await settingsNotifier.updatePort(_selectedPort);
    await settingsNotifier.updateBaudRate(_selectedBaudRate);
    await settingsNotifier.updateRfPower(_rfPower.round());

    if (_passwordController.text.isNotEmpty &&
        _passwordController.text.length == 8) {
      await settingsNotifier.updateAccessPassword(_passwordController.text);
    } else if (_passwordController.text.isEmpty) {
      await settingsNotifier.updateAccessPassword(null);
    }

    // Connect
    final uhfService = ref.read(uhfRfidServiceProvider);

    // Disconnect first if already connected
    if (uhfService.isConnected) {
      await uhfService.disconnect();
    }

    final connected = await uhfService.connect(
      _selectedPort!,
      baudRate: _selectedBaudRate,
    );

    if (connected) {
      // Set RF power
      await uhfService.setRfPower(_rfPower.round());

      // Set access password if provided
      if (_passwordController.text.isNotEmpty &&
          _passwordController.text.length == 8) {
        final passwordBytes = _hexToBytes(_passwordController.text);
        if (passwordBytes != null) {
          uhfService.setAccessPassword(passwordBytes);
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Connected to RFID module'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to $_selectedPort'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  /// Convert hex string to bytes
  List<int>? _hexToBytes(String hex) {
    if (hex.length != 8) return null;
    try {
      final bytes = <int>[];
      for (var i = 0; i < 8; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return bytes;
    } catch (e) {
      return null;
    }
  }
}
