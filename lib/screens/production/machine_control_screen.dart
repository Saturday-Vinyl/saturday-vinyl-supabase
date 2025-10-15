import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/models/gcode_file.dart';
import 'package:saturday_app/models/machine_macro.dart';
import 'package:saturday_app/services/machine_connection_service.dart';
import 'package:saturday_app/services/gcode_streaming_service.dart';
import 'package:saturday_app/services/grbl_error_codes.dart';
import 'package:saturday_app/providers/machine_provider.dart';
import 'package:saturday_app/providers/gcode_file_provider.dart';
import 'package:saturday_app/providers/image_to_gcode_provider.dart';
import 'package:saturday_app/providers/machine_macro_provider.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/product_variant.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/production/gcode_viewer_widget.dart';
import 'dart:async';
import 'dart:math' as math;

/// Jog mode enum for different step sizes
enum JogMode {
  rapid(10.0, 'Rapid', '10mm'),
  normal(2.0, 'Normal', '2mm'),
  precise(0.5, 'Precise', '0.5mm');

  const JogMode(this.distance, this.label, this.displayText);
  final double distance;
  final String label;
  final String displayText;
}

class MachineControlScreen extends ConsumerStatefulWidget {
  final ProductionStep step;
  final ProductionUnit unit;

  const MachineControlScreen({
    super.key,
    required this.step,
    required this.unit,
  });

  @override
  ConsumerState<MachineControlScreen> createState() => _MachineControlScreenState();
}

class _MachineControlScreenState extends ConsumerState<MachineControlScreen> {
  // Machine services
  late final MachineConnectionService _machine;
  late final GCodeStreamingService _streaming;

  // State
  MachineState _machineState = MachineState.disconnected;
  String? _selectedPort;
  List<String> _availablePorts = [];

  // Execution tracking
  final Map<String, bool> _gcodeFileCompleted = {};
  bool _qrEngraveCompleted = false;
  StreamingProgress? _currentProgress;

  // Macro execution tracking
  String? _executingMacroId;
  bool _isMacroExecuting = false;

  // Jog control state
  JogMode _jogMode = JogMode.normal;
  String? _joggingAxis; // e.g., 'X+', 'X-', 'Y+', 'Y-', 'Z+', 'Z-'
  Timer? _jogTimer;

  // GCode preview state
  String? _currentGCodePreview;
  String? _currentPreviewFileName;

  @override
  void initState() {
    super.initState();

    // Get machine service based on step type
    if (widget.step.stepType.isCnc) {
      _machine = ref.read(cncMachineServiceProvider);
      _streaming = ref.read(cncStreamingServiceProvider);
    } else if (widget.step.stepType.isLaser) {
      _machine = ref.read(laserMachineServiceProvider);
      _streaming = ref.read(laserStreamingServiceProvider);
    } else {
      throw Exception('Invalid step type for machine control: ${widget.step.stepType}');
    }

    // Listen to machine state changes
    _machine.stateStream.listen((state) {
      if (mounted) {
        setState(() => _machineState = state);
      }
    });

    // Listen to machine errors
    _machine.errorStream.listen((errorEvent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ${errorEvent.error.code}: ${errorEvent.error.userMessage}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                _showErrorDetailsDialog(errorEvent.error);
              },
            ),
          ),
        );
      }
    });

    // Listen to machine alarms
    _machine.alarmStream.listen((alarmEvent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ALARM ${alarmEvent.alarm.code}: ${alarmEvent.alarm.userMessage}'),
            backgroundColor: Colors.red.shade900,
            duration: const Duration(seconds: 10),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () {
                _showAlarmDetailsDialog(alarmEvent.alarm);
              },
            ),
          ),
        );
      }
    });

    // Listen to streaming progress
    _streaming.progressStream.listen((progress) {
      if (mounted) {
        setState(() => _currentProgress = progress);
      }
    });

    // Load saved port
    _loadSavedPort();

    // Refresh available ports
    _refreshPorts();
  }

  @override
  void dispose() {
    _jogTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSavedPort() async {
    final storage = ref.read(machineConfigStorageProvider);
    final port = widget.step.stepType.isCnc
        ? storage.getCncPort()
        : storage.getLaserPort();

    if (mounted && port != null) {
      setState(() => _selectedPort = port);
    }
  }

  void _refreshPorts() {
    setState(() {
      _availablePorts = MachineConnectionService.listAvailablePorts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Machine Control - ${widget.step.stepType.displayName}'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Use split layout for wider screens
          final bool useSplitLayout = constraints.maxWidth > 800;

          if (useSplitLayout) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left side: Controls (40% or fixed width)
                SizedBox(
                  width: math.max(400, constraints.maxWidth * 0.4),
                  child: _buildControlsPanel(),
                ),

                // Divider
                const VerticalDivider(width: 1, thickness: 1),

                // Right side: GCode Preview (flexible)
                Expanded(
                  child: _buildPreviewPanel(),
                ),
              ],
            );
          } else {
            // For narrow screens, stack vertically (unlikely for desktop)
            return _buildControlsPanel();
          }
        },
      ),
    );
  }

  /// Build the left panel with all machine controls
  Widget _buildControlsPanel() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // Machine status section
          _buildMachineStatusSection(),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // Unit details section
          _buildUnitDetailsSection(),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // Machine controls section
          _buildMachineControlsSection(),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // Quick Macros section
          _buildQuickMacrosSection(),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),

          // gCode files execution section
          SizedBox(
            height: 400,
            child: _buildGCodeFilesSection(),
          ),

          const SizedBox(height: 24),

          // Progress section (when streaming)
          if (_streaming.isStreaming) ...[
            _buildProgressSection(),
            const SizedBox(height: 24),
          ],

          // Navigation buttons
          _buildNavigationButtons(),
        ],
        ),
      ),
    );
  }

  /// Build the right panel with GCode preview
  Widget _buildPreviewPanel() {
    if (_currentGCodePreview == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.code,
                size: 64,
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Select a GCode file to preview',
                style: TextStyle(
                  fontSize: 18,
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Click "Run" on any file in the execution queue',
                style: TextStyle(
                  fontSize: 14,
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: GCodeViewerWidget(
        gcode: _currentGCodePreview!,
        fileName: _currentPreviewFileName,
      ),
    );
  }

  // Section builders
  Widget _buildMachineStatusSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cable, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Machine Connection',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Port selection
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedPort,
                    decoration: InputDecoration(
                      labelText: 'Serial Port',
                      border: const OutlineInputBorder(),
                      enabled: _machineState == MachineState.disconnected,
                    ),
                    items: _availablePorts.map((port) {
                      return DropdownMenuItem(
                        value: port,
                        child: Text(port),
                      );
                    }).toList(),
                    onChanged: _machineState == MachineState.disconnected
                        ? (port) {
                            setState(() => _selectedPort = port);
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _machineState == MachineState.disconnected
                      ? _refreshPorts
                      : null,
                  tooltip: 'Refresh Ports',
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Status indicator
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _getStatusColor(_machineState),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Status: ${_machineState.displayName.toUpperCase()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Connect/Disconnect button
            Row(
              children: [
                if (_machineState == MachineState.disconnected)
                  ElevatedButton.icon(
                    onPressed: _selectedPort != null ? _connect : null,
                    icon: const Icon(Icons.power),
                    label: const Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaturdayColors.success,
                      foregroundColor: Colors.white,
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _disconnect,
                    icon: const Icon(Icons.power_off),
                    label: const Text('Disconnect'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SaturdayColors.error,
                    ),
                  ),
                const SizedBox(width: 16),
                // Emergency stop (always visible when connected)
                if (_machineState != MachineState.disconnected)
                  ElevatedButton.icon(
                    onPressed: _emergencyStop,
                    icon: const Icon(Icons.stop_circle),
                    label: const Text('EMERGENCY STOP'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaturdayColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(MachineState state) {
    switch (state) {
      case MachineState.disconnected:
        return SaturdayColors.secondaryGrey;
      case MachineState.connecting:
        return SaturdayColors.info;
      case MachineState.connected:
      case MachineState.idle:
        return SaturdayColors.success;
      case MachineState.running:
        return SaturdayColors.info;
      case MachineState.paused:
        return Colors.orange;
      case MachineState.alarm:
      case MachineState.error:
        return SaturdayColors.error;
    }
  }

  Widget _buildUnitDetailsSection() {
    // Fetch product and variant data using providers
    final productAsync = ref.watch(productProvider(widget.unit.productId));
    final variantAsync = ref.watch(variantProvider(widget.unit.variantId));

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Unit Information',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Unit ID
            _buildInfoRow(
              label: 'Unit ID',
              value: widget.unit.unitId,
              isLoading: false,
            ),
            const SizedBox(height: 12),

            // Product Name
            productAsync.when(
              data: (product) => _buildInfoRow(
                label: 'Product',
                value: product?.name ?? 'Unknown Product',
                isLoading: false,
              ),
              loading: () => _buildInfoRow(
                label: 'Product',
                value: 'Loading...',
                isLoading: true,
              ),
              error: (error, stack) => _buildInfoRow(
                label: 'Product',
                value: 'Error loading',
                isLoading: false,
              ),
            ),
            const SizedBox(height: 12),

            // Variant Name
            variantAsync.when(
              data: (variant) => _buildInfoRow(
                label: 'Variant',
                value: variant?.getFormattedVariantName() ?? 'Unknown Variant',
                isLoading: false,
              ),
              loading: () => _buildInfoRow(
                label: 'Variant',
                value: 'Loading...',
                isLoading: true,
              ),
              error: (error, stack) => _buildInfoRow(
                label: 'Variant',
                value: 'Error loading',
                isLoading: false,
              ),
            ),
            const SizedBox(height: 12),

            // SKU
            variantAsync.when(
              data: (variant) => _buildInfoRow(
                label: 'SKU',
                value: variant?.sku ?? 'Unknown SKU',
                isLoading: false,
              ),
              loading: () => _buildInfoRow(
                label: 'SKU',
                value: 'Loading...',
                isLoading: true,
              ),
              error: (error, stack) => _buildInfoRow(
                label: 'SKU',
                value: 'Error loading',
                isLoading: false,
              ),
            ),

            // Order Number (if available)
            if (widget.unit.shopifyOrderNumber != null) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                label: 'Order Number',
                value: widget.unit.shopifyOrderNumber!,
                isLoading: false,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required bool isLoading,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: SaturdayColors.secondaryGrey,
              fontSize: 14,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildMachineControlsSection() {
    final canControl = _machineState == MachineState.idle ||
        _machineState == MachineState.connected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Machine Controls',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                // Home button
                OutlinedButton.icon(
                  onPressed: canControl ? _home : null,
                  icon: const Icon(Icons.home),
                  label: const Text('Home (\$H)'),
                ),
                // Set X zero
                OutlinedButton.icon(
                  onPressed: canControl ? () => _setZero(x: true) : null,
                  icon: const Icon(Icons.crop_square),
                  label: const Text('Set X0'),
                ),
                // Set Y zero
                OutlinedButton.icon(
                  onPressed: canControl ? () => _setZero(y: true) : null,
                  icon: const Icon(Icons.crop_square),
                  label: const Text('Set Y0'),
                ),
                // Set Z zero
                OutlinedButton.icon(
                  onPressed: canControl ? () => _setZero(z: true) : null,
                  icon: const Icon(Icons.crop_square),
                  label: const Text('Set Z0'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Jog Controls
            _buildJogControlsSection(canControl),
          ],
        ),
      ),
    );
  }

  Widget _buildJogControlsSection(bool canControl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Jog Controls',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),

        // Jog mode selector
        Row(
          children: [
            const Text('Mode: ', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            SegmentedButton<JogMode>(
              segments: JogMode.values.map((mode) {
                return ButtonSegment<JogMode>(
                  value: mode,
                  label: Text('${mode.label} (${mode.displayText})'),
                );
              }).toList(),
              selected: {_jogMode},
              onSelectionChanged: canControl
                  ? (Set<JogMode> newSelection) {
                      setState(() {
                        _jogMode = newSelection.first;
                      });
                    }
                  : null,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith<Color>(
                  (states) {
                    if (states.contains(WidgetState.selected)) {
                      return SaturdayColors.primaryDark;
                    }
                    return Colors.grey.shade200;
                  },
                ),
                foregroundColor: WidgetStateProperty.resolveWith<Color>(
                  (states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return SaturdayColors.primaryDark;
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Jog buttons layout
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // X and Y controls
            Column(
              children: [
                // Y+
                _buildJogButton('Y', true, canControl, Icons.arrow_upward),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // X-
                    _buildJogButton('X', false, canControl, Icons.arrow_back),
                    const SizedBox(width: 8),
                    // Center indicator
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
                      ),
                      child: const Icon(Icons.control_camera, size: 32),
                    ),
                    const SizedBox(width: 8),
                    // X+
                    _buildJogButton('X', true, canControl, Icons.arrow_forward),
                  ],
                ),
                const SizedBox(height: 8),
                // Y-
                _buildJogButton('Y', false, canControl, Icons.arrow_downward),
              ],
            ),
            const SizedBox(width: 32),
            // Z controls
            Column(
              children: [
                // Z+
                _buildJogButton('Z', true, canControl, Icons.arrow_upward),
                const SizedBox(height: 8),
                Container(
                  width: 60,
                  height: 60,
                  alignment: Alignment.center,
                  child: const Text(
                    'Z',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: SaturdayColors.secondaryGrey,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Z-
                _buildJogButton('Z', false, canControl, Icons.arrow_downward),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildJogButton(
      String axis, bool positive, bool canControl, IconData icon) {
    final direction = positive ? '+' : '-';
    final axisDirection = '$axis$direction';
    final isJogging = _joggingAxis == axisDirection;

    return GestureDetector(
      onTapDown: canControl && !_streaming.isStreaming && !_isMacroExecuting
          ? (_) => _startJogging(axis, positive)
          : null,
      onTapUp: (_) => _stopJogging(),
      onTapCancel: () => _stopJogging(),
      onLongPressStart: canControl && !_streaming.isStreaming && !_isMacroExecuting
          ? (_) => _startContinuousJogging(axis, positive)
          : null,
      onLongPressEnd: (_) => _stopJogging(),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isJogging
              ? SaturdayColors.info
              : (canControl && !_streaming.isStreaming && !_isMacroExecuting
                  ? SaturdayColors.primaryDark
                  : SaturdayColors.secondaryGrey.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 32,
          color: canControl && !_streaming.isStreaming && !_isMacroExecuting
              ? Colors.white
              : SaturdayColors.secondaryGrey,
        ),
      ),
    );
  }

  Widget _buildQuickMacrosSection() {
    // Determine machine type and fetch appropriate macros
    final machineType = widget.step.stepType.isCnc ? 'cnc' : 'laser';
    final macrosAsync = widget.step.stepType.isCnc
        ? ref.watch(cncMacrosProvider)
        : ref.watch(laserMacrosProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  widget.step.stepType.isCnc ? Icons.precision_manufacturing : Icons.flash_on,
                  size: 20,
                  color: SaturdayColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Text(
                  'Quick Macros',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            macrosAsync.when(
              data: (macros) {
                if (macros.isEmpty) {
                  return Text(
                    'No macros configured for ${machineType.toUpperCase()} machines',
                    style: const TextStyle(
                      color: SaturdayColors.secondaryGrey,
                      fontSize: 14,
                    ),
                  );
                }

                // Horizontal scrollable row of macro buttons
                return SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: macros.length,
                    itemBuilder: (context, index) {
                      final macro = macros[index];
                      final isExecuting = _executingMacroId == macro.id;
                      final canExecute = _canExecute() && !_isMacroExecuting;

                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _buildMacroButton(macro, canExecute, isExecuting),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Text(
                'Error loading macros: $error',
                style: const TextStyle(
                  color: SaturdayColors.error,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroButton(MachineMacro macro, bool canExecute, bool isExecuting) {
    return Tooltip(
      message: macro.description ?? macro.name,
      child: Material(
        elevation: canExecute ? 2 : 0,
        borderRadius: BorderRadius.circular(12),
        color: canExecute
            ? SaturdayColors.primaryDark
            : SaturdayColors.secondaryGrey.withValues(alpha: 0.3),
        child: InkWell(
          onTap: canExecute ? () => _executeMacro(macro) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 90,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isExecuting)
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  Icon(
                    macro.getIconData(),
                    size: 32,
                    color: canExecute ? Colors.white : SaturdayColors.secondaryGrey,
                  ),
                const SizedBox(height: 8),
                Text(
                  macro.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: canExecute ? Colors.white : SaturdayColors.secondaryGrey,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGCodeFilesSection() {
    final filesAsync = ref.watch(stepGCodeFilesProvider(widget.step.id));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Execution Queue',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: filesAsync.when(
                data: (files) {
                  if (files.isEmpty && !widget.step.engraveQr) {
                    return const Center(
                      child: Text('No gCode files configured for this step'),
                    );
                  }

                  return ListView(
                    children: [
                      // gCode files
                      ...files.asMap().entries.map((entry) {
                        final index = entry.key;
                        final stepGCodeFile = entry.value;
                        final file = stepGCodeFile.gcodeFile!;
                        final completed = _gcodeFileCompleted[file.id] ?? false;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: completed
                              ? SaturdayColors.success.withValues(alpha: 0.1)
                              : null,
                          child: ListTile(
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: completed
                                    ? SaturdayColors.success
                                    : SaturdayColors.primaryDark,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: completed
                                    ? const Icon(Icons.check,
                                        color: Colors.white, size: 20)
                                    : Text(
                                        '${index + 1}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            title: Text(
                              file.description ?? file.fileName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: file.description != null
                                ? Text(
                                    file.fileName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  )
                                : null,
                            trailing: ElevatedButton.icon(
                              onPressed: _canExecute() && !completed
                                  ? () => _runGCodeFile(file)
                                  : null,
                              icon: const Icon(Icons.play_arrow),
                              label: Text(completed ? 'Completed' : 'Run'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: completed
                                    ? SaturdayColors.secondaryGrey
                                    : SaturdayColors.primaryDark,
                              ),
                            ),
                          ),
                        );
                      }),

                      // QR Engraving (if enabled)
                      if (widget.step.engraveQr) ...[
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: _qrEngraveCompleted
                              ? SaturdayColors.success.withValues(alpha: 0.1)
                              : null,
                          child: ListTile(
                            leading: Icon(
                              Icons.qr_code,
                              size: 32,
                              color: _qrEngraveCompleted
                                  ? SaturdayColors.success
                                  : SaturdayColors.primaryDark,
                            ),
                            title: const Text('Engrave QR Code'),
                            subtitle: Text(
                              '${widget.step.qrSize}" square '
                              'at ${widget.step.qrPowerPercent}% power',
                            ),
                            trailing: ElevatedButton.icon(
                              onPressed:
                                  _canExecute() && !_qrEngraveCompleted
                                      ? _runQREngrave
                                      : null,
                              icon: const Icon(Icons.flash_on),
                              label: Text(_qrEngraveCompleted
                                  ? 'Completed'
                                  : 'Run Engrave'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _qrEngraveCompleted
                                    ? SaturdayColors.secondaryGrey
                                    : SaturdayColors.info,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, stack) => Center(
                  child: Text('Error loading files: $error'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canExecute() {
    return (_machineState == MachineState.idle ||
            _machineState == MachineState.connected) &&
           !_streaming.isStreaming;
  }

  Widget _buildProgressSection() {
    if (_currentProgress == null) return const SizedBox.shrink();

    return Card(
      color: SaturdayColors.info.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timelapse, color: SaturdayColors.info),
                const SizedBox(width: 8),
                Text(
                  'Execution Progress',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            LinearProgressIndicator(
              value: _currentProgress!.percentComplete / 100,
              backgroundColor: SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
              valueColor:
                  const AlwaysStoppedAnimation(SaturdayColors.success),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Line ${_currentProgress!.currentLineNumber} of ${_currentProgress!.totalLines}',
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  '${_currentProgress!.percentComplete.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: SaturdayColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Last: ${_currentProgress!.lastCommand}',
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: SaturdayColors.secondaryGrey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            // Control buttons
            Row(
              children: [
                if (_streaming.isPaused)
                  ElevatedButton.icon(
                    onPressed: _streaming.resume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaturdayColors.success,
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _streaming.pause,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                  ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _streaming.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SaturdayColors.error,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Unit'),
          ),
        ),
      ],
    );
  }

  // Action methods
  Future<void> _connect() async {
    if (_selectedPort == null) return;

    final success = await _machine.connect(
      portName: _selectedPort!,
      machineType: widget.step.stepType.isCnc
          ? MachineType.cnc
          : MachineType.laser,
    );

    if (mounted) {
      if (success) {
        // Save port for next time
        final storage = ref.read(machineConfigStorageProvider);
        if (widget.step.stepType.isCnc) {
          await storage.setCncPort(_selectedPort!);
        } else {
          await storage.setLaserPort(_selectedPort!);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected to machine'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  void _disconnect() {
    _machine.disconnect();
  }

  Future<void> _emergencyStop() async {
    await _machine.emergencyStop();
    _streaming.stop();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('EMERGENCY STOP ACTIVATED'),
          backgroundColor: SaturdayColors.error,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _home() async {
    final success = await _machine.home();

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Homing complete')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Homing failed'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Future<void> _setZero({bool x = false, bool y = false, bool z = false}) async {
    final success = await _machine.setZero(x: x, y: y, z: z);

    final axes = <String>[];
    if (x) axes.add('X');
    if (y) axes.add('Y');
    if (z) axes.add('Z');

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Set ${axes.join(', ')} to zero')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to set zero'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  // Jog control methods
  void _startJogging(String axis, bool positive) {
    // Single jog increment using GRBL $J= command
    final direction = positive ? '+' : '-';
    final distance = _jogMode.distance;
    final feedRate = _jogMode == JogMode.rapid ? 2000 : (_jogMode == JogMode.normal ? 1000 : 500);

    // GRBL jog command format: $J=G91 X10 F1000
    final command = '\$J=G91 $axis${positive ? distance : -distance} F$feedRate';

    AppLogger.info('Single jog: $command');

    setState(() {
      _joggingAxis = '$axis$direction';
    });

    _machine.sendCommand(command).then((success) {
      if (mounted && success) {
        // Clear jogging state after a short delay
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            setState(() {
              _joggingAxis = null;
            });
          }
        });
      }
    });
  }

  void _startContinuousJogging(String axis, bool positive) {
    // For continuous jogging, send a large distance that will be cancelled when button is released
    final direction = positive ? '+' : '-';
    final axisDirection = '$axis$direction';
    final feedRate = _jogMode == JogMode.rapid ? 2000 : (_jogMode == JogMode.normal ? 1000 : 500);

    AppLogger.info('Starting continuous jog: $axisDirection at $feedRate mm/min');

    setState(() {
      _joggingAxis = axisDirection;
    });

    // Send a large jog distance that will be cancelled when button is released
    // Use 1000mm as a "large enough" distance for continuous movement
    final largeDistance = positive ? 1000.0 : -1000.0;
    final command = '\$J=G91 $axis$largeDistance F$feedRate';

    _machine.sendCommand(command).catchError((error) {
      AppLogger.error('Jog command failed', error);
      _stopJogging();
      return false;
    });
  }

  void _stopJogging() {
    if (_joggingAxis != null) {
      AppLogger.info('Stopping jog');

      // Send jog cancel command (0x85 in ASCII, or use feed hold)
      // GRBL jog cancel is Ctrl-X (0x18) which is the same as soft reset
      // So we use feed hold (!) instead which can be resumed, but for jogging we want to cancel
      _machine.sendCommand('\x85'); // Jog cancel character

      // Clear jogging state
      if (mounted) {
        setState(() {
          _joggingAxis = null;
        });
      }
    }

    // Cancel any timer if it exists (for old implementation compatibility)
    if (_jogTimer != null) {
      _jogTimer!.cancel();
      _jogTimer = null;
    }
  }

  Future<void> _executeMacro(MachineMacro macro) async {
    // Validate macro has commands
    if (macro.gcodeCommands.trim().isEmpty) {
      AppLogger.warning('Macro ${macro.name} has no commands');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Macro "${macro.name}" has no commands'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
      return;
    }

    // Set executing state
    setState(() {
      _isMacroExecuting = true;
      _executingMacroId = macro.id;
    });

    AppLogger.info('Executing macro: ${macro.name}');

    try {
      // Parse gcode commands (split by lines, trim whitespace, filter empty)
      final commands = macro.getCommandLines();

      if (commands.isEmpty) {
        throw Exception('No valid commands in macro');
      }

      AppLogger.info('Executing ${commands.length} commands from macro ${macro.name}');

      // Send each command to machine sequentially
      int successCount = 0;
      String? failedCommand;

      for (final command in commands) {
        AppLogger.info('Sending macro command: $command');

        try {
          final success = await _machine.sendCommand(command);

          if (success) {
            successCount++;
            // Small delay between commands to allow machine to process
            await Future.delayed(const Duration(milliseconds: 100));
          } else {
            failedCommand = command;
            AppLogger.error('Macro command failed: $command');
            break;
          }
        } catch (e) {
          failedCommand = command;
          AppLogger.error('Error sending macro command: $command', e);
          break;
        }

        // Check if machine disconnected during execution
        if (_machineState == MachineState.disconnected) {
          throw Exception('Machine disconnected during macro execution');
        }
      }

      // Clear executing state
      if (mounted) {
        setState(() {
          _isMacroExecuting = false;
          _executingMacroId = null;
        });
      }

      // Show result
      if (mounted) {
        if (failedCommand != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Macro "${macro.name}" failed at command: $failedCommand\n'
                'Executed $successCount of ${commands.length} commands',
              ),
              backgroundColor: SaturdayColors.error,
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          AppLogger.info('Macro ${macro.name} completed successfully');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Macro "${macro.name}" executed successfully\n'
                '${commands.length} commands sent',
              ),
              backgroundColor: SaturdayColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error executing macro ${macro.name}', e, stackTrace);

      // Clear executing state
      if (mounted) {
        setState(() {
          _isMacroExecuting = false;
          _executingMacroId = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error executing macro "${macro.name}": $e'),
            backgroundColor: SaturdayColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _runGCodeFile(GCodeFile file) async {
    try {
      // Fetch gCode content from GitHub
      final syncService = ref.read(gcodeSyncServiceProvider);
      final gcodeContent = await syncService.fetchGCodeContent(file);

      // Show preview
      setState(() {
        _currentGCodePreview = gcodeContent;
        _currentPreviewFileName = file.description ?? file.fileName;
      });

      // Show confirmation dialog
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ready to Execute'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Execute ${file.fileName}?'),
              const SizedBox(height: 12),
              if (file.description != null) ...[
                Text(
                  file.description!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Review the toolpath preview on the right before executing.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Execution'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.primaryDark,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        // User cancelled, keep preview visible
        return;
      }

      // Stream to machine
      final result = await _streaming.streamGCode(gcodeContent);

      if (mounted) {
        if (result.success) {
          setState(() {
            _gcodeFileCompleted[file.id] = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${file.fileName} completed'),
              backgroundColor: SaturdayColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Execution failed: ${result.message}'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Future<void> _runQREngrave() async {
    try {
      // Generate gCode from QR code image
      final imageService = ref.read(imageToGCodeServiceProvider);
      final gcodeContent = await imageService.generateQREngraveGCode(
        unit: widget.unit,
        step: widget.step,
      );

      // Show preview
      setState(() {
        _currentGCodePreview = gcodeContent;
        _currentPreviewFileName = 'QR Code Engraving';
      });

      // Show confirmation dialog
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ready to Engrave QR Code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Engrave QR code for this unit?'),
              const SizedBox(height: 12),
              Text(
                'Size: ${widget.step.qrSize}" square',
                style: const TextStyle(fontSize: 14),
              ),
              Text(
                'Power: ${widget.step.qrPowerPercent}%',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                'Review the toolpath preview on the right before executing.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.flash_on),
              label: const Text('Start Engraving'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.info,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (confirmed != true) {
        // User cancelled, keep preview visible
        return;
      }

      // Stream to machine
      final result = await _streaming.streamGCode(gcodeContent);

      if (mounted) {
        if (result.success) {
          setState(() {
            _qrEngraveCompleted = true;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('QR code engraving completed'),
              backgroundColor: SaturdayColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Engraving failed: ${result.message}'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  /// Show error details dialog
  void _showErrorDetailsDialog(GrblError error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error, color: Colors.red),
            const SizedBox(width: 8),
            Text('Error ${error.code}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              error.userMessage,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Technical Details:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              error.description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Show alarm details dialog
  void _showAlarmDetailsDialog(GrblAlarm alarm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red.shade900),
            const SizedBox(width: 8),
            Text('Alarm ${alarm.code}'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alarm.name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              alarm.userMessage,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Technical Details:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              alarm.description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You may need to unlock or reset the machine to continue.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
