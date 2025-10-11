import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/production_unit_provider.dart';

/// Modal screen for completing a production step
class CompleteStepScreen extends ConsumerStatefulWidget {
  final String unitId;
  final String unitName;
  final ProductionStep step;

  const CompleteStepScreen({
    super.key,
    required this.unitId,
    required this.unitName,
    required this.step,
  });

  @override
  ConsumerState<CompleteStepScreen> createState() => _CompleteStepScreenState();
}

class _CompleteStepScreenState extends ConsumerState<CompleteStepScreen> {
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _completeStep() async {
    final currentUserAsync = ref.read(currentUserProvider);
    final currentUser = currentUserAsync.value;

    if (currentUser == null) {
      _showError('You must be logged in to complete steps');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final management = ref.read(productionUnitManagementProvider);
      final updatedUnit = await management.completeStep(
        unitId: widget.unitId,
        stepId: widget.step.id,
        userId: currentUser.id,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (mounted) {
        // Return the updated unit to the caller
        Navigator.pop(context, updatedUnit);
      }
    } catch (error) {
      setState(() {
        _isSubmitting = false;
      });
      _showError('Failed to complete step: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: SaturdayColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: SaturdayColors.success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: SaturdayColors.success,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Complete Step',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        widget.unitName,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondaryGrey,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Step info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SaturdayColors.light,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: SaturdayColors.primaryDark,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${widget.step.stepOrder}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.step.name,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.step.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.step.description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondaryGrey,
                          ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Notes field
            Text(
              'Notes (optional)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add any notes about this step...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              enabled: !_isSubmitting,
            ),

            const SizedBox(height: 24),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _completeStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SaturdayColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Complete Step'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
