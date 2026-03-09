import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A banner prompting the user to record track times.
///
/// Shown on the Now Playing screen when an album's track durations are unknown.
/// Appears in the space where the FlipTimer would normally be.
class TrackTimingBanner extends StatelessWidget {
  const TrackTimingBanner({
    super.key,
    required this.onStart,
  });

  /// Called when the user taps to start recording track times.
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onStart,
      child: Container(
        padding: const EdgeInsets.all(Spacing.lg),
        decoration: BoxDecoration(
          color: SaturdayColors.white,
          borderRadius: AppRadius.largeRadius,
          boxShadow: AppShadows.card,
          border: Border.all(
            color: SaturdayColors.primaryDark.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Spacing.sm),
              decoration: BoxDecoration(
                color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                borderRadius: AppRadius.smallRadius,
              ),
              child: Icon(
                Icons.timer_outlined,
                color: SaturdayColors.primaryDark,
                size: 24,
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Track times unknown',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to record them while you listen',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.secondary,
                        ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: SaturdayColors.secondary,
            ),
          ],
        ),
      ),
    );
  }
}
