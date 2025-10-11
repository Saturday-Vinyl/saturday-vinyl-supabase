import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_unit.dart';

/// Card widget displaying production unit summary
class UnitCard extends StatelessWidget {
  final ProductionUnit unit;
  final VoidCallback onTap;
  final int totalSteps;
  final int completedSteps;

  const UnitCard({
    super.key,
    required this.unit,
    required this.onTap,
    required this.totalSteps,
    required this.completedSteps,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalSteps > 0 ? completedSteps / totalSteps : 0.0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Unit ID and Status
              Row(
                children: [
                  Expanded(
                    child: Text(
                      unit.unitId,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: SaturdayColors.primaryDark,
                          ),
                    ),
                  ),
                  _buildStatusBadge(context),
                ],
              ),

              const SizedBox(height: 12),

              // Progress bar
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Progress',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                      ),
                      Text(
                        '$completedSteps / $totalSteps steps',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor:
                          SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        unit.isCompleted
                            ? SaturdayColors.success
                            : SaturdayColors.info,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Metadata
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildMetadata(
                    context,
                    Icons.calendar_today,
                    'Created',
                    _formatDate(unit.createdAt),
                  ),
                  if (unit.productionStartedAt != null)
                    _buildMetadata(
                      context,
                      Icons.play_circle_outline,
                      'Started',
                      _formatDate(unit.productionStartedAt!),
                    ),
                  if (unit.productionCompletedAt != null)
                    _buildMetadata(
                      context,
                      Icons.check_circle_outline,
                      'Completed',
                      _formatDate(unit.productionCompletedAt!),
                    ),
                  if (unit.customerName != null)
                    _buildMetadata(
                      context,
                      Icons.person_outline,
                      'Customer',
                      unit.customerName!,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    final Color color;
    final String label;
    final IconData icon;

    if (unit.isCompleted) {
      color = SaturdayColors.success;
      label = 'Complete';
      icon = Icons.check_circle;
    } else if (unit.productionStartedAt != null) {
      color = SaturdayColors.info;
      label = 'In Progress';
      icon = Icons.play_circle;
    } else {
      color = SaturdayColors.secondaryGrey;
      label = 'Not Started';
      icon = Icons.radio_button_unchecked;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadata(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: SaturdayColors.secondaryGrey,
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }
}
