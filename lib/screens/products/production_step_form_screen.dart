import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/providers/production_step_provider.dart';
import 'package:saturday_app/widgets/common/app_button.dart';

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
  ConsumerState<ProductionStepFormScreen> createState() => _ProductionStepFormScreenState();
}

class _ProductionStepFormScreenState extends ConsumerState<ProductionStepFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  File? _selectedFile;
  String? _selectedFileName;
  int? _selectedFileSize;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.step != null) {
      _nameController.text = widget.step!.name;
      _descriptionController.text = widget.step!.description ?? '';
      _selectedFileName = widget.step!.fileName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
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

              // File section
              Text(
                'Attach File (Optional)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Attach a gcode file, design file, or instruction document',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 16),

              // File picker
              if (_selectedFileName != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SaturdayColors.light,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: SaturdayColors.info),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.attach_file,
                        color: SaturdayColors.info,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedFileName!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                            if (_selectedFileSize != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _formatFileSize(_selectedFileSize!),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: SaturdayColors.secondaryGrey,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _selectedFile = null;
                            _selectedFileName = null;
                            _selectedFileSize = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.upload_file),
                label: Text(_selectedFileName != null ? 'Change File' : 'Select File'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
              ),
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

      if (widget.step != null) {
        // Update existing step
        final updatedStep = widget.step!.copyWith(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          fileName: _selectedFileName,
        );

        await management.updateStep(
          updatedStep,
          file: _selectedFile,
          oldStep: widget.step,
        );

        if (mounted) {
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
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await management.createStep(newStep, file: _selectedFile);

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save step: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
