import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/utils/track_position_calculator.dart';

/// A card showing the currently playing track with elapsed/total time.
///
/// Displayed between the flip timer and the track list on the
/// Now Playing screen.
class CurrentTrackCard extends StatelessWidget {
  const CurrentTrackCard({
    super.key,
    required this.trackPosition,
  });

  final TrackPosition trackPosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeColor = trackPosition.isOvertime
        ? SaturdayColors.warning
        : SaturdayColors.secondary;

    return Container(
      decoration: AppDecorations.card,
      padding: Spacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.music_note,
                size: 14,
                color: SaturdayColors.secondary,
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                'Now Playing',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),

          // Track info
          Row(
            children: [
              // Position
              Text(
                trackPosition.track.position,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.primaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: Spacing.sm),

              // Title
              Expanded(
                child: Text(
                  trackPosition.track.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.primaryDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Spacing.sm),

              // Elapsed / Duration
              Text(
                '${trackPosition.formattedElapsed} / ${trackPosition.formattedDuration}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: timeColor,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
