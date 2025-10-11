import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/utils/validators.dart';
import 'package:saturday_app/widgets/common/app_button.dart';
import 'package:uuid/uuid.dart';

/// Screen for uploading firmware binary files
class FirmwareUploadScreen extends ConsumerStatefulWidget {
  const FirmwareUploadScreen({super.key});

  @override
  ConsumerState<FirmwareUploadScreen> createState() =>
      _FirmwareUploadScreenState();
}

class _FirmwareUploadScreenState extends ConsumerState<FirmwareUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _versionController = TextEditingController();
  final _releaseNotesController = TextEditingController();

  String? _selectedDeviceTypeId;
  File? _selectedFile;
  String? _selectedFileName;
  bool _isProductionReady = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  @override
  void dispose() {
    _versionController.dispose();
    _releaseNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceTypesAsync = ref.watch(activeDeviceTypesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Firmware'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Device Type dropdown
              deviceTypesAsync.when(
                data: (deviceTypes) {
                  if (deviceTypes.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            const Icon(
                              Icons.warning,
                              color: SaturdayColors.error,
                              size: 48,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'No active device types found',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Please create a device type before uploading firmware',
                              style: TextStyle(
                                color: SaturdayColors.secondaryGrey,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return DropdownButtonFormField<String>(
                    initialValue: _selectedDeviceTypeId,
                    decoration: const InputDecoration(
                      labelText: 'Device Type *',
                      hintText: 'Select the device type',
                    ),
                    items: deviceTypes.map((dt) {
                      return DropdownMenuItem<String>(
                        value: dt.id,
                        child: Text(dt.name),
                      );
                    }).toList(),
                    onChanged: _isUploading
                        ? null
                        : (value) {
                            setState(() {
                              _selectedDeviceTypeId = value;
                            });
                          },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please select a device type';
                      }
                      return null;
                    },
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (error, stack) => Card(
                  color: SaturdayColors.error.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Error loading device types: $error',
                      style: const TextStyle(color: SaturdayColors.error),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Version field
              TextFormField(
                controller: _versionController,
                enabled: !_isUploading,
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
                enabled: !_isUploading,
                decoration: const InputDecoration(
                  labelText: 'Release Notes',
                  hintText: 'What\'s new in this version?',
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 16),

              // File picker
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.insert_drive_file,
                            color: _selectedFile != null
                                ? SaturdayColors.success
                                : SaturdayColors.secondaryGrey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _selectedFileName ?? 'No file selected',
                              style: TextStyle(
                                color: _selectedFile != null
                                    ? Colors.black
                                    : SaturdayColors.secondaryGrey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        onPressed: _isUploading ? null : _pickFile,
                        text: 'Choose Binary File *',
                        style: AppButtonStyle.secondary,
                      ),
                      if (_selectedFile == null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Please select a firmware binary file',
                          style: TextStyle(
                            color: SaturdayColors.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Production ready checkbox
              CheckboxListTile(
                value: _isProductionReady,
                onChanged: _isUploading
                    ? null
                    : (value) {
                        setState(() {
                          _isProductionReady = value ?? false;
                        });
                      },
                title: const Text('Mark as Production Ready'),
                subtitle: const Text(
                  'Check this if the firmware is stable and ready for production deployment',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 24),

              // Upload progress
              if (_isUploading) ...[
                LinearProgressIndicator(value: _uploadProgress),
                const SizedBox(height: 8),
                Text(
                  'Uploading... ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: SaturdayColors.secondaryGrey),
                ),
                const SizedBox(height: 24),
              ],

              // Upload button
              AppButton(
                onPressed: _isUploading ? null : _upload,
                text: 'Upload Firmware',
                isLoading: _isUploading,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bin', 'hex', 'elf', 'uf2'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _selectedFileName = result.files.single.name;
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

  Future<void> _upload() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a firmware binary file'),
          backgroundColor: SaturdayColors.error,
        ),
      );
      return;
    }

    if (_selectedDeviceTypeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a device type'),
          backgroundColor: SaturdayColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final currentUserAsync = ref.read(currentUserProvider);
      final currentUser = currentUserAsync.value;
      final firmware = FirmwareVersion(
        id: const Uuid().v4(),
        deviceTypeId: _selectedDeviceTypeId!,
        version: _versionController.text.trim(),
        releaseNotes: _releaseNotesController.text.trim().isEmpty
            ? null
            : _releaseNotesController.text.trim(),
        binaryUrl: '', // Will be set by the upload
        binaryFilename: _selectedFileName!,
        isProductionReady: _isProductionReady,
        createdAt: DateTime.now(),
        createdBy: currentUser?.id,
      );

      // Simulate progress for better UX
      setState(() => _uploadProgress = 0.3);

      final management = ref.read(firmwareManagementProvider);
      await management.uploadFirmware(firmware, _selectedFile!);

      setState(() => _uploadProgress = 1.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firmware uploaded successfully'),
            backgroundColor: SaturdayColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload firmware: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }
}
