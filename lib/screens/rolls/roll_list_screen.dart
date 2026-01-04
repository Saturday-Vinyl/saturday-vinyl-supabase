import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_tag_roll.dart';
import 'package:saturday_app/providers/rfid_tag_roll_provider.dart';
import 'package:saturday_app/screens/rolls/create_roll_screen.dart';
import 'package:saturday_app/screens/rolls/roll_detail_screen.dart';
import 'package:saturday_app/widgets/common/empty_state.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/tags/rfid_module_status.dart';

/// Main screen for viewing and managing RFID tag rolls
class RollListScreen extends ConsumerStatefulWidget {
  const RollListScreen({super.key});

  @override
  ConsumerState<RollListScreen> createState() => _RollListScreenState();
}

class _RollListScreenState extends ConsumerState<RollListScreen> {
  RfidTagRollStatus? _statusFilter;

  @override
  Widget build(BuildContext context) {
    final rollsAsync = _statusFilter != null
        ? ref.watch(rfidTagRollsByStatusProvider(_statusFilter))
        : ref.watch(allRfidTagRollsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tag Rolls'),
        actions: [
          FilledButton.icon(
            onPressed: _createNewRoll,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Roll'),
            style: FilledButton.styleFrom(
              backgroundColor: SaturdayColors.primaryDark,
              foregroundColor: SaturdayColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 8),
          const RfidAppBarStatus(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Filter bar
          _buildFilterBar(),

          // Roll list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshRolls,
              child: rollsAsync.when(
                data: (rolls) => _buildRollList(rolls),
                loading: () => const LoadingIndicator(),
                error: (error, _) => ErrorState(
                  message: 'Failed to load rolls',
                  details: error.toString(),
                  onRetry: _refreshRolls,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<RfidTagRollStatus?>(
              value: _statusFilter,
              decoration: const InputDecoration(
                labelText: 'Status',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem<RfidTagRollStatus?>(
                  value: null,
                  child: Text('All Statuses'),
                ),
                ...RfidTagRollStatus.values.map((status) => DropdownMenuItem(
                      value: status,
                      child: Text(_getStatusLabel(status)),
                    )),
              ],
              onChanged: (value) {
                setState(() {
                  _statusFilter = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRollList(List<RfidTagRoll> rolls) {
    if (rolls.isEmpty) {
      if (_statusFilter != null) {
        return EmptyState(
          icon: Icons.filter_list_off,
          message: 'No rolls with status "${_getStatusLabel(_statusFilter!)}".',
          actionLabel: 'Clear Filter',
          onAction: () {
            setState(() {
              _statusFilter = null;
            });
          },
        );
      }
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'No tag rolls yet.\nCreate a new roll to start writing RFID tags.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rolls.length,
      itemBuilder: (context, index) {
        final roll = rolls[index];
        return _RollListItem(
          roll: roll,
          onTap: () => _openRollDetail(roll),
        );
      },
    );
  }

  String _getStatusLabel(RfidTagRollStatus status) {
    switch (status) {
      case RfidTagRollStatus.writing:
        return 'Writing';
      case RfidTagRollStatus.readyToPrint:
        return 'Ready to Print';
      case RfidTagRollStatus.printing:
        return 'Printing';
      case RfidTagRollStatus.completed:
        return 'Completed';
    }
  }

  Future<void> _refreshRolls() async {
    if (_statusFilter != null) {
      ref.invalidate(rfidTagRollsByStatusProvider(_statusFilter));
    } else {
      ref.invalidate(allRfidTagRollsProvider);
    }
  }

  void _openRollDetail(RfidTagRoll roll) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RollDetailScreen(rollId: roll.id),
      ),
    );
  }

  void _createNewRoll() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CreateRollScreen(),
      ),
    );
  }
}

/// List item widget for a single roll
class _RollListItem extends StatelessWidget {
  final RfidTagRoll roll;
  final VoidCallback onTap;

  const _RollListItem({
    required this.roll,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: _buildStatusIcon(),
        title: Text(
          'Roll ${roll.shortId}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(roll.dimensionsDisplay),
            Text(
              '${roll.labelCount} labels',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildStatusBadge(),
            if (roll.isPrinting || roll.isCompleted)
              Text(
                '${roll.lastPrintedPosition}/${roll.labelCount}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData iconData;
    Color iconColor;

    switch (roll.status) {
      case RfidTagRollStatus.writing:
        iconData = Icons.edit;
        iconColor = SaturdayColors.info;
        break;
      case RfidTagRollStatus.readyToPrint:
        iconData = Icons.print;
        iconColor = SaturdayColors.success;
        break;
      case RfidTagRollStatus.printing:
        iconData = Icons.print;
        iconColor = SaturdayColors.info;
        break;
      case RfidTagRollStatus.completed:
        iconData = Icons.check_circle;
        iconColor = SaturdayColors.success;
        break;
    }

    return CircleAvatar(
      backgroundColor: iconColor.withValues(alpha: 0.1),
      child: Icon(iconData, color: iconColor),
    );
  }

  Widget _buildStatusBadge() {
    Color badgeColor;
    String label;

    switch (roll.status) {
      case RfidTagRollStatus.writing:
        badgeColor = SaturdayColors.info;
        label = 'Writing';
        break;
      case RfidTagRollStatus.readyToPrint:
        badgeColor = SaturdayColors.success;
        label = 'Ready';
        break;
      case RfidTagRollStatus.printing:
        badgeColor = SaturdayColors.info;
        label = 'Printing';
        break;
      case RfidTagRollStatus.completed:
        badgeColor = SaturdayColors.secondaryGrey;
        label = 'Done';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: badgeColor,
        ),
      ),
    );
  }
}
