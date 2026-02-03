import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/models/product.dart';
import 'package:saturday_app/models/product_variant.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/providers/unit_provider.dart';
import 'package:saturday_app/services/file_launcher_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/firmware/firmware_selector.dart';

/// Screen for flashing firmware to devices during production
class FirmwareFlashScreen extends ConsumerStatefulWidget {
  final Unit unit;
  final String? stepId; // Optional production step ID to mark complete

  const FirmwareFlashScreen({
    super.key,
    required this.unit,
    this.stepId,
  });

  @override
  ConsumerState<FirmwareFlashScreen> createState() =>
      _FirmwareFlashScreenState();
}

class _FirmwareFlashScreenState extends ConsumerState<FirmwareFlashScreen> {
  final _notesController = TextEditingController();
  final _fileLauncher = FileLauncherService();

  // Map of deviceTypeId -> selected firmware ID
  final Map<String, String?> _selectedFirmware = {};

  // Map of deviceTypeId -> flashed confirmation
  final Map<String, bool> _flashedConfirmations = {};

  // Map of deviceTypeId -> recommended firmware ID
  final Map<String, String?> _recommendedFirmware = {};

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRecommendedFirmware();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRecommendedFirmware() async {
    try {
      final firmwareMap = await ref
          .read(unitRepositoryProvider)
          .getFirmwareForUnit(widget.unit.id);

      if (mounted) {
        setState(() {
          for (final entry in firmwareMap.entries) {
            _recommendedFirmware[entry.key] = entry.value.id;
            // Pre-select recommended firmware
            _selectedFirmware[entry.key] = entry.value.id;
            _flashedConfirmations[entry.key] = false;
          }
        });
      }
    } catch (e) {
      AppLogger.error('Failed to load recommended firmware', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load recommended firmware: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Future<void> _downloadAndLaunch(
      DeviceType deviceType, String firmwareId) async {
    try {
      setState(() => _isLoading = true);

      final repository = ref.read(unitRepositoryProvider);
      final firmwareMap = await repository.getFirmwareForUnit(widget.unit.id);
      final firmware = firmwareMap.values.firstWhere(
        (f) => f.id == firmwareId,
        orElse: () => throw Exception('Firmware not found'),
      );

      // Launch the firmware flashing tool
      final result = await _fileLauncher.launchFirmwareFlashTool(
        deviceType: deviceType,
        firmware: firmware,
      );

      if (mounted) {
        if (!result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? 'Failed to launch tool'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Failed to download and launch firmware', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to launch flashing tool: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmInstallations() async {
    try {
      setState(() => _isLoading = true);

      final user = await ref.read(currentUserProvider.future);
      final userId = user?.id;

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final repository = ref.read(unitRepositoryProvider);

      // Record each firmware installation
      // Only mark the step as complete after the last firmware installation
      final entries = _selectedFirmware.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final deviceTypeId = entry.key;
        final firmwareId = entry.value;
        final isLastEntry = i == entries.length - 1;

        if (firmwareId != null && _flashedConfirmations[deviceTypeId] == true) {
          await repository.recordFirmwareInstallation(
            unitId: widget.unit.id,
            deviceTypeId: deviceTypeId,
            firmwareVersionId: firmwareId,
            userId: userId,
            installationMethod: 'manual', // Could be enhanced to detect esptool
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            // Only pass stepId on the last firmware installation to mark step complete once
            stepId: isLastEntry ? widget.stepId : null,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Firmware installations recorded successfully'),
            backgroundColor: SaturdayColors.success,
          ),
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      AppLogger.error('Failed to confirm firmware installations', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm installations: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _allFlashed {
    if (_flashedConfirmations.isEmpty) return false;
    return _flashedConfirmations.values.every((confirmed) => confirmed);
  }

  @override
  Widget build(BuildContext context) {
    // Check if unit has product and variant assigned
    if (widget.unit.productId == null || widget.unit.variantId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Flash Firmware'),
        ),
        body: _buildErrorCard(context, 'Unit has no product or variant assigned'),
      );
    }

    // Get product and variant for this unit
    final productAsync = ref.watch(productProvider(widget.unit.productId!));
    final variantAsync = ref.watch(variantProvider(widget.unit.variantId!));
    final deviceTypesAsync = ref.watch(deviceTypesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flash Firmware'),
      ),
      body: productAsync.when(
        data: (product) {
          if (product == null) {
            return _buildErrorCard(context, 'Product not found');
          }
          return variantAsync.when(
            data: (variant) {
              if (variant == null) {
                return _buildErrorCard(context, 'Variant not found');
              }
              return deviceTypesAsync.when(
                data: (allDeviceTypes) {
                  // Get device types for this unit from the firmware recommendations
                  // that were loaded in initState
                  final deviceTypeIds = _recommendedFirmware.keys.toList();
                  final productDeviceTypes = deviceTypeIds
                      .map((id) => allDeviceTypes.firstWhere(
                            (dt) => dt.id == id,
                            orElse: () => throw Exception(
                                'Device type $id not found'),
                          ))
                      .toList();

                  if (productDeviceTypes.isEmpty) {
                    return _buildNoDeviceTypesCard(context);
                  }

                  return _buildContent(
                    context,
                    product,
                    variant,
                    productDeviceTypes,
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => _buildErrorCard(
                  context,
                  'Failed to load device types: $error',
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => _buildErrorCard(
              context,
              'Failed to load variant: $error',
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildErrorCard(
          context,
          'Failed to load product: $error',
        ),
      ),
    );
  }

  Widget _buildNoDeviceTypesCard(BuildContext context) {
    return Center(
      child: Card(
        color: SaturdayColors.secondaryGrey.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline,
                color: SaturdayColors.secondaryGrey,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'No device types configured for this product',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    return Center(
      child: Card(
        color: SaturdayColors.error.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            style: const TextStyle(color: SaturdayColors.error),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Product product,
    ProductVariant variant,
    List<DeviceType> deviceTypes,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unit information card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Production Unit',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('Serial Number', widget.unit.serialNumber ?? 'Unassigned'),
                  const SizedBox(height: 8),
                  _buildInfoRow('Product', product.name),
                  const SizedBox(height: 8),
                  _buildInfoRow('Variant', variant.name),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Instructions
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
                      'Select firmware version for each device, download and flash the firmware, then confirm installation.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: SaturdayColors.info,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Device types and firmware selection
          Text(
            'Device Firmware',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),

          ...deviceTypes.map((deviceType) {
            return _buildDeviceTypeCard(deviceType);
          }),

          const SizedBox(height: 24),

          // Notes field
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Installation Notes (Optional)',
              hintText:
                  'Any observations or issues during firmware flashing...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _allFlashed && !_isLoading ? _confirmInstallations : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: SaturdayColors.success,
                foregroundColor: Colors.white,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Confirm All Installations',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          if (!_allFlashed)
            Center(
              child: Text(
                'Please confirm all firmware installations before proceeding',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(
              color: SaturdayColors.secondaryGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceTypeCard(DeviceType deviceType) {
    final selectedFirmwareId = _selectedFirmware[deviceType.id];
    final isFlashed = _flashedConfirmations[deviceType.id] ?? false;
    final recommendedId = _recommendedFirmware[deviceType.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.memory,
                  color: SaturdayColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    deviceType.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Firmware selector
            FirmwareSelector(
              deviceTypeId: deviceType.id,
              selectedFirmwareId: selectedFirmwareId,
              recommendedFirmwareId: recommendedId,
              onChanged: (firmwareId) {
                setState(() {
                  _selectedFirmware[deviceType.id] = firmwareId;
                  // Reset confirmation when firmware changes
                  _flashedConfirmations[deviceType.id] = false;
                });
              },
            ),
            const SizedBox(height: 16),

            // Download and launch button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: selectedFirmwareId != null && !_isLoading
                    ? () => _downloadAndLaunch(deviceType, selectedFirmwareId)
                    : null,
                icon: const Icon(Icons.download),
                label: const Text('Download & Launch Flashing Tool'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Confirmation checkbox
            CheckboxListTile(
              value: isFlashed,
              onChanged: selectedFirmwareId != null
                  ? (value) {
                      setState(() {
                        _flashedConfirmations[deviceType.id] = value ?? false;
                      });
                    }
                  : null,
              title: const Text('Firmware flashed successfully'),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: SaturdayColors.success,
            ),
          ],
        ),
      ),
    );
  }
}
