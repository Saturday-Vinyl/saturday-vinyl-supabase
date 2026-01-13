import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// Badge that indicates the currently playing album was auto-detected by a hub.
class AutoDetectedBadge extends StatelessWidget {
  const AutoDetectedBadge({
    super.key,
    required this.deviceName,
  });

  /// The name of the device that detected the album.
  final String deviceName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.xs,
      ),
      decoration: BoxDecoration(
        color: SaturdayColors.success.withValues(alpha: 0.15),
        borderRadius: AppRadius.smallRadius,
        border: Border.all(
          color: SaturdayColors.success.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sensors,
            size: 16,
            color: SaturdayColors.success,
          ),
          const SizedBox(width: Spacing.xs),
          Text(
            'Detected by $deviceName',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.success,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
