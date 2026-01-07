import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/widgets/common/app_button.dart';

/// Form screen for creating or editing a device type
class DeviceTypeFormScreen extends ConsumerStatefulWidget {
  final DeviceType? deviceType; // null for create, non-null for edit

  const DeviceTypeFormScreen({
    super.key,
    this.deviceType,
  });

  @override
  ConsumerState<DeviceTypeFormScreen> createState() =>
      _DeviceTypeFormScreenState();
}

class _DeviceTypeFormScreenState extends ConsumerState<DeviceTypeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _firmwareController = TextEditingController();
  final _specUrlController = TextEditingController();

  List<String> _selectedCapabilities = [];
  String? _selectedChipType;
  bool _isActive = true;
  bool _isLoading = false;

  // Available ESP32 chip types for firmware provisioning
  static const List<String> _chipTypes = [
    'esp32',
    'esp32s2',
    'esp32s3',
    'esp32c3',
    'esp32c6',
    'esp32h2',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.deviceType != null) {
      _nameController.text = widget.deviceType!.name;
      _descriptionController.text = widget.deviceType!.description ?? '';
      _firmwareController.text =
          widget.deviceType!.currentFirmwareVersion ?? '';
      _specUrlController.text = widget.deviceType!.specUrl ?? '';
      _selectedCapabilities = List.from(widget.deviceType!.capabilities);
      _selectedChipType = widget.deviceType!.chipType;
      _isActive = widget.deviceType!.isActive;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _firmwareController.dispose();
    _specUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.deviceType != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Device Type' : 'Add Device Type'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g., ESP32-S3',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
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
                  hintText: 'Brief description of the device',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Firmware version field
              TextFormField(
                controller: _firmwareController,
                decoration: const InputDecoration(
                  labelText: 'Current Firmware Version',
                  hintText: 'e.g., v1.2.3',
                ),
              ),
              const SizedBox(height: 16),

              // Spec URL field
              TextFormField(
                controller: _specUrlController,
                decoration: const InputDecoration(
                  labelText: 'Specification URL',
                  hintText: 'Link to datasheet or docs',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),

              // Chip Type (for firmware provisioning)
              DropdownButtonFormField<String>(
                value: _selectedChipType,
                decoration: const InputDecoration(
                  labelText: 'ESP32 Chip Type (Optional)',
                  hintText: 'Select chip type for firmware flashing',
                  prefixIcon: Icon(Icons.memory),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('-- None --'),
                  ),
                  ..._chipTypes.map((type) => DropdownMenuItem<String>(
                        value: type,
                        child: Text(type.toUpperCase()),
                      )),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedChipType = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              Text(
                'Set chip type if this device uses an ESP32 microcontroller for firmware provisioning',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 24),

              // Capabilities
              Text(
                'Capabilities',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: DeviceCapabilities.all.map((capability) {
                  final isSelected = _selectedCapabilities.contains(capability);
                  return FilterChip(
                    label:
                        Text(DeviceCapabilities.getDisplayName(capability)),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedCapabilities.add(capability);
                        } else {
                          _selectedCapabilities.remove(capability);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Active status
              SwitchListTile(
                title: const Text('Active'),
                subtitle: const Text('Inactive devices won\'t appear in lists'),
                value: _isActive,
                onChanged: (value) {
                  setState(() {
                    _isActive = value;
                  });
                },
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
                      text: isEditing ? 'Save Changes' : 'Create',
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

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final management = ref.read(deviceTypeManagementProvider);

      if (widget.deviceType != null) {
        // Update existing device type
        final updatedDeviceType = widget.deviceType!.copyWith(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          currentFirmwareVersion: _firmwareController.text.trim().isEmpty
              ? null
              : _firmwareController.text.trim(),
          specUrl: _specUrlController.text.trim().isEmpty
              ? null
              : _specUrlController.text.trim(),
          capabilities: _selectedCapabilities,
          chipType: _selectedChipType,
          isActive: _isActive,
        );

        await management.updateDeviceType(updatedDeviceType);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device type updated'),
              backgroundColor: SaturdayColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        // Create new device type
        final newDeviceType = DeviceType(
          id: '', // Will be generated by repository
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          currentFirmwareVersion: _firmwareController.text.trim().isEmpty
              ? null
              : _firmwareController.text.trim(),
          specUrl: _specUrlController.text.trim().isEmpty
              ? null
              : _specUrlController.text.trim(),
          capabilities: _selectedCapabilities,
          chipType: _selectedChipType,
          isActive: _isActive,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await management.createDeviceType(newDeviceType);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device type created'),
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
            content: Text('Failed to save device type: $error'),
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
