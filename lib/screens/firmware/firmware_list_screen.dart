import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/firmware_version.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/providers/firmware_provider.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/screens/firmware/firmware_upload_screen.dart';
import 'package:saturday_app/screens/firmware/firmware_detail_screen.dart';
import 'package:saturday_app/services/storage_service.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/utils/validators.dart';

/// Screen for listing and managing firmware versions
class FirmwareListScreen extends ConsumerStatefulWidget {
  const FirmwareListScreen({super.key});

  @override
  ConsumerState<FirmwareListScreen> createState() =>
      _FirmwareListScreenState();
}

class _FirmwareListScreenState extends ConsumerState<FirmwareListScreen> {
  String? _selectedDeviceTypeId;
  bool _showProductionOnly = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceTypesAsync = ref.watch(deviceTypesProvider);
    final firmwareAsync = _selectedDeviceTypeId != null
        ? ref.watch(firmwareVersionsByDeviceTypeProvider(_selectedDeviceTypeId!))
        : ref.watch(firmwareVersionsProvider);
    final canManage = ref.watch(currentUserProvider).value != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Firmware Management'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _navigateToUpload(),
              tooltip: 'Upload Firmware',
            ),
        ],
      ),
      body: Column(
        children: [
          // Filters section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Device type filter
                deviceTypesAsync.when(
                  data: (deviceTypes) {
                    return DropdownButtonFormField<String?>(
                      initialValue: _selectedDeviceTypeId,
                      decoration: InputDecoration(
                        labelText: 'Filter by Device Type',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Device Types'),
                        ),
                        ...deviceTypes.map((dt) => DropdownMenuItem<String>(
                              value: dt.id,
                              child: Text(dt.name),
                            )),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedDeviceTypeId = value;
                        });
                      },
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stack) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),

                // Search field
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by version...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                const SizedBox(height: 8),

                // Production only checkbox
                Row(
                  children: [
                    Checkbox(
                      value: _showProductionOnly,
                      onChanged: (value) {
                        setState(() {
                          _showProductionOnly = value ?? false;
                        });
                      },
                    ),
                    const Text('Show production ready only'),
                  ],
                ),
              ],
            ),
          ),

          // Firmware list
          Expanded(
            child: firmwareAsync.when(
              data: (firmwareVersions) {
                // Apply filters
                var filtered = firmwareVersions;

                if (_searchQuery.isNotEmpty) {
                  filtered = filtered
                      .where((fw) => fw.version
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase()))
                      .toList();
                }

                if (_showProductionOnly) {
                  filtered =
                      filtered.where((fw) => fw.isProductionReady).toList();
                }

                // Sort by version (semantic versioning)
                filtered.sort((a, b) =>
                    Validators.compareSemanticVersions(b.version, a.version));

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: Icons.memory,
                    message: _searchQuery.isNotEmpty
                        ? 'No firmware versions found matching "$_searchQuery"'
                        : 'No firmware versions yet',
                    actionLabel: canManage ? 'Upload Firmware' : null,
                    onAction: canManage ? () => _navigateToUpload() : null,
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(firmwareVersionsProvider);
                    if (_selectedDeviceTypeId != null) {
                      ref.invalidate(firmwareVersionsByDeviceTypeProvider(
                          _selectedDeviceTypeId!));
                    }
                  },
                  child: ListView.builder(
                    itemCount: filtered.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final firmware = filtered[index];
                      return _FirmwareCard(
                        firmware: firmware,
                        deviceTypesAsync: deviceTypesAsync,
                        canManage: canManage,
                        onTap: () => _navigateToDetail(firmware),
                        onDelete: () => _deleteFirmware(firmware),
                        onToggleProduction: () =>
                            _toggleProduction(firmware),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => ErrorState(
                message: 'Failed to load firmware versions',
                details: error.toString(),
                onRetry: () {
                  ref.invalidate(firmwareVersionsProvider);
                  if (_selectedDeviceTypeId != null) {
                    ref.invalidate(firmwareVersionsByDeviceTypeProvider(
                        _selectedDeviceTypeId!));
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToUpload() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const FirmwareUploadScreen(),
      ),
    );

    if (result == true && mounted) {
      ref.invalidate(firmwareVersionsProvider);
      if (_selectedDeviceTypeId != null) {
        ref.invalidate(
            firmwareVersionsByDeviceTypeProvider(_selectedDeviceTypeId!));
      }
    }
  }

  void _navigateToDetail(FirmwareVersion firmware) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FirmwareDetailScreen(firmware: firmware),
      ),
    );

    // Refresh list when returning in case changes were made
    if (mounted) {
      ref.invalidate(firmwareVersionsProvider);
      if (_selectedDeviceTypeId != null) {
        ref.invalidate(
            firmwareVersionsByDeviceTypeProvider(_selectedDeviceTypeId!));
      }
    }
  }

  void _deleteFirmware(FirmwareVersion firmware) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Firmware'),
        content: Text(
          'Are you sure you want to delete firmware version ${firmware.version}?\n\n'
          'This will also delete the binary file from storage and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: SaturdayColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final management = ref.read(firmwareManagementProvider);
      await management.deleteFirmware(firmware.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Firmware deleted successfully')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete firmware: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  void _toggleProduction(FirmwareVersion firmware) async {
    final newStatus = !firmware.isProductionReady;
    final action = newStatus ? 'mark as production ready' : 'remove from production';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${newStatus ? 'Enable' : 'Disable'} Production Status'),
        content: Text(
          'Are you sure you want to $action firmware version ${firmware.version}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final management = ref.read(firmwareManagementProvider);
      await management.toggleProductionReady(firmware.id, newStatus);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Firmware ${newStatus ? 'marked as production ready' : 'removed from production'}',
            ),
          ),
        );
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
    }
  }
}

/// Card widget for displaying a firmware version
class _FirmwareCard extends ConsumerWidget {
  final FirmwareVersion firmware;
  final AsyncValue<List<DeviceType>> deviceTypesAsync;
  final bool canManage;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleProduction;

  const _FirmwareCard({
    required this.firmware,
    required this.deviceTypesAsync,
    required this.canManage,
    required this.onTap,
    required this.onDelete,
    required this.onToggleProduction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceTypeName = deviceTypesAsync.maybeWhen(
      data: (types) {
        final deviceType = types.firstWhere(
          (dt) => dt.id == firmware.deviceTypeId,
          orElse: () => DeviceType(
            id: firmware.deviceTypeId,
            name: 'Unknown',
            isActive: false,
            capabilities: const [],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        return deviceType.name;
      },
      orElse: () => 'Loading...',
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'v${firmware.version}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: firmware.isProductionReady
                                  ? SaturdayColors.success.withOpacity(0.1)
                                  : SaturdayColors.secondaryGrey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              firmware.isProductionReady ? 'Production' : 'Development',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: firmware.isProductionReady
                                        ? SaturdayColors.success
                                        : SaturdayColors.secondaryGrey,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        deviceTypeName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'toggle_production') {
                        onToggleProduction();
                      } else if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'toggle_production',
                        child: Row(
                          children: [
                            Icon(
                              firmware.isProductionReady
                                  ? Icons.remove_circle_outline
                                  : Icons.check_circle_outline,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              firmware.isProductionReady
                                  ? 'Remove from Production'
                                  : 'Mark as Production',
                            ),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: SaturdayColors.error),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: SaturdayColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (firmware.releaseNotes != null) ...[
              const SizedBox(height: 12),
              Text(
                firmware.releaseNotes!,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.insert_drive_file,
                      size: 16,
                      color: SaturdayColors.secondaryGrey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      firmware.binaryFilename,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ],
                ),
                if (firmware.binarySize != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.data_usage,
                        size: 16,
                        color: SaturdayColors.secondaryGrey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        StorageService.formatFileSize(firmware.binarySize!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                      ),
                    ],
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: SaturdayColors.secondaryGrey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(firmware.createdAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
        ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
