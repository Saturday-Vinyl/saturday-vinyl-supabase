import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/providers/file_provider.dart';

/// Widget to display a single production step
class ProductionStepItem extends ConsumerWidget {
  final ProductionStep step;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isEditable;
  final bool showDragHandle;
  final int? reorderIndex;

  const ProductionStepItem({
    super.key,
    required this.step,
    this.onEdit,
    this.onDelete,
    this.isEditable = false,
    this.showDragHandle = false,
    this.reorderIndex,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Drag handle (if enabled)
            if (showDragHandle && reorderIndex != null) ...[
              ReorderableDragStartListener(
                index: reorderIndex!,
                child: Icon(
                  Icons.drag_indicator,
                  color: SaturdayColors.secondaryGrey,
                ),
              ),
              const SizedBox(width: 12),
            ],

            // Step number badge
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: SaturdayColors.primaryDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${step.stepOrder}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: SaturdayColors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Step info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: SaturdayColors.primaryDark,
                        ),
                  ),
                  if (step.description != null && step.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      step.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ],
                  // Show attached files count
                  const SizedBox(height: 8),
                  _buildFileAttachments(ref),
                ],
              ),
            ),

            // Action buttons (if editable)
            if (isEditable) ...[
              IconButton(
                icon: const Icon(Icons.edit, color: SaturdayColors.info),
                onPressed: onEdit,
                tooltip: 'Edit',
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: SaturdayColors.error),
                onPressed: onDelete,
                tooltip: 'Delete',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileAttachments(WidgetRef ref) {
    final filesAsync = ref.watch(stepFilesProvider(step.id));

    return filesAsync.when(
      data: (files) {
        if (files.isEmpty) {
          return const SizedBox.shrink();
        }

        return Row(
          children: [
            Icon(
              Icons.attach_file,
              size: 16,
              color: SaturdayColors.info,
            ),
            const SizedBox(width: 4),
            Text(
              '${files.length} file${files.length == 1 ? '' : 's'} attached',
              style: const TextStyle(
                fontSize: 12,
                color: SaturdayColors.info,
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
