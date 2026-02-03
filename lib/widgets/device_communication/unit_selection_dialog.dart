import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/providers/unit_provider.dart';

/// Dialog for selecting a unit to provision a device against.
///
/// Features:
/// - Auto-filters by device type (units whose products use this device type)
/// - Shows warning when a unit already has this device type provisioned
/// - Supports search by serial number
class UnitSelectionDialog extends ConsumerStatefulWidget {
  /// The device type slug from the connected device (e.g., "hub-prototype")
  final String deviceTypeSlug;

  /// Human-readable device type name for display
  final String deviceTypeName;

  const UnitSelectionDialog({
    super.key,
    required this.deviceTypeSlug,
    required this.deviceTypeName,
  });

  /// Show the dialog and return the selected unit, or null if cancelled
  static Future<Unit?> show({
    required BuildContext context,
    required String deviceTypeSlug,
    required String deviceTypeName,
  }) {
    return showDialog<Unit?>(
      context: context,
      builder: (context) => UnitSelectionDialog(
        deviceTypeSlug: deviceTypeSlug,
        deviceTypeName: deviceTypeName,
      ),
    );
  }

  @override
  ConsumerState<UnitSelectionDialog> createState() =>
      _UnitSelectionDialogState();
}

class _UnitSelectionDialogState extends ConsumerState<UnitSelectionDialog> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  List<Unit> _units = [];
  Map<String, bool> _unitsWithDeviceType = {};
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadUnits();
    // Auto-focus search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUnits({String? searchQuery}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(unitRepositoryProvider);

      // Search for units that match the device type
      final units = await repository.searchUnitsByDeviceType(
        deviceTypeSlug: widget.deviceTypeSlug,
        searchQuery: searchQuery,
      );

      // Check which units already have this device type provisioned
      final unitIds = units.map((u) => u.id).toList();
      final deviceTypeStatus = await repository.getUnitsDeviceTypeStatus(
        unitIds: unitIds,
        deviceTypeSlug: widget.deviceTypeSlug,
      );

      if (mounted) {
        setState(() {
          _units = units;
          _unitsWithDeviceType = deviceTypeStatus;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load units: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _loadUnits(searchQuery: value.isEmpty ? null : value);
    });
  }

  void _selectUnit(Unit unit) {
    Navigator.of(context).pop(unit);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 24,
                  color: SaturdayColors.primaryDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Unit',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        'Choose a unit to provision this ${widget.deviceTypeName}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cancel',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Device type filter indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: SaturdayColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: SaturdayColors.info.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt_outlined,
                    size: 16,
                    color: SaturdayColors.info,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing units for products that use "${widget.deviceTypeName}"',
                      style: const TextStyle(
                        fontSize: 12,
                        color: SaturdayColors.info,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Search field
            TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search by serial number...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onChanged: _onSearchChanged,
            ),

            const SizedBox(height: 16),

            // Unit list
            Expanded(
              child: _buildUnitList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: SaturdayColors.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: SaturdayColors.error),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadUnits(
                  searchQuery: _searchController.text.isEmpty
                      ? null
                      : _searchController.text),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_units.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchController.text.isNotEmpty
                  ? 'No units found matching "${_searchController.text}"'
                  : 'No units available for this device type',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Units must be created with a product that uses this device type.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _units.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final unit = _units[index];
        final hasDeviceType = _unitsWithDeviceType[unit.id] ?? false;

        return _UnitListTile(
          unit: unit,
          hasDeviceType: hasDeviceType,
          deviceTypeName: widget.deviceTypeName,
          onTap: () => _selectUnit(unit),
        );
      },
    );
  }
}

class _UnitListTile extends StatelessWidget {
  final Unit unit;
  final bool hasDeviceType;
  final String deviceTypeName;
  final VoidCallback onTap;

  const _UnitListTile({
    required this.unit,
    required this.hasDeviceType,
    required this.deviceTypeName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            // Status icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _getStatusColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getStatusIcon(),
                size: 20,
                color: _getStatusColor(),
              ),
            ),
            const SizedBox(width: 12),

            // Unit info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        unit.serialNumber ?? 'No Serial',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStatusBadge(),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getStatusDescription(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),

            // Warning icon if already provisioned
            if (hasDeviceType) ...[
              Tooltip(
                message:
                    'This unit already has a $deviceTypeName.\nProvisioning again will replace it.',
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: SaturdayColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: SaturdayColors.warning,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],

            // Select chevron
            Icon(
              Icons.chevron_right,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor() {
    switch (unit.status) {
      case UnitStatus.unprovisioned:
        return SaturdayColors.info;
      case UnitStatus.factoryProvisioned:
        return SaturdayColors.success;
      case UnitStatus.userProvisioned:
        return SaturdayColors.primaryDark;
    }
  }

  IconData _getStatusIcon() {
    switch (unit.status) {
      case UnitStatus.unprovisioned:
        return Icons.new_releases_outlined;
      case UnitStatus.factoryProvisioned:
        return Icons.check_circle_outline;
      case UnitStatus.userProvisioned:
        return Icons.person_outline;
    }
  }

  Widget _buildStatusBadge() {
    final color = _getStatusColor();
    final label = _getStatusLabel();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _getStatusLabel() {
    switch (unit.status) {
      case UnitStatus.unprovisioned:
        return 'NEW';
      case UnitStatus.factoryProvisioned:
        return 'FACTORY';
      case UnitStatus.userProvisioned:
        return 'USER';
    }
  }

  String _getStatusDescription() {
    if (hasDeviceType) {
      return 'Already has $deviceTypeName provisioned';
    }
    switch (unit.status) {
      case UnitStatus.unprovisioned:
        return 'Ready for provisioning';
      case UnitStatus.factoryProvisioned:
        return 'Factory provisioned';
      case UnitStatus.userProvisioned:
        return 'Owned by consumer';
    }
  }
}
