import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_tag_roll.dart';
import 'package:saturday_app/providers/rfid_tag_roll_provider.dart';
import 'package:saturday_app/screens/rolls/roll_print_screen.dart';
import 'package:saturday_app/screens/rolls/roll_write_screen.dart';
import 'package:saturday_app/widgets/common/error_state.dart';
import 'package:saturday_app/widgets/common/loading_indicator.dart';
import 'package:saturday_app/widgets/tags/rfid_module_status.dart';

/// Screen showing details of a specific roll
class RollDetailScreen extends ConsumerWidget {
  final String rollId;

  const RollDetailScreen({super.key, required this.rollId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rollAsync = ref.watch(rfidTagRollByIdProvider(rollId));
    final tagCountAsync = ref.watch(tagCountForRollProvider(rollId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roll Details'),
        actions: const [
          RfidAppBarStatus(),
          SizedBox(width: 8),
        ],
      ),
      body: rollAsync.when(
        data: (roll) {
          if (roll == null) {
            return const ErrorState(
              message: 'Roll not found',
              details: 'This roll may have been deleted.',
            );
          }
          return _buildContent(context, ref, roll, tagCountAsync);
        },
        loading: () => const LoadingIndicator(),
        error: (error, _) => ErrorState(
          message: 'Failed to load roll',
          details: error.toString(),
          onRetry: () => ref.invalidate(rfidTagRollByIdProvider(rollId)),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    RfidTagRoll roll,
    AsyncValue<int> tagCountAsync,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Roll ID card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Roll ${roll.shortId}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      _buildStatusBadge(roll),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Created ${_formatDate(roll.createdAt)}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Specifications card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Specifications',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Label Size', roll.dimensionsDisplay),
                  _buildInfoRow('Total Labels', roll.labelCount.toString()),
                  tagCountAsync.when(
                    data: (count) => _buildInfoRow('Tags Written', count.toString()),
                    loading: () => _buildInfoRow('Tags Written', '...'),
                    error: (_, __) => _buildInfoRow('Tags Written', 'Error'),
                  ),
                  if (roll.manufacturerUrl != null)
                    _buildInfoRow('Manufacturer', 'Link available'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Progress card (for printing status)
          if (roll.isPrinting || roll.isCompleted)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Print Progress',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: roll.printProgress,
                      backgroundColor: SaturdayColors.light,
                      color: roll.isCompleted
                          ? SaturdayColors.success
                          : SaturdayColors.info,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${roll.lastPrintedPosition} of ${roll.labelCount} printed (${(roll.printProgress * 100).toStringAsFixed(0)}%)',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Action buttons
          _buildActionButtons(context, ref, roll),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(RfidTagRoll roll) {
    Color badgeColor;
    String label;

    switch (roll.status) {
      case RfidTagRollStatus.writing:
        badgeColor = SaturdayColors.info;
        label = 'Writing';
        break;
      case RfidTagRollStatus.readyToPrint:
        badgeColor = SaturdayColors.success;
        label = 'Ready to Print';
        break;
      case RfidTagRollStatus.printing:
        badgeColor = SaturdayColors.info;
        label = 'Printing';
        break;
      case RfidTagRollStatus.completed:
        badgeColor = SaturdayColors.secondaryGrey;
        label = 'Completed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: badgeColor,
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref, RfidTagRoll roll) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary action based on status
        if (roll.isWriting)
          FilledButton.icon(
            onPressed: () => _continueWriting(context, roll),
            icon: const Icon(Icons.edit),
            label: const Text('Continue Writing'),
            style: FilledButton.styleFrom(
              backgroundColor: SaturdayColors.primaryDark,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

        if (roll.isReadyToPrint)
          FilledButton.icon(
            onPressed: () => _startPrinting(context, roll),
            icon: const Icon(Icons.print),
            label: const Text('Start Printing'),
            style: FilledButton.styleFrom(
              backgroundColor: SaturdayColors.success,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

        if (roll.isPrinting)
          FilledButton.icon(
            onPressed: () => _continuePrinting(context, roll),
            icon: const Icon(Icons.print),
            label: const Text('Continue Printing'),
            style: FilledButton.styleFrom(
              backgroundColor: SaturdayColors.info,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

        if (roll.isCompleted) ...[
          FilledButton.icon(
            onPressed: () => _reprintRoll(context, roll),
            icon: const Icon(Icons.print),
            label: const Text('Reprint Labels'),
            style: FilledButton.styleFrom(
              backgroundColor: SaturdayColors.secondaryGrey,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Secondary actions
        if (!roll.isCompleted)
          OutlinedButton.icon(
            onPressed: () => _markComplete(context, ref, roll),
            icon: const Icon(Icons.check),
            label: const Text('Mark as Complete'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

        const SizedBox(height: 12),

        // Delete button
        TextButton.icon(
          onPressed: () => _deleteRoll(context, ref, roll),
          icon: const Icon(Icons.delete_outline, color: SaturdayColors.error),
          label: const Text(
            'Delete Roll',
            style: TextStyle(color: SaturdayColors.error),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  void _continueWriting(BuildContext context, RfidTagRoll roll) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RollWriteScreen(rollId: roll.id),
      ),
    );
  }

  void _startPrinting(BuildContext context, RfidTagRoll roll) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RollPrintScreen(rollId: roll.id),
      ),
    );
  }

  void _continuePrinting(BuildContext context, RfidTagRoll roll) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RollPrintScreen(rollId: roll.id),
      ),
    );
  }

  void _reprintRoll(BuildContext context, RfidTagRoll roll) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RollPrintScreen(rollId: roll.id, startFromPosition: 1),
      ),
    );
  }

  Future<void> _markComplete(BuildContext context, WidgetRef ref, RfidTagRoll roll) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Roll as Complete?'),
        content: const Text(
          'This will finalize the roll. You can still reprint labels if needed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(rfidTagRollManagementProvider).completeRoll(roll.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Roll marked as complete')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to complete roll: $e'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteRoll(BuildContext context, WidgetRef ref, RfidTagRoll roll) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Roll?'),
        content: const Text(
          'This will delete the roll record. Tags written to this roll will remain in the system but will no longer be associated with a roll.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: SaturdayColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(rfidTagRollManagementProvider).deleteRoll(roll.id);
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Roll deleted')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete roll: $e'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    }
  }
}
