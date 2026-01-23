import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/providers/service_mode_provider.dart';
import 'package:saturday_app/widgets/service_mode/log_display.dart';
import 'package:saturday_app/widgets/service_mode/action_buttons_panel.dart';
import 'package:saturday_app/widgets/service_mode/device_info_card.dart';
import 'package:saturday_app/widgets/service_mode/led_patterns_card.dart';
import 'package:saturday_app/widgets/service_mode/unit_context_card.dart';
import 'package:saturday_app/widgets/service_mode/unit_selection_dialog.dart';

/// Global Service Mode screen for device provisioning and diagnostics
class ServiceModeScreen extends ConsumerStatefulWidget {
  /// Optional: Unit context from production step navigation
  final ProductionUnit? initialUnit;

  /// Optional: Production step context
  final ProductionStep? fromStep;

  /// Named constructor for use with ServiceModeArgs
  ServiceModeScreen({
    super.key,
    this.initialUnit,
    this.fromStep,
    ServiceModeArgs? args,
  })  : _initialUnit = args?.unit ?? initialUnit,
        _fromStep = args?.step ?? fromStep;

  final ProductionUnit? _initialUnit;
  final ProductionStep? _fromStep;

  @override
  ConsumerState<ServiceModeScreen> createState() => _ServiceModeScreenState();
}

class _ServiceModeScreenState extends ConsumerState<ServiceModeScreen> {
  bool _hideBeacons = true; // Default to hiding beacons for cleaner logs

  @override
  void initState() {
    super.initState();

    // If we have an initial unit context, set it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget._initialUnit != null) {
        ref
            .read(serviceModeStateProvider.notifier)
            .setProductionUnit(widget._initialUnit);
      }
    });
  }

  @override
  void dispose() {
    // Disconnect from the serial port when leaving the screen
    // This ensures resources are properly released
    ref.read(serviceModeStateProvider.notifier).disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serviceModeStateProvider);
    final notifier = ref.read(serviceModeStateProvider.notifier);
    final portsAsync = ref.watch(availablePortsAutoRefreshProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Mode'),
        actions: [
          if (state.isConnected)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: state.phase.isMonitoring
                        ? SaturdayColors.info
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
                        state.phase.isMonitoring ? 'Monitoring' : 'Connected',
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
                  // Port selection
                  _buildPortSelection(portsAsync, state, notifier),
                  const SizedBox(height: 16),

                  // Device info card
                  DeviceInfoCard(
                    deviceInfo: state.deviceInfo,
                    manifest: state.manifest,
                    isInServiceMode: state.isInServiceMode,
                  ),
                  const SizedBox(height: 16),

                  // Unit context card
                  UnitContextCard(
                    unit: state.associatedUnit,
                    isFreshDevice: state.isFreshDevice,
                    onSelectUnit: () => _showUnitSelectionDialog(notifier),
                    onClearUnit: () => notifier.setProductionUnit(null),
                  ),
                  const SizedBox(height: 16),

                  // Action buttons
                  ActionButtonsPanel(
                    state: state,
                    manifest: state.manifest,
                    onConnect: () => notifier.connect(),
                    onConnectMonitorOnly: () => notifier.connect(monitorOnly: true),
                    onDisconnect: () => notifier.disconnect(),
                    onEnterServiceMode: () => notifier.enterServiceMode(),
                    onExitServiceMode: () => notifier.exitServiceMode(),
                    onProvision: () => _handleProvision(notifier),
                    onTestAll: () => _handleTestAll(notifier),
                    onRunTest: (testName, {Map<String, dynamic>? data}) =>
                        notifier.runTest(testName, testData: data),
                    onCustomerReset: () => notifier.customerReset(),
                    onFactoryReset: () => notifier.factoryReset(),
                    onReboot: () => notifier.reboot(),
                  ),

                  // LED patterns reference (if available in manifest)
                  if (state.manifest?.ledPatterns.isNotEmpty ?? false) ...[
                    const SizedBox(height: 16),
                    LedPatternsCard(
                      ledPatterns: state.manifest!.ledPatterns,
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
                      const SizedBox(width: 8),
                      Tooltip(
                        message: _hideBeacons
                            ? 'Show beacon messages'
                            : 'Hide beacon messages',
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _hideBeacons = !_hideBeacons;
                            });
                          },
                          icon: Icon(
                            _hideBeacons
                                ? Icons.visibility_off
                                : Icons.visibility,
                            size: 18,
                          ),
                          label: const Text('Beacons'),
                          style: TextButton.styleFrom(
                            foregroundColor: _hideBeacons
                                ? SaturdayColors.secondaryGrey
                                : SaturdayColors.info,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: LogDisplay(
                      logLines: state.logLines,
                      hideBeacons: _hideBeacons,
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

  Widget _buildPortSelection(
    AsyncValue<List<String>> portsAsync,
    dynamic state,
    ServiceModeStateNotifier notifier,
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
                  'Serial Port',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                if (state.isConnected)
                  TextButton.icon(
                    onPressed: () => notifier.disconnect(),
                    icon: const Icon(Icons.link_off, size: 16),
                    label: const Text('Disconnect'),
                    style: TextButton.styleFrom(
                      foregroundColor: SaturdayColors.error,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            portsAsync.when(
              data: (ports) {
                if (ports.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.grey[600], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No serial ports detected. Connect a device via USB.',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return DropdownButtonFormField<String>(
                  value: ports.contains(state.selectedPort)
                      ? state.selectedPort
                      : null,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    hintText: 'Select a port',
                  ),
                  items: ports.map((port) {
                    return DropdownMenuItem(
                      value: port,
                      child: Text(
                        port,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    );
                  }).toList(),
                  onChanged: state.isConnected
                      ? null
                      : (value) => notifier.selectPort(value),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(
                'Error loading ports: $error',
                style: const TextStyle(color: SaturdayColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showUnitSelectionDialog(
      ServiceModeStateNotifier notifier) async {
    final unit = await showUnitSelectionDialog(
      context,
      firmwareId: ref.read(serviceModeStateProvider).manifest?.firmwareId,
    );

    if (unit != null) {
      notifier.selectUnitForFreshDevice(unit);
    }
  }

  Future<void> _handleProvision(ServiceModeStateNotifier notifier) async {
    // For now, provision without additional session data
    // In the future, we could show a dialog to collect Wi-Fi credentials, etc.
    await notifier.provision();
  }

  Future<void> _handleTestAll(ServiceModeStateNotifier notifier) async {
    // For now, run all tests without Wi-Fi credentials
    // In the future, we could show a dialog to collect credentials if needed
    await notifier.testAll();
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
