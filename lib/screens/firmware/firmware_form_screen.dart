import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/models/firmware.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
import 'package:saturday_app/repositories/firmware_repository.dart';
import 'package:saturday_app/utils/validators.dart';
import 'package:saturday_app/widgets/common/app_button.dart';

/// Screen for creating or editing firmware versions with multi-SoC file support
class FirmwareFormScreen extends ConsumerStatefulWidget {
  /// Device type ID for new firmware, or null if editing existing
  final String? deviceTypeId;

  /// Existing firmware to edit, or null if creating new
  final Firmware? firmware;

  const FirmwareFormScreen({
    super.key,
    this.deviceTypeId,
    this.firmware,
  }) : assert(deviceTypeId != null || firmware != null);

  @override
  ConsumerState<FirmwareFormScreen> createState() => _FirmwareFormScreenState();
}

class _FirmwareFormScreenState extends ConsumerState<FirmwareFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _versionController = TextEditingController();
  final _releaseNotesController = TextEditingController();

  bool _isCritical = false;
  bool _isSaving = false;
  String? _masterSoc;

  // Map of SoC type -> selected file
  final Map<String, File> _selectedFiles = {};

  // Existing files from firmware (for edit mode)
  List<FirmwareFile> _existingFiles = [];

  bool get isEditing => widget.firmware != null;

  String get effectiveDeviceTypeId =>
      widget.firmware?.deviceTypeId ?? widget.deviceTypeId!;

  @override
  void initState() {
    super.initState();
    if (widget.firmware != null) {
      _versionController.text = widget.firmware!.version;
      _releaseNotesController.text = widget.firmware!.releaseNotes ?? '';
      _isCritical = widget.firmware!.isCritical;
      _existingFiles = widget.firmware!.files;
      _masterSoc = widget.firmware!.masterFile?.socType;
    }
  }

  @override
  void dispose() {
    _versionController.dispose();
    _releaseNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceTypeAsync = ref.watch(deviceTypeProvider(effectiveDeviceTypeId));

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Firmware' : 'New Firmware'),
      ),
      body: deviceTypeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (deviceType) {
          if (deviceType == null) {
            return const Center(child: Text('Device type not found'));
          }
          return _buildForm(deviceType);
        },
      ),
    );
  }

  Widget _buildForm(DeviceType deviceType) {
    final socTypes = deviceType.effectiveSocTypes;

    // Initialize master SoC if not set
    if (_masterSoc == null && socTypes.isNotEmpty) {
      _masterSoc = deviceType.effectiveMasterSoc ?? socTypes.first;
    }

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device type info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.developer_board),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deviceType.name,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (socTypes.isNotEmpty)
                            Text(
                              'SoCs: ${socTypes.map((s) => s.toUpperCase()).join(', ')}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Version field
            TextFormField(
              controller: _versionController,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: 'Version *',
                hintText: 'e.g., 1.2.3',
                helperText: 'Semantic versioning (X.Y.Z)',
              ),
              validator: Validators.validateSemanticVersion,
            ),
            const SizedBox(height: 16),

            // Release Notes field
            TextFormField(
              controller: _releaseNotesController,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: 'Release Notes',
                hintText: "What's new in this version?",
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 16),

            // Critical update checkbox
            CheckboxListTile(
              value: _isCritical,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _isCritical = value ?? false;
                      });
                    },
              title: const Text('Critical Update'),
              subtitle: const Text(
                'Critical updates are prioritized and may force immediate installation',
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 24),

            // Firmware files section
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Firmware Files',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Upload binary files for each SoC. The master file is pushed via OTA.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
            ),
            const SizedBox(height: 16),

            // File upload cards for each SoC
            ...socTypes.map((socType) => _buildSocFileCard(socType)),

            if (socTypes.isEmpty)
              Card(
                color: SaturdayColors.info.withValues(alpha: 0.1),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No SoC types configured for this device type. '
                    'Please configure SoC types on the device type first.',
                  ),
                ),
              ),

            const SizedBox(height: 32),

            // Save button
            AppButton(
              onPressed: _isSaving ? null : _save,
              text: isEditing ? 'Save Changes' : 'Create Firmware',
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocFileCard(String socType) {
    final existingFile = _existingFiles
        .where((f) => f.socType == socType)
        .firstOrNull;
    final selectedFile = _selectedFiles[socType];
    final isMaster = _masterSoc == socType;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isMaster ? Icons.star : Icons.memory,
                  color: isMaster ? Colors.orange : SaturdayColors.secondaryGrey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        socType.toUpperCase(),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (isMaster)
                        Text(
                          'Master (pushed via OTA)',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                // Master toggle
                TextButton(
                  onPressed: _isSaving
                      ? null
                      : () {
                          setState(() {
                            _masterSoc = socType;
                          });
                        },
                  child: Text(isMaster ? 'MASTER' : 'Set as Master'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // File status
            if (selectedFile != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: SaturdayColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedFile.path.split('/').last,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '${(selectedFile.lengthSync() / 1024).toStringAsFixed(1)} KB',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _selectedFiles.remove(socType);
                        });
                      },
                    ),
                  ],
                ),
              ),
            ] else if (existingFile != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_done, color: SaturdayColors.secondaryGrey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            existingFile.filename,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            existingFile.formattedSize,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _isSaving ? null : () => _pickFile(socType),
                      child: const Text('Replace'),
                    ),
                  ],
                ),
              ),
            ] else ...[
              OutlinedButton.icon(
                onPressed: _isSaving ? null : () => _pickFile(socType),
                icon: const Icon(Icons.upload_file),
                label: const Text('Select Binary File'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile(String socType) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFiles[socType] = File(result.files.single.path!);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate at least one file
    final hasFiles = _selectedFiles.isNotEmpty || _existingFiles.isNotEmpty;
    if (!hasFiles && !isEditing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload at least one firmware file'),
          backgroundColor: SaturdayColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final management = ref.read(firmwareManagementProvider);

      if (isEditing) {
        // Update existing firmware metadata
        final updated = widget.firmware!.copyWith(
          version: _versionController.text.trim(),
          releaseNotes: _releaseNotesController.text.trim().isEmpty
              ? null
              : _releaseNotesController.text.trim(),
          isCritical: _isCritical,
        );

        // TODO: Support updating firmware metadata via new Firmware model
        // For now, create a FirmwareVersion from it for backwards compatibility
        await management.updateFirmware(
          updated.toFirmwareVersion(),
        );

        // Upload any new files
        for (final entry in _selectedFiles.entries) {
          await management.addFirmwareFile(
            firmwareId: widget.firmware!.id,
            socType: entry.key,
            isMaster: _masterSoc == entry.key,
            file: entry.value,
          );
        }
      } else {
        // Create new firmware
        final firmware = Firmware(
          id: '', // Will be generated by database
          deviceTypeId: effectiveDeviceTypeId,
          version: _versionController.text.trim(),
          releaseNotes: _releaseNotesController.text.trim().isEmpty
              ? null
              : _releaseNotesController.text.trim(),
          isCritical: _isCritical,
          createdAt: DateTime.now(),
        );

        // Prepare file uploads
        final fileUploads = _selectedFiles.entries.map((entry) {
          return FirmwareFileUpload(
            socType: entry.key,
            isMaster: _masterSoc == entry.key,
            file: entry.value,
          );
        }).toList();

        await management.createFirmwareWithFiles(firmware, fileUploads);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing
                ? 'Firmware updated successfully'
                : 'Firmware created successfully'),
            backgroundColor: SaturdayColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save firmware: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

/// Extension to convert new Firmware to old FirmwareVersion for compatibility
extension FirmwareToVersion on Firmware {
  FirmwareVersion toFirmwareVersion() {
    return FirmwareVersion(
      id: id,
      deviceTypeId: deviceTypeId,
      version: version,
      releaseNotes: releaseNotes,
      binaryUrl: binaryUrl ?? '',
      binaryFilename: binaryFilename ?? '',
      binarySize: binarySize,
      isProductionReady: isProductionReady,
      createdAt: createdAt,
      createdBy: createdBy,
    );
  }
}

