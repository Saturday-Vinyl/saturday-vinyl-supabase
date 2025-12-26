import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/widgets/tags/tag_status_badge.dart';

/// List item card displaying a single RFID tag
class TagListItem extends StatelessWidget {
  final RfidTag tag;
  final VoidCallback? onTap;
  final bool isHighlighted;

  const TagListItem({
    super.key,
    required this.tag,
    this.onTap,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isHighlighted ? 4 : 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isHighlighted
            ? BorderSide(color: SaturdayColors.success, width: 2)
            : BorderSide.none,
      ),
      color: isHighlighted
          ? SaturdayColors.success.withValues(alpha: 0.05)
          : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // RFID icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: TagStatusBadge.getColorForStatus(tag.status)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.label,
                  color: TagStatusBadge.getColorForStatus(tag.status),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),

              // Tag info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // EPC identifier
                    Text(
                      tag.formattedEpc,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                    ),
                    const SizedBox(height: 4),

                    // Secondary info row
                    Row(
                      children: [
                        // Created date
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: SaturdayColors.secondaryGrey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(tag.createdAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: SaturdayColors.secondaryGrey,
                              ),
                        ),

                        // TID if available
                        if (tag.tid != null && tag.tid!.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Icon(
                            Icons.fingerprint,
                            size: 14,
                            color: SaturdayColors.secondaryGrey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _truncateTid(tag.tid!),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: SaturdayColors.secondaryGrey,
                                      fontFamily: 'monospace',
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Status badge
              TagStatusBadge(status: tag.status),

              // Chevron
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: SaturdayColors.secondaryGrey,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM d, y').format(date);
    }
  }

  String _truncateTid(String tid) {
    if (tid.length <= 12) return tid.toUpperCase();
    return '${tid.substring(0, 8).toUpperCase()}...';
  }
}
