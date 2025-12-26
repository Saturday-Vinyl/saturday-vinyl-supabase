import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/step_type.dart';
import 'package:saturday_app/providers/file_provider.dart';
import 'package:saturday_app/providers/production_step_provider.dart';
import 'package:saturday_app/providers/step_label_provider.dart';
import 'package:saturday_app/providers/step_timer_provider.dart';
import 'package:saturday_app/widgets/common/app_button.dart';
import 'package:saturday_app/widgets/products/step_file_selector.dart';
import 'package:saturday_app/widgets/products/step_type_config.dart';

/// Form screen for creating or editing a production step
class ProductionStepFormScreen extends ConsumerStatefulWidget {
  final Product product;
  final ProductionStep? step; // null for create, non-null for edit

  const ProductionStepFormScreen({
    super.key,
    required this.product,
    this.step,
  });

  @override
  ConsumerState<ProductionStepFormScreen> createState() =>
      _ProductionStepFormScreenState();
}

class _ProductionStepFormScreenState
    extends ConsumerState<ProductionStepFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  File? _selectedFile;
  String? _selectedFileName;
  int? _selectedFileSize;
  bool _isLoading = false;
  bool _isLoadingLabels = false;

  // Step type
  StepType _stepType = StepType.general;

  // gCode file selection (for CNC/Laser steps)
  List<String> _selectedGCodeFileIds = [];

  // QR engraving parameters (for Laser steps)
  bool _engraveQr = false;
  final _qrXOffsetController = TextEditingController();
  final _qrYOffsetController = TextEditingController();
  final _qrSizeController = TextEditingController();
  final _qrPowerController = TextEditingController();
  final _qrSpeedController = TextEditingController();

  // Multiple label controllers
  List<TextEditingController> _labelControllers = [];

  // Multiple timer controllers
  List<Map<String, TextEditingController>> _timerControllers = [];
  bool _isLoadingTimers = false;

  @override
  void initState() {
    super.initState();
    if (widget.step != null) {
      _nameController.text = widget.step!.name;
      _descriptionController.text = widget.step!.description ?? '';
      _selectedFileName = widget.step!.fileName;

      // Load step type and machine-specific fields
      _stepType = widget.step!.stepType;

      // Load QR engraving parameters
      _engraveQr = widget.step!.engraveQr;
      if (widget.step!.qrXOffset != null) {
        _qrXOffsetController.text = widget.step!.qrXOffset.toString();
      }
      if (widget.step!.qrYOffset != null) {
        _qrYOffsetController.text = widget.step!.qrYOffset.toString();
      }
      if (widget.step!.qrSize != null) {
        _qrSizeController.text = widget.step!.qrSize.toString();
      }
      if (widget.step!.qrPowerPercent != null) {
        _qrPowerController.text = widget.step!.qrPowerPercent.toString();
      }
      if (widget.step!.qrSpeedMmMin != null) {
        _qrSpeedController.text = widget.step!.qrSpeedMmMin.toString();
      }

      // Load attached files from new file system
      _loadExistingFiles();

      // Load existing labels
      _loadExistingLabels();

      // Load existing timers
      _loadExistingTimers();
    }
  }

  Future<void> _loadExistingLabels() async {
    if (widget.step == null) return;

    setState(() {
      _isLoadingLabels = true;
    });

    try {
      final labels =
          await ref.read(stepLabelsProvider(widget.step!.id).future);

      if (mounted) {
        setState(() {
          _labelControllers = labels
              .map((label) => TextEditingController(text: label.labelText))
              .toList();
          _isLoadingLabels = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoadingLabels = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load labels: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Future<void> _loadExistingTimers() async {
    if (widget.step == null) return;

    setState(() {
      _isLoadingTimers = true;
    });

    try {
      final timers =
          await ref.read(stepTimersProvider(widget.step!.id).future);

      if (mounted) {
        setState(() {
          _timerControllers = timers
              .map((timer) => {
                    'name': TextEditingController(text: timer.timerName),
                    'duration': TextEditingController(
                        text: timer.durationMinutes.toString()),
                  })
              .toList();
          _isLoadingTimers = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoadingTimers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load timers: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Future<void> _loadExistingFiles() async {
    if (widget.step == null) return;

    try {
      final stepFiles =
          await ref.read(stepFilesProvider(widget.step!.id).future);

      if (mounted) {
        setState(() {
          _selectedGCodeFileIds = stepFiles.map((sf) => sf.fileId).toList();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load attached files: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _qrXOffsetController.dispose();
    _qrYOffsetController.dispose();
    _qrSizeController.dispose();
    _qrPowerController.dispose();
    _qrSpeedController.dispose();
    for (final controller in _labelControllers) {
      controller.dispose();
    }
    for (final timerControllerMap in _timerControllers) {
      timerControllerMap['name']?.dispose();
      timerControllerMap['duration']?.dispose();
    }
    super.dispose();
  }

  void _addLabel() {
    setState(() {
      _labelControllers.add(TextEditingController());
    });
  }

  void _removeLabel(int index) {
    setState(() {
      _labelControllers[index].dispose();
      _labelControllers.removeAt(index);
    });
  }

  void _addTimer() {
    setState(() {
      _timerControllers.add({
        'name': TextEditingController(),
        'duration': TextEditingController(),
      });
    });
  }

  void _removeTimer(int index) {
    setState(() {
      _timerControllers[index]['name']?.dispose();
      _timerControllers[index]['duration']?.dispose();
      _timerControllers.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.step != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Production Step' : 'Add Production Step'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Product info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SaturdayColors.light,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.product.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Step Name *',
                  hintText: 'e.g., CNC Machining',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a step name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description field
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Detailed instructions for this step...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 24),

              // Step Type Configuration
              StepTypeConfig(
                stepType: _stepType,
                onStepTypeChanged: (type) {
                  setState(() {
                    _stepType = type;
                  });
                },
                selectedGCodeFileIds: _selectedGCodeFileIds,
                onGCodeFilesChanged: (ids) {
                  setState(() {
                    _selectedGCodeFileIds = ids;
                  });
                },
                engraveQr: _engraveQr,
                onEngraveQrChanged: (value) {
                  setState(() {
                    _engraveQr = value;
                  });
                },
                qrXOffsetController: _qrXOffsetController,
                qrYOffsetController: _qrYOffsetController,
                qrSizeController: _qrSizeController,
                qrPowerController: _qrPowerController,
                qrSpeedController: _qrSpeedController,
              ),

              const SizedBox(height: 24),

              // File Attachments (for all step types)
              // Workers can attach gcode files, spec documents, instructions, etc.
              StepFileSelector(
                stepId: widget.step?.id,
                selectedFileIds: _selectedGCodeFileIds,
                onFilesChanged: (ids) {
                  setState(() {
                    _selectedGCodeFileIds = ids;
                  });
                },
              ),
              const SizedBox(height: 24),

              const Divider(),
              const SizedBox(height: 24),

              // DEPRECATED: Old single-file attachment section
              // Replaced by StepFileSelector widget above
              // Keeping code commented for reference during migration
              // if (false) ...[
              //   Text('Attach File (Optional)', ...),
              //   ...file picker UI...
              // ],

              // Label configuration section
              Text(
                'Label Configuration',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add one or more labels to print when this step is completed. '
                'Example: "LEFT SIDE", "RIGHT SIDE" for parts that come in pairs.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 16),

              // Show loading indicator while loading labels
              if (_isLoadingLabels)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                // Label list
                ..._labelControllers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final controller = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        // Label order badge
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: SaturdayColors.primaryDark,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Text field
                        Expanded(
                          child: TextFormField(
                            controller: controller,
                            decoration: InputDecoration(
                              labelText: 'Label ${index + 1}',
                              hintText: 'e.g., LEFT SIDE',
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter label text';
                              }
                              return null;
                            },
                          ),
                        ),

                        // Delete button
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: SaturdayColors.error,
                          onPressed: () => _removeLabel(index),
                          tooltip: 'Remove label',
                        ),
                      ],
                    ),
                  );
                }).toList(),

                // Add label button
                OutlinedButton.icon(
                  onPressed: _addLabel,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Label'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Timer configuration section
              Text(
                'Timer Configuration',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add optional timers that can be started when completing this step (e.g., "Cure Time - 15 min", "Cool Down - 30 min")',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 16),

              // Show loading indicator while loading timers
              if (_isLoadingTimers)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                )
              else ...[
                // Timer list
                ..._timerControllers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final nameController = entry.value['name']!;
                  final durationController = entry.value['duration']!;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        // Timer order badge
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: SaturdayColors.info,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Timer name field
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: nameController,
                            decoration: InputDecoration(
                              labelText: 'Timer ${index + 1} Name',
                              hintText: 'e.g., Cure Time',
                              border: const OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter timer name';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Duration field
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: durationController,
                            decoration: const InputDecoration(
                              labelText: 'Minutes',
                              hintText: '15',
                              border: OutlineInputBorder(),
                              suffixText: 'min',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Required';
                              }
                              final duration = int.tryParse(value);
                              if (duration == null || duration <= 0) {
                                return 'Invalid';
                              }
                              return null;
                            },
                          ),
                        ),

                        // Delete button
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          color: SaturdayColors.error,
                          onPressed: () => _removeTimer(index),
                          tooltip: 'Remove timer',
                        ),
                      ],
                    ),
                  );
                }),

                // Add timer button
                OutlinedButton.icon(
                  onPressed: _addTimer,
                  icon: const Icon(Icons.timer),
                  label: const Text('Add Timer'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: 'Cancel',
                      style: AppButtonStyle.secondary,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AppButton(
                      text: isEditing ? 'Save Changes' : 'Create Step',
                      onPressed: _isLoading ? null : _handleSubmit,
                      isLoading: _isLoading,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pick a file using file picker
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          if (file.path != null) {
            _selectedFile = File(file.path!);
          }
          _selectedFileName = file.name;
          _selectedFileSize = file.size;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick file: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  /// Format file size for display
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }

  /// Handle form submission
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final management = ref.read(productionStepManagementProvider);
      final labelManagement = ref.read(stepLabelManagementProvider);
      final timerManagement = ref.read(stepTimerManagementProvider);
      final fileManagement = ref.read(fileManagementProvider);

      // Parse QR parameters if QR engraving is enabled
      double? qrXOffset;
      double? qrYOffset;
      double? qrSize;
      int? qrPowerPercent;
      int? qrSpeedMmMin;

      if (_engraveQr) {
        try {
          qrXOffset = double.parse(_qrXOffsetController.text.trim());
          qrYOffset = double.parse(_qrYOffsetController.text.trim());
          qrSize = double.parse(_qrSizeController.text.trim());
          qrPowerPercent = int.parse(_qrPowerController.text.trim());
          qrSpeedMmMin = int.parse(_qrSpeedController.text.trim());

          // Validate QR parameters
          if (qrSize <= 0) {
            throw const FormatException('QR size must be positive');
          }
          if (qrPowerPercent < 0 || qrPowerPercent > 100) {
            throw const FormatException('Power must be between 0 and 100');
          }
          if (qrSpeedMmMin <= 0) {
            throw const FormatException('Speed must be positive');
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Invalid QR parameters: $e'),
                backgroundColor: SaturdayColors.error,
              ),
            );
          }
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      if (widget.step != null) {
        // Update existing step
        final updatedStep = widget.step!.copyWith(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          fileName: _selectedFileName,
          stepType: _stepType,
          engraveQr: _engraveQr,
          qrXOffset: qrXOffset,
          qrYOffset: qrYOffset,
          qrSize: qrSize,
          qrPowerPercent: qrPowerPercent,
          qrSpeedMmMin: qrSpeedMmMin,
        );

        await management.updateStep(
          updatedStep,
          file: null, // DEPRECATED: Now using file library system
          oldStep: widget.step,
        );

        // Update file associations
        await fileManagement.attachFilesToStep(
          stepId: widget.step!.id,
          fileIds: _selectedGCodeFileIds,
        );

        // Update labels
        final labelTexts = _labelControllers
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();

        await labelManagement.updateLabelsForStep(
          widget.step!.id,
          labelTexts,
        );

        // Update timers
        final timerConfigs = _timerControllers
            .where((controllers) =>
                controllers['name']!.text.trim().isNotEmpty &&
                controllers['duration']!.text.trim().isNotEmpty)
            .map((controllers) => {
                  'name': controllers['name']!.text.trim(),
                  'duration': int.parse(controllers['duration']!.text.trim()),
                })
            .toList();

        await timerManagement.updateTimersForStep(
          widget.step!.id,
          timerConfigs,
        );

        if (mounted) {
          // Invalidate the providers to refresh
          ref.invalidate(stepLabelsProvider(widget.step!.id));
          ref.invalidate(stepTimersProvider(widget.step!.id));

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Production step updated'),
              backgroundColor: SaturdayColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        // Create new step
        final nextOrder = await management.getNextStepOrder(widget.product.id);

        final newStep = ProductionStep(
          id: '', // Will be generated by repository
          productId: widget.product.id,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          stepOrder: nextOrder,
          fileName: _selectedFileName,
          stepType: _stepType,
          engraveQr: _engraveQr,
          qrXOffset: qrXOffset,
          qrYOffset: qrYOffset,
          qrSize: qrSize,
          qrPowerPercent: qrPowerPercent,
          qrSpeedMmMin: qrSpeedMmMin,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final createdStep = await management.createStep(
          newStep,
          file: null, // DEPRECATED: Now using file library system
        );

        // Save file associations
        if (_selectedGCodeFileIds.isNotEmpty) {
          await fileManagement.attachFilesToStep(
            stepId: createdStep.id,
            fileIds: _selectedGCodeFileIds,
          );
        }

        // Create labels
        final labelTexts = _labelControllers
            .map((c) => c.text.trim())
            .where((t) => t.isNotEmpty)
            .toList();

        if (labelTexts.isNotEmpty) {
          await labelManagement.batchCreateLabels(
            createdStep.id,
            labelTexts,
          );
        }

        // Create timers
        final timerConfigs = _timerControllers
            .where((controllers) =>
                controllers['name']!.text.trim().isNotEmpty &&
                controllers['duration']!.text.trim().isNotEmpty)
            .map((controllers) => {
                  'name': controllers['name']!.text.trim(),
                  'duration': int.parse(controllers['duration']!.text.trim()),
                })
            .toList();

        if (timerConfigs.isNotEmpty) {
          await timerManagement.batchCreateTimers(
            createdStep.id,
            timerConfigs,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Production step created'),
              backgroundColor: SaturdayColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (error) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save step: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }
}
