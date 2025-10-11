import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
import 'package:saturday_app/utils/validators.dart';
import 'package:saturday_app/widgets/common/app_button.dart';

/// Screen for editing firmware version metadata
/// Note: Cannot change device type or binary file - must upload new version for that
class FirmwareEditScreen extends ConsumerStatefulWidget {
  final FirmwareVersion firmware;

  const FirmwareEditScreen({
    super.key,
    required this.firmware,
  });

  @override
  ConsumerState<FirmwareEditScreen> createState() =>
      _FirmwareEditScreenState();
}

class _FirmwareEditScreenState extends ConsumerState<FirmwareEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _versionController = TextEditingController();
  final _releaseNotesController = TextEditingController();

  bool _isProductionReady = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _versionController.text = widget.firmware.version;
    _releaseNotesController.text = widget.firmware.releaseNotes ?? '';
    _isProductionReady = widget.firmware.isProductionReady;
  }

  @override
  void dispose() {
    _versionController.dispose();
    _releaseNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Firmware'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info card about what can't be edited
              Card(
                color: SaturdayColors.info.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: SaturdayColors.info,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Device type and binary file cannot be changed. Upload a new version to change these.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: SaturdayColors.primaryDark,
                              ),
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
                  hintText: 'What\'s new in this version?',
                  alignLabelWithHint: true,
                ),
                maxLines: 6,
              ),
              const SizedBox(height: 16),

              // Production ready checkbox
              CheckboxListTile(
                value: _isProductionReady,
                onChanged: _isSaving
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

              // Read-only fields section
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Read-Only Information',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),
              const SizedBox(height: 16),

              _ReadOnlyField(
                label: 'Device Type ID',
                value: widget.firmware.deviceTypeId,
              ),
              const SizedBox(height: 12),
              _ReadOnlyField(
                label: 'Binary Filename',
                value: widget.firmware.binaryFilename,
              ),
              const SizedBox(height: 12),
              _ReadOnlyField(
                label: 'Upload Date',
                value: _formatDate(widget.firmware.createdAt),
              ),
              const SizedBox(height: 32),

              // Save button
              AppButton(
                onPressed: _isSaving ? null : _save,
                text: 'Save Changes',
                isLoading: _isSaving,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final updatedFirmware = widget.firmware.copyWith(
        version: _versionController.text.trim(),
        releaseNotes: _releaseNotesController.text.trim().isEmpty
            ? null
            : _releaseNotesController.text.trim(),
        isProductionReady: _isProductionReady,
      );

      final management = ref.read(firmwareManagementProvider);
      await management.updateFirmware(updatedFirmware);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firmware updated successfully'),
            backgroundColor: SaturdayColors.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update firmware: $error'),
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

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Widget for displaying read-only field information
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadOnlyField({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
      ],
    );
  }
}
