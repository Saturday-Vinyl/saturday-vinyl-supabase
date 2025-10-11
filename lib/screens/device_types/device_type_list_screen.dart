import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device_type.dart';
import 'package:saturday_app/providers/device_type_provider.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/screens/device_types/device_type_form_screen.dart';
import 'package:saturday_app/screens/device_types/device_type_detail_screen.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';

/// Screen for listing and managing device types
class DeviceTypeListScreen extends ConsumerStatefulWidget {
  const DeviceTypeListScreen({super.key});

  @override
  ConsumerState<DeviceTypeListScreen> createState() =>
      _DeviceTypeListScreenState();
}

class _DeviceTypeListScreenState extends ConsumerState<DeviceTypeListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showInactiveOnly = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceTypesAsync = ref.watch(deviceTypesProvider);
    final canManage = ref.watch(currentUserProvider) != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Types'),
        actions: [
          if (canManage)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _navigateToForm(null),
              tooltip: 'Add Device Type',
            ),
        ],
      ),
      body: Column(
        children: [
          // Search and filter
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search device types...',
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
                Row(
                  children: [
                    Checkbox(
                      value: _showInactiveOnly,
                      onChanged: (value) {
                        setState(() {
                          _showInactiveOnly = value ?? false;
                        });
                      },
                    ),
                    const Text('Show inactive only'),
                  ],
                ),
              ],
            ),
          ),

          // Device types list
          Expanded(
            child: deviceTypesAsync.when(
              data: (deviceTypes) {
                // Apply filters
                var filteredDeviceTypes = deviceTypes;

                if (_searchQuery.isNotEmpty) {
                  filteredDeviceTypes = deviceTypes
                      .where((dt) =>
                          dt.name
                              .toLowerCase()
                              .contains(_searchQuery.toLowerCase()) ||
                          (dt.description?.toLowerCase() ?? '')
                              .contains(_searchQuery.toLowerCase()))
                      .toList();
                }

                if (_showInactiveOnly) {
                  filteredDeviceTypes =
                      filteredDeviceTypes.where((dt) => !dt.isActive).toList();
                }

                if (filteredDeviceTypes.isEmpty) {
                  return EmptyState(
                    icon: Icons.devices_other,
                    message: _searchQuery.isNotEmpty
                        ? 'No device types found matching "$_searchQuery"'
                        : 'No device types yet',
                    actionLabel: 'Add Device Type',
                    onAction: () => _navigateToForm(null),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(deviceTypesProvider);
                  },
                  child: ListView.builder(
                    itemCount: filteredDeviceTypes.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, index) {
                      final deviceType = filteredDeviceTypes[index];
                      return _DeviceTypeCard(
                        deviceType: deviceType,
                        onTap: () => _navigateToDetail(deviceType),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => ErrorState(
                message: 'Failed to load device types',
                details: error.toString(),
                onRetry: () => ref.invalidate(deviceTypesProvider),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToForm(DeviceType? deviceType) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceTypeFormScreen(deviceType: deviceType),
      ),
    );

    if (result == true && mounted) {
      ref.invalidate(deviceTypesProvider);
    }
  }

  void _navigateToDetail(DeviceType deviceType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DeviceTypeDetailScreen(deviceType: deviceType),
      ),
    );
  }
}

/// Card widget for displaying a device type
class _DeviceTypeCard extends StatelessWidget {
  final DeviceType deviceType;
  final VoidCallback onTap;

  const _DeviceTypeCard({
    required this.deviceType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                    child: Text(
                      deviceType.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: deviceType.isActive
                          ? SaturdayColors.success.withOpacity(0.1)
                          : SaturdayColors.secondaryGrey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      deviceType.status,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: deviceType.isActive
                                ? SaturdayColors.success
                                : SaturdayColors.secondaryGrey,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              if (deviceType.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  deviceType.description!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (deviceType.capabilities.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...deviceType.capabilities.take(3).map((capability) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: SaturdayColors.light,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          DeviceCapabilities.getDisplayName(capability),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    }),
                    if (deviceType.capabilities.length > 3)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Text(
                          '+${deviceType.capabilities.length - 3} more',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: SaturdayColors.secondaryGrey,
                              ),
                        ),
                      ),
                  ],
                ),
              ],
              if (deviceType.currentFirmwareVersion != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.memory,
                      size: 16,
                      color: SaturdayColors.secondaryGrey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Firmware: ${deviceType.currentFirmwareVersion}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
