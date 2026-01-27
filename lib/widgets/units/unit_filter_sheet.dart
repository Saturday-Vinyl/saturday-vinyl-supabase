import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/models/unit_filter.dart';
import 'package:saturday_app/providers/unit_dashboard_provider.dart';

/// Bottom sheet for filtering and sorting units
class UnitFilterSheet extends ConsumerWidget {
  const UnitFilterSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(unitFilterProvider);
    final notifier = ref.read(unitFilterProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Row(
                children: [
                  const Text(
                    'Filter & Sort',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (filter.hasActiveFilters)
                    TextButton(
                      onPressed: () {
                        notifier.reset();
                      },
                      child: const Text('Reset'),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // Status filter
              _buildSectionTitle('Status'),
              const SizedBox(height: 8),
              _buildStatusSelector(context, filter, notifier),
              const SizedBox(height: 24),

              // Connection filter
              _buildSectionTitle('Connection'),
              const SizedBox(height: 8),
              _buildConnectionSelector(context, filter, notifier),
              const SizedBox(height: 24),

              // Sort options
              _buildSectionTitle('Sort By'),
              const SizedBox(height: 8),
              _buildSortSelector(context, filter, notifier),
              const SizedBox(height: 16),
              _buildSortDirection(context, filter, notifier),
              const SizedBox(height: 24),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SaturdayColors.primaryDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Apply Filters'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: SaturdayColors.secondaryGrey,
      ),
    );
  }

  Widget _buildStatusSelector(
    BuildContext context,
    UnitFilter filter,
    UnitFilterNotifier notifier,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChipOption(
          label: 'All',
          isSelected: filter.status == null,
          onSelected: () => notifier.setStatus(null),
        ),
        _FilterChipOption(
          label: 'Unprovisioned',
          isSelected: filter.status == UnitStatus.unprovisioned,
          onSelected: () => notifier.setStatus(UnitStatus.unprovisioned),
          color: SaturdayColors.secondaryGrey,
        ),
        _FilterChipOption(
          label: 'Factory Ready',
          isSelected: filter.status == UnitStatus.factoryProvisioned,
          onSelected: () => notifier.setStatus(UnitStatus.factoryProvisioned),
          color: SaturdayColors.info,
        ),
        _FilterChipOption(
          label: 'User Claimed',
          isSelected: filter.status == UnitStatus.userProvisioned,
          onSelected: () => notifier.setStatus(UnitStatus.userProvisioned),
          color: SaturdayColors.success,
        ),
      ],
    );
  }

  Widget _buildConnectionSelector(
    BuildContext context,
    UnitFilter filter,
    UnitFilterNotifier notifier,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChipOption(
          label: 'All',
          isSelected: filter.isConnected == null,
          onSelected: () => notifier.setConnected(null),
        ),
        _FilterChipOption(
          label: 'Connected',
          isSelected: filter.isConnected == true,
          onSelected: () => notifier.setConnected(true),
          color: SaturdayColors.success,
          icon: Icons.wifi,
        ),
        _FilterChipOption(
          label: 'Disconnected',
          isSelected: filter.isConnected == false,
          onSelected: () => notifier.setConnected(false),
          color: SaturdayColors.secondaryGrey,
          icon: Icons.wifi_off,
        ),
      ],
    );
  }

  Widget _buildSortSelector(
    BuildContext context,
    UnitFilter filter,
    UnitFilterNotifier notifier,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: UnitSortBy.values.map((sortBy) {
        return _FilterChipOption(
          label: sortBy.displayName,
          isSelected: filter.sortBy == sortBy,
          onSelected: () => notifier.setSortBy(sortBy),
        );
      }).toList(),
    );
  }

  Widget _buildSortDirection(
    BuildContext context,
    UnitFilter filter,
    UnitFilterNotifier notifier,
  ) {
    return Row(
      children: [
        Text(
          'Direction:',
          style: TextStyle(
            fontSize: 14,
            color: SaturdayColors.secondaryGrey,
          ),
        ),
        const SizedBox(width: 16),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.arrow_downward, size: 16),
              label: Text('Newest'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.arrow_upward, size: 16),
              label: Text('Oldest'),
            ),
          ],
          selected: {filter.sortAscending},
          onSelectionChanged: (selection) {
            notifier.setSortAscending(selection.first);
          },
        ),
      ],
    );
  }
}

/// Reusable filter chip option widget
class _FilterChipOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onSelected;
  final Color? color;
  final IconData? icon;

  const _FilterChipOption({
    required this.label,
    required this.isSelected,
    required this.onSelected,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? SaturdayColors.primaryDark;

    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : chipColor,
            ),
            const SizedBox(width: 4),
          ],
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: chipColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : chipColor,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? chipColor : chipColor.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
