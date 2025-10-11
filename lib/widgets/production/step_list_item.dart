import 'dart:io';
import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/unit_step_completion.dart';
import 'package:saturday_app/widgets/production/file_action_button.dart';

/// Widget displaying a production step with completion status
class StepListItem extends StatelessWidget {
  final ProductionStep step;
  final UnitStepCompletion? completion;
  final VoidCallback? onTap;

  const StepListItem({
    super.key,
    required this.step,
    this.completion,
    this.onTap,
  });

  bool get isCompleted => completion != null;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isCompleted ? 0 : 1,
      color: isCompleted
          ? SaturdayColors.success.withValues(alpha: 0.05)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCompleted
              ? SaturdayColors.success.withValues(alpha: 0.3)
              : SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: isCompleted ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step number, firmware icon, or checkmark
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? SaturdayColors.success
                      : step.isFirmwareStep()
                          ? SaturdayColors.info.withValues(alpha: 0.1)
                          : SaturdayColors.light,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCompleted
                        ? SaturdayColors.success
                        : step.isFirmwareStep()
                            ? SaturdayColors.info
                            : SaturdayColors.secondaryGrey,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(
                          Icons.check,
                          size: 18,
                          color: Colors.white,
                        )
                      : step.isFirmwareStep()
                          ? Icon(
                              Icons.memory,
                              size: 18,
                              color: SaturdayColors.info,
                            )
                          : Text(
                              '${step.stepOrder}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: SaturdayColors.primaryDark,
                                  ),
                            ),
                ),
              ),

              const SizedBox(width: 12),

              // Step details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isCompleted
                                ? SaturdayColors.primaryDark
                                : SaturdayColors.primaryDark,
                            decoration:
                                isCompleted ? TextDecoration.lineThrough : null,
                          ),
                    ),
                    if (step.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        step.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                      ),
                    ],
                    // File action button (desktop only, if file attached)
                    if ((Platform.isMacOS || Platform.isWindows || Platform.isLinux) &&
                        step.fileUrl != null &&
                        step.fileName != null &&
                        step.fileType != null) ...[
                      const SizedBox(height: 12),
                      FileActionButton(
                        fileUrl: step.fileUrl!,
                        fileName: step.fileName!,
                        fileType: step.fileType!,
                      ),
                    ],
                    if (isCompleted && completion != null) ...[
                      const SizedBox(height: 8),
                      _buildCompletionInfo(context),
                    ],
                  ],
                ),
              ),

              // Action indicator
              if (!isCompleted && onTap != null)
                const Icon(
                  Icons.play_circle_outline,
                  color: SaturdayColors.info,
                  size: 28,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionInfo(BuildContext context) {
    if (completion == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: SaturdayColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                size: 14,
                color: SaturdayColors.success,
              ),
              const SizedBox(width: 4),
              Text(
                'Completed',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.success,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(completion!.completedAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondaryGrey,
                ),
          ),
          if (completion!.notes != null && completion!.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Notes: ${completion!.notes}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
