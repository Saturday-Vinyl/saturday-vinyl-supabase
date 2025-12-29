import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A badge showing the physical location of an album.
///
/// Displays the crate name if known, or "Unknown location" otherwise.
/// Can optionally show a "last seen" timestamp.
class AlbumLocationBadge extends StatelessWidget {
  const AlbumLocationBadge({
    super.key,
    this.crateName,
    this.lastSeen,
    this.isCurrentlyDetected = false,
    this.onTap,
  });

  /// The name of the crate where the album is located.
  final String? crateName;

  /// When the album was last detected (if not currently detected).
  final DateTime? lastSeen;

  /// Whether the album is currently detected by a crate.
  final bool isCurrentlyDetected;

  /// Callback when the badge is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasLocation = crateName != null && crateName!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smallRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: hasLocation
              ? SaturdayColors.primaryDark.withValues(alpha: 0.1)
              : SaturdayColors.secondary.withValues(alpha: 0.1),
          borderRadius: AppRadius.smallRadius,
          border: Border.all(
            color: hasLocation
                ? SaturdayColors.primaryDark.withValues(alpha: 0.2)
                : SaturdayColors.secondary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasLocation ? Icons.inventory_2_outlined : Icons.help_outline,
              size: 18,
              color: hasLocation
                  ? SaturdayColors.primaryDark
                  : SaturdayColors.secondary,
            ),
            const SizedBox(width: Spacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hasLocation ? crateName! : 'Unknown location',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: hasLocation
                            ? SaturdayColors.primaryDark
                            : SaturdayColors.secondary,
                      ),
                ),
                if (!isCurrentlyDetected && lastSeen != null)
                  Text(
                    'Last seen ${_formatLastSeen(lastSeen!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.secondary,
                        ),
                  ),
                if (isCurrentlyDetected && hasLocation)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: SaturdayColors.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Currently detected',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.success,
                            ),
                      ),
                    ],
                  ),
              ],
            ),
            if (onTap != null) ...[
              const SizedBox(width: Spacing.sm),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: SaturdayColors.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${lastSeen.month}/${lastSeen.day}/${lastSeen.year}';
    }
  }
}

/// A compact location indicator for list views.
class LocationIndicator extends StatelessWidget {
  const LocationIndicator({
    super.key,
    this.crateName,
    this.isCurrentlyDetected = false,
  });

  final String? crateName;
  final bool isCurrentlyDetected;

  @override
  Widget build(BuildContext context) {
    final hasLocation = crateName != null && crateName!.isNotEmpty;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCurrentlyDetected)
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: SaturdayColors.success,
              shape: BoxShape.circle,
            ),
          )
        else
          Icon(
            hasLocation ? Icons.inventory_2_outlined : Icons.help_outline,
            size: 14,
            color: SaturdayColors.secondary,
          ),
        const SizedBox(width: 4),
        Text(
          hasLocation ? crateName! : 'Unknown',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondary,
              ),
        ),
      ],
    );
  }
}
