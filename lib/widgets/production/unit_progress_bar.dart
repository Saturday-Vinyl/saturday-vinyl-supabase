import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';

/// Visual progress bar for production unit completion
class UnitProgressBar extends StatelessWidget {
  final int completedSteps;
  final int totalSteps;
  final bool showPercentage;

  const UnitProgressBar({
    super.key,
    required this.completedSteps,
    required this.totalSteps,
    this.showPercentage = true,
  });

  double get progress => totalSteps > 0 ? completedSteps / totalSteps : 0.0;
  int get percentage => (progress * 100).round();

  @override
  Widget build(BuildContext context) {
    final isComplete = completedSteps == totalSteps && totalSteps > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: SaturdayColors.primaryDark,
                  ),
            ),
            if (showPercentage)
              Text(
                '$percentage%',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isComplete
                          ? SaturdayColors.success
                          : SaturdayColors.info,
                    ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 12,
            backgroundColor: SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(
              isComplete ? SaturdayColors.success : SaturdayColors.info,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$completedSteps of $totalSteps steps complete',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
      ],
    );
  }
}
