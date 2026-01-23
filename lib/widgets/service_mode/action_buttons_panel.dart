import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/service_mode_manifest.dart';
import 'package:saturday_app/models/service_mode_state.dart';
import 'package:saturday_app/models/thread_credentials.dart';
import 'package:saturday_app/providers/service_mode_provider.dart';

/// Panel displaying action buttons based on device state and manifest
class ActionButtonsPanel extends StatelessWidget {
  final ServiceModeState state;
  final ServiceModeManifest? manifest;

  // Callbacks - using Future-returning functions for async operations
  final Future<void> Function()? onConnect;
  final Future<void> Function()? onConnectMonitorOnly;
  final Future<void> Function()? onDisconnect;
  final Future<void> Function()? onEnterServiceMode;
  final Future<void> Function()? onExitServiceMode;
  final Future<void> Function()? onProvision;
  final Future<void> Function()? onTestAll;
  final void Function(String testName, {Map<String, dynamic>? data})? onRunTest;
  final Future<void> Function()? onCustomerReset;
  final Future<void> Function()? onFactoryReset;
  final Future<void> Function()? onReboot;

  const ActionButtonsPanel({
    super.key,
    required this.state,
    this.manifest,
    this.onConnect,
    this.onConnectMonitorOnly,
    this.onDisconnect,
    this.onEnterServiceMode,
    this.onExitServiceMode,
    this.onProvision,
    this.onTestAll,
    this.onRunTest,
    this.onCustomerReset,
    this.onFactoryReset,
    this.onReboot,
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
                const Icon(Icons.play_arrow, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Actions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    // Disconnected state
    if (state.phase == ServiceModePhase.disconnected) {
      return _buildConnectButtons();
    }

    // Connecting/waiting states
    if (state.phase == ServiceModePhase.connecting ||
        state.phase == ServiceModePhase.waitingForDevice) {
      return _buildWaitingState();
    }

    // Error state
    if (state.phase == ServiceModePhase.error) {
      return _buildErrorState(context);
    }

    // In service mode - show all available actions
    if (state.phase == ServiceModePhase.inServiceMode) {
      return _buildServiceModeActions(context);
    }

    // Monitor-only mode - show disconnect and option to enter service mode
    if (state.phase == ServiceModePhase.monitoring) {
      return _buildMonitoringActions(context);
    }

    // Executing command - show busy state
    if (state.phase == ServiceModePhase.executingCommand) {
      return _buildExecutingState();
    }

    // Need to enter service mode
    if (state.phase == ServiceModePhase.enteringServiceMode) {
      return _buildEnteringServiceModeState();
    }

    // Default
    return _buildConnectButtons();
  }

  Widget _buildConnectButtons() {
    final hasPort = state.selectedPort != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary: Connect & Enter Service Mode
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: hasPort ? onConnect : null,
            icon: const Icon(Icons.build),
            label: const Text('Connect (Service Mode)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SaturdayColors.info,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Secondary: Monitor Only
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: hasPort ? onConnectMonitorOnly : null,
            icon: const Icon(Icons.monitor),
            label: const Text('Monitor Only'),
            style: OutlinedButton.styleFrom(
              foregroundColor: SaturdayColors.secondaryGrey,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (!hasPort) ...[
          const SizedBox(height: 8),
          Text(
            'Select a serial port to connect',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildWaitingState() {
    return Column(
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(
          state.phase == ServiceModePhase.connecting
              ? 'Connecting...'
              : 'Waiting for device...',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.cancel),
            label: const Text('Cancel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: SaturdayColors.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SaturdayColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.error, color: SaturdayColors.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.errorMessage ?? 'An error occurred',
                  style: const TextStyle(color: SaturdayColors.error),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onConnect,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEnteringServiceModeState() {
    return Column(
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(
          'Entering service mode...',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        Text(
          'Make sure to reboot the device now',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.cancel),
            label: const Text('Cancel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: SaturdayColors.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExecutingState() {
    return Column(
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(
          'Executing: ${state.currentCommand ?? 'command'}...',
          style: TextStyle(color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildMonitoringActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status indicator
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SaturdayColors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.monitor, color: SaturdayColors.info, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Monitoring device logs (not in service mode)',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Enter Service Mode button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onEnterServiceMode,
            icon: const Icon(Icons.build),
            label: const Text('Enter Service Mode'),
            style: ElevatedButton.styleFrom(
              backgroundColor: SaturdayColors.info,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Reboot the device after pressing to enter service mode',
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),

        // Disconnect button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onDisconnect,
            icon: const Icon(Icons.link_off, size: 18),
            label: const Text('Disconnect'),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceModeActions(BuildContext context) {
    final isFresh = state.isFreshDevice;
    final hasUnit = state.hasAssociatedUnit;
    final supportedTests = manifest?.supportedTests ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Disconnect button
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('Disconnect'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onExitServiceMode,
                icon: const Icon(Icons.exit_to_app, size: 18),
                label: const Text('Exit Service Mode'),
              ),
            ),
          ],
        ),

        // Provisioning section (for fresh devices)
        if (isFresh) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          _buildSectionHeader('Provisioning'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: hasUnit ? onProvision : null,
              icon: const Icon(Icons.check_circle),
              label: Text(hasUnit ? 'Provision Device' : 'Select Unit First'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          if (!hasUnit) ...[
            const SizedBox(height: 8),
            Text(
              'Select a production unit before provisioning',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ],

        // Testing section
        if (supportedTests.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          _buildSectionHeader('Tests'),
          const SizedBox(height: 8),

          // Test All button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onTestAll,
              icon: const Icon(Icons.playlist_play),
              label: const Text('Run All Tests'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.info,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Individual test buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: supportedTests.map((test) {
              final result = state.testResults[test];
              return _TestButton(
                testName: test,
                status: result?.status,
                onPressed: () => _handleTestPressed(context, test),
              );
            }).toList(),
          ),
        ],

        // Reset section
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        _buildSectionHeader('Device Actions'),
        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onReboot,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reboot'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCustomerReset,
                icon: const Icon(Icons.person_off, size: 18),
                label: const Text('Customer Reset'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _confirmFactoryReset(context),
            icon: const Icon(Icons.delete_forever),
            label: const Text('Factory Reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: SaturdayColors.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: Colors.grey[700],
        fontSize: 12,
      ),
    );
  }

  Future<void> _handleTestPressed(BuildContext context, String testName) async {
    // Tests that require metadata input
    if (testName == 'wifi') {
      final credentials = await _showWifiCredentialsDialog(context);
      if (credentials != null) {
        onRunTest?.call(testName, data: credentials);
      }
      return;
    }

    // Thread test: non-BR devices need credentials to join network
    if (testName == 'thread') {
      // Check if device has thread capability but NOT thread_br
      // Thread BR devices create their own network, non-BR devices need credentials
      final hasThread = manifest?.capabilities.thread ?? false;
      final hasThreadBr = manifest?.capabilities.threadBr ?? false;

      if (hasThread && !hasThreadBr) {
        final credentials = await _showThreadCredentialsDialog(context);
        if (credentials != null) {
          onRunTest?.call(testName, data: credentials);
        }
        return;
      }
      // Thread BR devices can test without provided credentials
    }

    // Default: run test without data
    onRunTest?.call(testName);
  }

  Future<Map<String, dynamic>?> _showWifiCredentialsDialog(
      BuildContext context) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _WifiCredentialsDialog(),
    );
  }

  Future<Map<String, dynamic>?> _showThreadCredentialsDialog(
      BuildContext context) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _ThreadCredentialsDialog(),
    );
  }

  Future<void> _confirmFactoryReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: SaturdayColors.error),
            SizedBox(width: 8),
            Text('Factory Reset'),
          ],
        ),
        content: const Text(
          'This will erase ALL data from the device including its unit ID. '
          'The device will need to be re-provisioned.\n\n'
          'Are you sure you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SaturdayColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Factory Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onFactoryReset?.call();
    }
  }
}

class _TestButton extends StatelessWidget {
  final String testName;
  final TestStatus? status;
  final VoidCallback onPressed;

  const _TestButton({
    required this.testName,
    this.status,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    Color? backgroundColor;
    Color? foregroundColor;
    IconData? icon;

    switch (status) {
      case TestStatus.running:
        backgroundColor = SaturdayColors.info.withValues(alpha: 0.1);
        foregroundColor = SaturdayColors.info;
        icon = Icons.hourglass_empty;
        break;
      case TestStatus.passed:
        backgroundColor = SaturdayColors.success.withValues(alpha: 0.1);
        foregroundColor = SaturdayColors.success;
        icon = Icons.check;
        break;
      case TestStatus.failed:
        backgroundColor = SaturdayColors.error.withValues(alpha: 0.1);
        foregroundColor = SaturdayColors.error;
        icon = Icons.close;
        break;
      default:
        backgroundColor = Colors.grey[100];
        foregroundColor = Colors.grey[700];
        icon = _getTestIcon(testName);
    }

    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: status == TestStatus.running ? null : onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == TestStatus.running)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foregroundColor,
                  ),
                )
              else
                Icon(icon, size: 14, color: foregroundColor),
              const SizedBox(width: 6),
              Text(
                _formatTestName(testName),
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getTestIcon(String testName) {
    switch (testName) {
      case 'wifi':
        return Icons.wifi;
      case 'bluetooth':
        return Icons.bluetooth;
      case 'cloud':
        return Icons.cloud;
      case 'rfid':
        return Icons.nfc;
      case 'audio':
        return Icons.volume_up;
      case 'display':
        return Icons.tv;
      case 'button':
        return Icons.touch_app;
      case 'thread':
        return Icons.hub;
      default:
        return Icons.science;
    }
  }

  String _formatTestName(String testName) {
    return testName.split('_').map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }
}

/// Dialog for entering WiFi credentials for the connection test.
///
/// This is a StatefulWidget to properly manage TextEditingControllers
/// and ensure text input works correctly on all platforms.
class _WifiCredentialsDialog extends StatefulWidget {
  const _WifiCredentialsDialog();

  @override
  State<_WifiCredentialsDialog> createState() => _WifiCredentialsDialogState();
}

class _WifiCredentialsDialogState extends State<_WifiCredentialsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _ssidFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Request focus on the SSID field after the dialog is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ssidFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passwordController.dispose();
    _ssidFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.wifi, color: SaturdayColors.info),
          SizedBox(width: 8),
          Text('WiFi Test Credentials'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter WiFi credentials for the connection test.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ssidController,
              focusNode: _ssidFocusNode,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'SSID',
                hintText: 'Network name',
                prefixIcon: Icon(Icons.wifi),
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter the network SSID';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                hintText: 'Network password',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter the network password';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Run Test'),
          style: ElevatedButton.styleFrom(
            backgroundColor: SaturdayColors.info,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop({
        'ssid': _ssidController.text,
        'password': _passwordController.text,
      });
    }
  }
}

/// Dialog for selecting/entering Thread credentials for non-BR device testing.
///
/// Non-BR Thread devices (like Crates) need to join an existing Thread network,
/// so they require credentials from a provisioned Thread Border Router (Hub).
class _ThreadCredentialsDialog extends ConsumerStatefulWidget {
  const _ThreadCredentialsDialog();

  @override
  ConsumerState<_ThreadCredentialsDialog> createState() =>
      _ThreadCredentialsDialogState();
}

class _ThreadCredentialsDialogState
    extends ConsumerState<_ThreadCredentialsDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _manualEntry = false;
  ThreadCredentialsWithUnit? _selectedCredentials;

  // Manual entry controllers
  final _networkNameController = TextEditingController();
  final _panIdController = TextEditingController();
  final _channelController = TextEditingController(text: '15');
  final _networkKeyController = TextEditingController();
  final _extendedPanIdController = TextEditingController();
  final _meshLocalPrefixController = TextEditingController();
  final _pskcController = TextEditingController();

  @override
  void dispose() {
    _networkNameController.dispose();
    _panIdController.dispose();
    _channelController.dispose();
    _networkKeyController.dispose();
    _extendedPanIdController.dispose();
    _meshLocalPrefixController.dispose();
    _pskcController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final credentialsAsync = ref.watch(availableThreadCredentialsProvider);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.hub, color: SaturdayColors.info),
          SizedBox(width: 8),
          Text('Thread Test Credentials'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Thread network credentials from a provisioned Hub, '
                  'or enter credentials manually.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),

                // Mode toggle
                Row(
                  children: [
                    Expanded(
                      child: _ModeButton(
                        label: 'Select from Hub',
                        icon: Icons.list,
                        isSelected: !_manualEntry,
                        onTap: () => setState(() => _manualEntry = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ModeButton(
                        label: 'Manual Entry',
                        icon: Icons.edit,
                        isSelected: _manualEntry,
                        onTap: () => setState(() => _manualEntry = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                if (_manualEntry)
                  _buildManualEntryForm()
                else
                  _buildCredentialsSelector(credentialsAsync),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _canSubmit() ? _submit : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Run Test'),
          style: ElevatedButton.styleFrom(
            backgroundColor: SaturdayColors.info,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  bool _canSubmit() {
    if (_manualEntry) {
      return _networkNameController.text.isNotEmpty &&
          _networkKeyController.text.isNotEmpty;
    }
    return _selectedCredentials != null;
  }

  Widget _buildCredentialsSelector(
      AsyncValue<List<ThreadCredentialsWithUnit>> credentialsAsync) {
    return credentialsAsync.when(
      data: (credentials) {
        if (credentials.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No Thread credentials available. Provision a Hub first, '
                    'or use manual entry.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<ThreadCredentialsWithUnit>(
              value: _selectedCredentials,
              decoration: const InputDecoration(
                labelText: 'Select Network',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.hub),
              ),
              items: credentials.map((cred) {
                return DropdownMenuItem(
                  value: cred,
                  child: Text(
                    cred.displayLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedCredentials = value);
              },
              validator: (value) {
                if (value == null) {
                  return 'Please select a network';
                }
                return null;
              },
            ),
            if (_selectedCredentials != null) ...[
              const SizedBox(height: 12),
              _buildCredentialsPreview(_selectedCredentials!.credentials),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: SaturdayColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.error, color: SaturdayColors.error, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Failed to load credentials: $error',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialsPreview(ThreadCredentials credentials) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPreviewRow('Network', credentials.networkName),
          _buildPreviewRow('Channel', credentials.channel.toString()),
          _buildPreviewRow(
              'PAN ID', '0x${credentials.panId.toRadixString(16).toUpperCase()}'),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          Text(value,
              style:
                  const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildManualEntryForm() {
    return Column(
      children: [
        TextFormField(
          controller: _networkNameController,
          decoration: const InputDecoration(
            labelText: 'Network Name *',
            border: OutlineInputBorder(),
            hintText: 'e.g., SaturdayVinyl',
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Required';
            }
            if (value.length > 16) {
              return 'Max 16 characters';
            }
            return null;
          },
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _channelController,
                decoration: const InputDecoration(
                  labelText: 'Channel *',
                  border: OutlineInputBorder(),
                  hintText: '11-26',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Required';
                  final channel = int.tryParse(value);
                  if (channel == null || channel < 11 || channel > 26) {
                    return '11-26';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _panIdController,
                decoration: const InputDecoration(
                  labelText: 'PAN ID',
                  border: OutlineInputBorder(),
                  hintText: '0-65534',
                ),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _networkKeyController,
          decoration: const InputDecoration(
            labelText: 'Network Key (32 hex chars) *',
            border: OutlineInputBorder(),
            hintText: 'a1b2c3d4...',
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Required';
            if (value.length != 32 ||
                !RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
              return '32 hex characters required';
            }
            return null;
          },
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _extendedPanIdController,
          decoration: const InputDecoration(
            labelText: 'Extended PAN ID (16 hex chars)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _meshLocalPrefixController,
          decoration: const InputDecoration(
            labelText: 'Mesh Local Prefix (16 hex chars)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _pskcController,
          decoration: const InputDecoration(
            labelText: 'PSKC (32 hex chars)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Map<String, dynamic> credentials;

    if (_manualEntry) {
      credentials = {
        'network_name': _networkNameController.text,
        'channel': int.tryParse(_channelController.text) ?? 15,
        if (_panIdController.text.isNotEmpty)
          'pan_id': int.tryParse(_panIdController.text) ?? 0,
        'network_key': _networkKeyController.text,
        if (_extendedPanIdController.text.isNotEmpty)
          'extended_pan_id': _extendedPanIdController.text,
        if (_meshLocalPrefixController.text.isNotEmpty)
          'mesh_local_prefix': _meshLocalPrefixController.text,
        if (_pskcController.text.isNotEmpty) 'pskc': _pskcController.text,
      };
    } else {
      final cred = _selectedCredentials!.credentials;
      credentials = {
        'network_name': cred.networkName,
        'pan_id': cred.panId,
        'channel': cred.channel,
        'network_key': cred.networkKey,
        'extended_pan_id': cred.extendedPanId,
        'mesh_local_prefix': cred.meshLocalPrefix,
        'pskc': cred.pskc,
      };
    }

    Navigator.of(context).pop(credentials);
  }
}

/// Mode toggle button for Thread credentials dialog
class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? SaturdayColors.info.withValues(alpha: 0.1)
          : Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? SaturdayColors.info
                  : Colors.grey[300]!,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? SaturdayColors.info : Colors.grey[600],
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? SaturdayColors.info : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
