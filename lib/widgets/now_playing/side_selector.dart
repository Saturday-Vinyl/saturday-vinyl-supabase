import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A selector for choosing the current record side.
///
/// Dynamically renders a button for each available side (A, B, C, D, etc.)
/// to support multi-disc albums.
class SideSelector extends StatelessWidget {
  const SideSelector({
    super.key,
    required this.currentSide,
    required this.availableSides,
    required this.onSideChanged,
    this.sideDurations = const {},
  });

  /// The currently selected side letter.
  final String currentSide;

  /// All available side letters, in order.
  final List<String> availableSides;

  /// Callback when the side is changed.
  final ValueChanged<String> onSideChanged;

  /// Optional durations per side in seconds.
  final Map<String, int> sideDurations;

  @override
  Widget build(BuildContext context) {
    if (availableSides.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.card,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < availableSides.length; i++)
              _SideButton(
                side: availableSides[i],
                isSelected: currentSide == availableSides[i],
                duration: sideDurations[availableSides[i]],
                onTap: () => onSideChanged(availableSides[i]),
                isFirst: i == 0,
                isLast: i == availableSides.length - 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.side,
    required this.isSelected,
    required this.onTap,
    required this.isFirst,
    required this.isLast,
    this.duration,
  });

  final String side;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;
  final int? duration;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.only(
      topLeft: isFirst ? const Radius.circular(AppRadius.lg) : Radius.zero,
      bottomLeft: isFirst ? const Radius.circular(AppRadius.lg) : Radius.zero,
      topRight: isLast ? const Radius.circular(AppRadius.lg) : Radius.zero,
      bottomRight: isLast ? const Radius.circular(AppRadius.lg) : Radius.zero,
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
