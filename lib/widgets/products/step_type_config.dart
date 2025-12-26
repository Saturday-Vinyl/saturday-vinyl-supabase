import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/step_type.dart';

/// Widget for configuring step type-specific parameters
class StepTypeConfig extends ConsumerStatefulWidget {
  final StepType stepType;
  final ValueChanged<StepType> onStepTypeChanged;

  // gCode file selection (for CNC/Laser)
  final List<String> selectedGCodeFileIds;
  final ValueChanged<List<String>> onGCodeFilesChanged;

  // QR engraving (for Laser)
  final bool engraveQr;
  final ValueChanged<bool> onEngraveQrChanged;
  final TextEditingController qrXOffsetController;
  final TextEditingController qrYOffsetController;
  final TextEditingController qrSizeController;
  final TextEditingController qrPowerController;
  final TextEditingController qrSpeedController;

  const StepTypeConfig({
    super.key,
    required this.stepType,
    required this.onStepTypeChanged,
    required this.selectedGCodeFileIds,
    required this.onGCodeFilesChanged,
    required this.engraveQr,
    required this.onEngraveQrChanged,
    required this.qrXOffsetController,
    required this.qrYOffsetController,
    required this.qrSizeController,
    required this.qrPowerController,
    required this.qrSpeedController,
  });

  @override
  ConsumerState<StepTypeConfig> createState() => _StepTypeConfigState();
}

class _StepTypeConfigState extends ConsumerState<StepTypeConfig> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step Type Selector
        Text(
          'Step Type',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select the type of production step',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
        const SizedBox(height: 16),

        // Step Type Radio Buttons
        ...StepType.values.map((type) {
          return RadioListTile<StepType>(
            title: Text(type.displayName),
            subtitle: Text(_getStepTypeDescription(type)),
            value: type,
            groupValue: widget.stepType,
            onChanged: (value) {
              if (value != null) {
                widget.onStepTypeChanged(value);
              }
            },
            contentPadding: EdgeInsets.zero,
          );
        }),

        const SizedBox(height: 24),

        // Machine-specific configuration - DEPRECATED
        // File selection is now handled by StepFileSelector widget
        // in production_step_form_screen.dart
        // if (widget.stepType.requiresMachine) ...[
        //   _buildMachineConfigSection(),
        //   const SizedBox(height: 24),
        // ],

        // QR engraving section (Laser only)
        if (widget.stepType == StepType.laserCutting) ...[
          _buildQrEngravingSection(),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  String _getStepTypeDescription(StepType type) {
    switch (type) {
      case StepType.general:
        return 'Manual production work';
      case StepType.cncMilling:
        return 'CNC milling machine operation';
      case StepType.laserCutting:
        return 'Laser cutting/engraving operation';
    }
  }

  // DEPRECATED: Machine config methods removed - file selection now handled by StepFileSelector
  // Widget _buildMachineConfigSection() { ... }
  // Widget _buildGCodeFileSelector(List<GCodeFile> availableFiles) { ... }

  Widget _buildQrEngravingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          title: const Text('Engrave QR Code'),
          subtitle: const Text('Engrave the unit QR code after cutting'),
          value: widget.engraveQr,
          onChanged: (value) {
            widget.onEngraveQrChanged(value ?? false);
          },
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),

        if (widget.engraveQr) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QR Code Parameters',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),

                // Position
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: widget.qrXOffsetController,
                        decoration: const InputDecoration(
                          labelText: 'X Offset (mm)',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Invalid number';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: widget.qrYOffsetController,
                        decoration: const InputDecoration(
                          labelText: 'Y Offset (mm)',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          if (double.tryParse(value) == null) {
                            return 'Invalid number';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Size
                TextFormField(
                  controller: widget.qrSizeController,
                  decoration: const InputDecoration(
                    labelText: 'QR Code Size (mm)',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Required';
                    }
                    final size = double.tryParse(value);
                    if (size == null || size <= 0) {
                      return 'Must be positive';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Power and Speed
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: widget.qrPowerController,
                        decoration: const InputDecoration(
                          labelText: 'Power (%)',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          final power = int.tryParse(value);
                          if (power == null || power < 0 || power > 100) {
                            return '0-100';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: widget.qrSpeedController,
                        decoration: const InputDecoration(
                          labelText: 'Speed (mm/min)',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Required';
                          }
                          final speed = int.tryParse(value);
                          if (speed == null || speed <= 0) {
                            return 'Must be positive';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
