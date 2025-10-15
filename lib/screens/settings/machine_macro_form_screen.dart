import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../config/theme.dart';
import '../../models/machine_macro.dart';
import '../../providers/machine_macro_provider.dart';
import '../../utils/app_logger.dart';
import '../../widgets/settings/icon_picker_widget.dart';

/// Form screen for creating or editing a machine macro
class MachineMacroFormScreen extends ConsumerStatefulWidget {
  final MachineMacro? macro;
  final String machineType;

  const MachineMacroFormScreen({
    super.key,
    this.macro,
    required this.machineType,
  });

  @override
  ConsumerState<MachineMacroFormScreen> createState() =>
      _MachineMacroFormScreenState();
}

class _MachineMacroFormScreenState
    extends ConsumerState<MachineMacroFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _gcodeController = TextEditingController();

  late String _selectedMachineType;
  String _selectedIconName = 'settings';
  bool _isActive = true;
  bool _isSaving = false;

  bool get _isEditing => widget.macro != null;

  @override
  void initState() {
    super.initState();

    if (_isEditing) {
      // Populate form with existing macro data
      _nameController.text = widget.macro!.name;
      _descriptionController.text = widget.macro!.description ?? '';
      _gcodeController.text = widget.macro!.gcodeCommands;
      _selectedMachineType = widget.macro!.machineType;
      _selectedIconName = widget.macro!.iconName;
      _isActive = widget.macro!.isActive;
    } else {
      // New macro - use provided machine type
      _selectedMachineType = widget.machineType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _gcodeController.dispose();
    super.dispose();
  }

  Future<void> _pickIcon() async {
    final selectedIcon = await showDialog<String>(
      context: context,
      builder: (context) => const IconPickerWidget(),
    );

    if (selectedIcon != null) {
      setState(() {
        _selectedIconName = selectedIcon;
      });
    }
  }

  Future<void> _saveMacro() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final macroManagement = ref.read(macroManagementProvider);
      final now = DateTime.now();

      final macro = MachineMacro(
        id: _isEditing ? widget.macro!.id : const Uuid().v4(),
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        machineType: _selectedMachineType,
        iconName: _selectedIconName,
        gcodeCommands: _gcodeController.text.trim(),
        executionOrder: _isEditing ? widget.macro!.executionOrder : 1,
        isActive: _isActive,
        createdAt: _isEditing ? widget.macro!.createdAt : now,
        updatedAt: now,
      );

      // Validate macro
      if (!macro.isValid()) {
        throw Exception('Invalid macro data');
      }

      // Save to database
      if (_isEditing) {
        await macroManagement.updateMacro(macro);
      } else {
        await macroManagement.createMacro(macro);
      }

      AppLogger.info('Macro saved successfully: ${macro.name}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Macro updated' : 'Macro created'),
            backgroundColor: SaturdayColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      AppLogger.error('Error saving macro', e, stackTrace);
      setState(() => _isSaving = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving macro: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteMacro() async {
    if (!_isEditing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Macro'),
        content: Text('Are you sure you want to delete "${widget.macro!.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SaturdayColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final macroManagement = ref.read(macroManagementProvider);
        await macroManagement.deleteMacro(widget.macro!.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "${widget.macro!.name}"'),
              backgroundColor: SaturdayColors.success,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e, stackTrace) {
        AppLogger.error('Error deleting macro', e, stackTrace);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting macro: $e'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Macro' : 'New Macro'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _isSaving ? null : _deleteMacro,
              tooltip: 'Delete macro',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g., Spindle On, Laser Test Fire',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Description field
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Tooltip text shown on hover',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),

              // Machine Type dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedMachineType,
                decoration: const InputDecoration(
                  labelText: 'Machine Type *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cnc', child: Text('CNC')),
                  DropdownMenuItem(value: 'laser', child: Text('Laser')),
                ],
                onChanged: _isEditing
                    ? null // Disable changing machine type when editing
                    : (value) {
                        if (value != null) {
                          setState(() => _selectedMachineType = value);
                        }
                      },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Machine type is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Icon picker
              Text(
                'Icon *',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickIcon,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: SaturdayColors.secondaryGrey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            SaturdayColors.primaryDark.withValues(alpha: 0.1),
                        child: Icon(
                          MachineMacro(
                            id: '',
                            name: '',
                            machineType: 'cnc',
                            iconName: _selectedIconName,
                            gcodeCommands: '',
                            executionOrder: 1,
                            isActive: true,
                            createdAt: DateTime.now(),
                            updatedAt: DateTime.now(),
                          ).getIconData(),
                          color: SaturdayColors.primaryDark,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _selectedIconName,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // GCode commands field
              TextFormField(
                controller: _gcodeController,
                decoration: const InputDecoration(
                  labelText: 'GCode Commands *',
                  hintText: 'M3 S12000\nG4 P0.5\nM5',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                ),
                maxLines: 10,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'GCode commands are required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter one command per line. Lines will be sent sequentially to the machine.',
                style: TextStyle(
                  fontSize: 12,
                  color: SaturdayColors.secondaryGrey,
                ),
              ),
              const SizedBox(height: 20),

              // Active checkbox
              CheckboxListTile(
                title: const Text('Active'),
                subtitle: const Text('Inactive macros will not appear in machine control'),
                value: _isActive,
                onChanged: (value) {
                  setState(() => _isActive = value ?? true);
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 32),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveMacro,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SaturdayColors.primaryDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(_isEditing ? 'Update Macro' : 'Create Macro'),
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
}
