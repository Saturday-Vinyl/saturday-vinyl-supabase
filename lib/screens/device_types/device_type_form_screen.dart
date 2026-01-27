import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/capability.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/models/firmware.dart';
import 'package:saturday_app/providers/capability_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
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
  final _slugController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _specUrlController = TextEditingController();

  // Track if user has manually edited the slug
  bool _slugManuallyEdited = false;

  // Dynamic capabilities (loaded from database)
  Set<String> _selectedCapabilityIds = {};

  // Multi-SoC support
  List<String> _selectedSocTypes = [];
  String? _masterSoc;

  // Firmware versions
  String? _productionFirmwareId;
  String? _devFirmwareId;

  bool _isActive = true;
  bool _isLoading = false;
  bool _isLoadingCapabilities = true;

  // Available ESP32 chip types for SoC selection
  static const List<String> _availableSocTypes = [
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
    _initializeForm();
  }

  Future<void> _initializeForm() async {
    // Set up name listener to auto-generate slug
    _nameController.addListener(_onNameChanged);

    if (widget.deviceType != null) {
      _nameController.text = widget.deviceType!.name;
      _slugController.text = widget.deviceType!.slug;
      _slugManuallyEdited = true; // Don't auto-update existing slugs
      _descriptionController.text = widget.deviceType!.description ?? '';
      _specUrlController.text = widget.deviceType!.specUrl ?? '';
      _selectedSocTypes = List.from(widget.deviceType!.effectiveSocTypes);
      _masterSoc = widget.deviceType!.effectiveMasterSoc;
      _productionFirmwareId = widget.deviceType!.productionFirmwareId;
      _devFirmwareId = widget.deviceType!.devFirmwareId;
      _isActive = widget.deviceType!.isActive;

      // Load existing capability associations
      try {
        final capabilities = await ref
            .read(capabilityRepositoryProvider)
            .getCapabilitiesForDeviceType(widget.deviceType!.id);
        setState(() {
          _selectedCapabilityIds = capabilities.map((c) => c.id).toSet();
          _isLoadingCapabilities = false;
        });
      } catch (e) {
        setState(() {
          _isLoadingCapabilities = false;
        });
      }
    } else {
      setState(() {
        _isLoadingCapabilities = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _slugController.dispose();
    _descriptionController.dispose();
    _specUrlController.dispose();
    super.dispose();
  }

  /// Convert name to slug format (kebab-case, lowercase, alphanumeric only)
  String _generateSlug(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Auto-update slug when name changes (unless manually edited)
  void _onNameChanged() {
    if (!_slugManuallyEdited) {
      final newSlug = _generateSlug(_nameController.text);
      if (_slugController.text != newSlug) {
        _slugController.text = newSlug;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.deviceType != null;
    final activeCapabilities = ref.watch(activeCapabilitiesProvider);

    // Load firmware versions for this device type (if editing)
    final firmwareVersions = isEditing
        ? ref.watch(firmwareByDeviceTypeProvider(widget.deviceType!.id))
        : const AsyncValue<List<Firmware>>.data([]);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Device Type' : 'Add Device Type'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Basic Information Section
              _buildSectionHeader('Basic Information'),
              const SizedBox(height: 16),

              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name *',
                  hintText: 'e.g., Saturday Crate Board',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Slug field
              TextFormField(
                controller: _slugController,
                decoration: InputDecoration(
                  labelText: 'Slug *',
                  hintText: 'e.g., saturday-crate-board',
                  helperText: 'URL-safe identifier used in firmware schemas',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Regenerate from name',
                    onPressed: () {
                      setState(() {
                        _slugManuallyEdited = false;
                        _slugController.text =
                            _generateSlug(_nameController.text);
                      });
                    },
                  ),
                ),
                onChanged: (value) {
                  // Mark as manually edited if user types
                  _slugManuallyEdited = true;
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a slug';
                  }
                  if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(value)) {
                    return 'Slug must be lowercase with hyphens only (e.g., my-device)';
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

              // Spec URL field
              TextFormField(
                controller: _specUrlController,
                decoration: const InputDecoration(
                  labelText: 'Specification URL',
                  hintText: 'Link to datasheet or docs',
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 24),

              // SoC Types Section
              _buildSectionHeader('SoC Configuration'),
              const SizedBox(height: 8),
              Text(
                'Select all SoC types on this PCB. Multi-SoC boards (e.g., S3 + H2) have multiple selections.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableSocTypes.map((socType) {
                  final isSelected = _selectedSocTypes.contains(socType);
                  return FilterChip(
                    label: Text(socType.toUpperCase()),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedSocTypes.add(socType);
                          // Auto-select as master if it's the first one
                          _masterSoc ??= socType;
                        } else {
                          _selectedSocTypes.remove(socType);
                          // Clear master if it was this one
                          if (_masterSoc == socType) {
                            _masterSoc = _selectedSocTypes.isNotEmpty
                                ? _selectedSocTypes.first
                                : null;
                          }
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Master SoC dropdown (only if multiple SoCs selected)
              if (_selectedSocTypes.length > 1) ...[
                DropdownButtonFormField<String>(
                  value: _masterSoc,
                  decoration: const InputDecoration(
                    labelText: 'Master SoC',
                    hintText: 'SoC with network connectivity',
                    prefixIcon: Icon(Icons.wifi),
                  ),
                  items: _selectedSocTypes
                      .map((soc) => DropdownMenuItem<String>(
                            value: soc,
                            child: Text(soc.toUpperCase()),
                          ))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _masterSoc = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'The master SoC handles OTA updates and pulls firmware for secondary SoCs',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                ),
              ],
              const SizedBox(height: 24),

              // Capabilities Section (Dynamic from database)
              _buildSectionHeader('Capabilities'),
              const SizedBox(height: 8),
              Text(
                'Select capabilities this device type supports',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 12),
              _buildCapabilitiesSection(activeCapabilities),
              const SizedBox(height: 24),

              // Firmware Section (only for editing)
              if (isEditing) ...[
                _buildSectionHeader('Firmware Versions'),
                const SizedBox(height: 8),
                Text(
                  'Assign firmware versions for this device type',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                ),
                const SizedBox(height: 12),
                _buildFirmwareSection(firmwareVersions),
                const SizedBox(height: 24),
              ],

              // Active status
              SwitchListTile(
                title: const Text('Active'),
                subtitle:
                    const Text('Inactive device types won\'t appear in lists'),
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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }

  Widget _buildCapabilitiesSection(
      AsyncValue<List<Capability>> capabilitiesAsync) {
    if (_isLoadingCapabilities) {
      return const Center(child: CircularProgressIndicator());
    }

    return capabilitiesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text(
        'Error loading capabilities: $error',
        style: TextStyle(color: SaturdayColors.error),
      ),
      data: (capabilities) {
        if (capabilities.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, color: SaturdayColors.secondaryGrey),
                const SizedBox(width: 8),
                const Text('No capabilities defined yet'),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/capabilities');
                  },
                  child: const Text('Create Capabilities'),
                ),
              ],
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: capabilities.map((capability) {
            final isSelected = _selectedCapabilityIds.contains(capability.id);
            return FilterChip(
              avatar: isSelected
                  ? null
                  : Icon(Icons.extension, size: 18, color: SaturdayColors.info),
              label: Text(capability.displayName),
              selected: isSelected,
              selectedColor: SaturdayColors.info.withValues(alpha: 0.2),
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedCapabilityIds.add(capability.id);
                  } else {
                    _selectedCapabilityIds.remove(capability.id);
                  }
                });
              },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildFirmwareSection(AsyncValue<List<Firmware>> firmwareAsync) {
    return firmwareAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Text(
        'Error loading firmware: $error',
        style: TextStyle(color: SaturdayColors.error),
      ),
      data: (firmwareList) {
        final releasedFirmware =
            firmwareList.where((f) => f.releasedAt != null).toList();
        final devFirmware =
            firmwareList.where((f) => f.releasedAt == null).toList();

        return Column(
          children: [
            // Production Firmware
            DropdownButtonFormField<String>(
              value: _productionFirmwareId,
              decoration: const InputDecoration(
                labelText: 'Production Firmware',
                hintText: 'Select released firmware version',
                prefixIcon: Icon(Icons.verified),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('-- None --'),
                ),
                ...releasedFirmware.map((fw) => DropdownMenuItem<String>(
                      value: fw.id,
                      child: Row(
                        children: [
                          Text(fw.version),
                          if (fw.isCritical)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: SaturdayColors.error,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'CRITICAL',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                    )),
              ],
              onChanged: (value) {
                setState(() {
                  _productionFirmwareId = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // Dev Firmware
            DropdownButtonFormField<String>(
              value: _devFirmwareId,
              decoration: const InputDecoration(
                labelText: 'Development Firmware',
                hintText: 'Select development firmware version',
                prefixIcon: Icon(Icons.developer_mode),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('-- None --'),
                ),
                ...devFirmware.map((fw) => DropdownMenuItem<String>(
                      value: fw.id,
                      child: Text('${fw.version} (dev)'),
                    )),
                // Also allow released firmware as dev
                ...releasedFirmware.map((fw) => DropdownMenuItem<String>(
                      value: fw.id,
                      child: Text(fw.version),
                    )),
              ],
              onChanged: (value) {
                setState(() {
                  _devFirmwareId = value;
                });
              },
            ),

            if (firmwareList.isEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: SaturdayColors.info),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                          'No firmware versions yet. Upload firmware in the Firmware section.'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
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
      final capabilityManagement = ref.read(capabilityManagementProvider);

      if (widget.deviceType != null) {
        // Update existing device type
        final updatedDeviceType = widget.deviceType!.copyWith(
          name: _nameController.text.trim(),
          slug: _slugController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          specUrl: _specUrlController.text.trim().isEmpty
              ? null
              : _specUrlController.text.trim(),
          socTypes: _selectedSocTypes,
          masterSoc: _masterSoc,
          chipType: _selectedSocTypes.isNotEmpty
              ? _selectedSocTypes.first
              : null, // Legacy compat
          productionFirmwareId: _productionFirmwareId,
          devFirmwareId: _devFirmwareId,
          isActive: _isActive,
          // Keep legacy capabilities field in sync for backwards compat
          capabilities: [], // Cleared - now using junction table
        );

        await management.updateDeviceType(updatedDeviceType);

        // Update capability associations via junction table
        await capabilityManagement.setCapabilitiesForDeviceType(
          deviceTypeId: widget.deviceType!.id,
          capabilityIds: _selectedCapabilityIds.toList(),
        );

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
          slug: _slugController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          specUrl: _specUrlController.text.trim().isEmpty
              ? null
              : _specUrlController.text.trim(),
          socTypes: _selectedSocTypes,
          masterSoc: _masterSoc,
          chipType: _selectedSocTypes.isNotEmpty
              ? _selectedSocTypes.first
              : null, // Legacy compat
          productionFirmwareId: _productionFirmwareId,
          devFirmwareId: _devFirmwareId,
          capabilities: [], // Using junction table instead
          isActive: _isActive,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final created = await management.createDeviceType(newDeviceType);

        // Set capability associations for new device type
        if (_selectedCapabilityIds.isNotEmpty) {
          await capabilityManagement.setCapabilitiesForDeviceType(
            deviceTypeId: created.id,
            capabilityIds: _selectedCapabilityIds.toList(),
          );
        }

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
