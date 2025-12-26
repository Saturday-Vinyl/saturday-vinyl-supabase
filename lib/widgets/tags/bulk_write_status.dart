import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/bulk_write_provider.dart';

/// Status display during bulk write operations
class BulkWriteStatus extends ConsumerWidget {
  final VoidCallback? onStop;

  const BulkWriteStatus({super.key, this.onStop});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bulkState = ref.watch(bulkWriteProvider);

    if (!bulkState.isWriting) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SaturdayColors.info.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: SaturdayColors.info.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Progress indicator
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: SaturdayColors.info,
            ),
          ),
          const SizedBox(width: 12),

          // Current operation text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  bulkState.currentOperation ?? 'Processing...',
                  style: TextStyle(
                    color: SaturdayColors.info,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (bulkState.tagsWritten > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${bulkState.tagsWritten} tag${bulkState.tagsWritten == 1 ? '' : 's'} created',
                    style: TextStyle(
                      fontSize: 12,
                      color: SaturdayColors.success,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Tags written count badge
          _buildCountBadge(bulkState.tagsWritten),

          const SizedBox(width: 12),

          // Stop button
          TextButton.icon(
            onPressed: bulkState.stopRequested
                ? null
                : () {
                    ref.read(bulkWriteProvider.notifier).stopBulkWrite();
                    onStop?.call();
                  },
            icon: Icon(
              Icons.stop,
              size: 18,
              color: bulkState.stopRequested
                  ? SaturdayColors.secondaryGrey
                  : SaturdayColors.error,
            ),
            label: Text(
              bulkState.stopRequested ? 'Stopping...' : 'Stop',
              style: TextStyle(
                color: bulkState.stopRequested
                    ? SaturdayColors.secondaryGrey
                    : SaturdayColors.error,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              backgroundColor: SaturdayColors.error.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: SaturdayColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SaturdayColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            size: 14,
            color: SaturdayColors.success,
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: SaturdayColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact status chip for bulk write mode
class BulkWriteChip extends ConsumerWidget {
  final VoidCallback? onTap;

  const BulkWriteChip({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bulkState = ref.watch(bulkWriteProvider);

    if (!bulkState.isWriting && bulkState.tagsWritten == 0) {
      return const SizedBox.shrink();
    }

    final isWriting = bulkState.isWriting;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isWriting
              ? SaturdayColors.info.withValues(alpha: 0.1)
              : SaturdayColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isWriting
                ? SaturdayColors.info.withValues(alpha: 0.3)
                : SaturdayColors.success.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWriting) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SaturdayColors.info,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              isWriting
                  ? 'Writing (${bulkState.tagsWritten})'
                  : '${bulkState.tagsWritten} written',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isWriting ? SaturdayColors.info : SaturdayColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
