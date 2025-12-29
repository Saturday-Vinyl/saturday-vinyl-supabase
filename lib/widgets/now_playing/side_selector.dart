import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A toggle button for selecting Side A or Side B.
///
/// Used in the Now Playing screen to switch between record sides
/// and reset the flip timer.
class SideSelector extends StatelessWidget {
  const SideSelector({
    super.key,
    required this.currentSide,
    required this.onSideChanged,
    this.sideADuration,
    this.sideBDuration,
  });

  /// The currently selected side ('A' or 'B').
  final String currentSide;

  /// Callback when the side is changed.
  final ValueChanged<String> onSideChanged;

  /// Optional duration of Side A in seconds.
  final int? sideADuration;

  /// Optional duration of Side B in seconds.
  final int? sideBDuration;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SideButton(
            side: 'A',
            isSelected: currentSide == 'A',
            duration: sideADuration,
            onTap: () => onSideChanged('A'),
            isLeft: true,
          ),
          _SideButton(
            side: 'B',
            isSelected: currentSide == 'B',
            duration: sideBDuration,
            onTap: () => onSideChanged('B'),
            isLeft: false,
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.side,
    required this.isSelected,
    required this.onTap,
    required this.isLeft,
    this.duration,
  });

  final String side;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isLeft;
  final int? duration;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.only(
      topLeft: isLeft ? const Radius.circular(AppRadius.lg) : Radius.zero,
      bottomLeft: isLeft ? const Radius.circular(AppRadius.lg) : Radius.zero,
      topRight: !isLeft ? const Radius.circular(AppRadius.lg) : Radius.zero,
      bottomRight: !isLeft ? const Radius.circular(AppRadius.lg) : Radius.zero,
    );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.xl,
          vertical: Spacing.md,
        ),
        decoration: BoxDecoration(
          color: isSelected ? SaturdayColors.primaryDark : Colors.transparent,
          borderRadius: borderRadius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Side $side',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: isSelected
                        ? SaturdayColors.white
                        : SaturdayColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (duration != null && duration! > 0) ...[
              const SizedBox(height: 2),
              Text(
                _formatDuration(duration!),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isSelected
                          ? SaturdayColors.white.withValues(alpha: 0.7)
                          : SaturdayColors.secondary,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
