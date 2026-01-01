import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/providers/production_unit_provider.dart';
import 'package:saturday_app/providers/step_label_provider.dart';
import 'package:saturday_app/providers/step_timer_provider.dart';
import 'package:saturday_app/providers/unit_timer_provider.dart';
import 'package:saturday_app/services/printer_service.dart';
import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/screens/production/machine_control_screen.dart';

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
  bool _isPrinting = false;

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

  Future<void> _printAllStepLabels() async {
    setState(() {
      _isPrinting = true;
    });

    try {
      // Get unit data
      final unitAsync = ref.read(unitByIdProvider(widget.unitId));
      final unit = unitAsync.value;

      if (unit == null) {
        _showError('Unit data not available');
        return;
      }

      // Get product and variant info
      final productAsync = ref.read(productProvider(unit.productId));
      final product = productAsync.value;

      if (product == null) {
        _showError('Product data not available');
        return;
      }

      final variantAsync = ref.read(variantProvider(unit.variantId));
      final variant = variantAsync.value;

      if (variant == null) {
        _showError('Variant data not available');
        return;
      }

      // Get labels for this step
      final labels = await ref.read(stepLabelsProvider(widget.step.id).future);

      if (labels.isEmpty) {
        _showError('No labels configured for this step');
        return;
      }

      AppLogger.info(
          'Printing ${labels.length} labels for step ${widget.step.name}');

      // Generate QR code once (used for all labels)
      final qrService = QRService();
      final qrImageData = await qrService.generateQRCode(
        unit.uuid,
        size: 512,
        embedLogo: true,
      );

      final printerService = PrinterService();
      int successCount = 0;
      int failCount = 0;

      // Print each label
      for (final label in labels) {
        try {
          // Generate label
          final labelData = await printerService.generateStepLabel(
            unit: unit,
            productName: product.name,
            variantName: variant.name,
            qrImageData: qrImageData,
            labelText: label.labelText,
          );

          // Print to configured printer with proper dimensions
          final success = await printerService.printLabel(
            labelData,
            labelWidth: 1.0,  // 1 inch labels
            labelHeight: 1.0,
          );

          if (success) {
            successCount++;
            AppLogger.info('Printed label: ${label.labelText}');
          } else {
            failCount++;
            AppLogger.warning('Failed to print label: ${label.labelText}');
          }

          // Small delay between prints
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          failCount++;
          AppLogger.error('Error printing label ${label.labelText}', e);
        }
      }

      if (mounted) {
        if (successCount > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                failCount > 0
                    ? '$successCount of ${labels.length} labels printed ($failCount failed)'
                    : 'All $successCount labels sent to printer',
              ),
              backgroundColor:
                  failCount > 0 ? Colors.orange : SaturdayColors.success,
            ),
          );
        } else {
          _showError('Failed to print all labels');
        }
      }
    } catch (error, stackTrace) {
      AppLogger.error('Error printing step labels', error, stackTrace);
      _showError('Failed to print labels: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isPrinting = false;
        });
      }
    }
  }

  void _openMachineControl() {
    // Get the unit data first
    final unitAsync = ref.read(unitByIdProvider(widget.unitId));
    final unit = unitAsync.value;

    if (unit == null) {
      _showError('Unit data not available');
      return;
    }

    // Navigate to Machine Control screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MachineControlScreen(
          step: widget.step,
          unit: unit,
        ),
      ),
    );
  }

  Future<void> _startTimer(String stepTimerId, int durationMinutes) async {
    try {
      final management = ref.read(unitTimerManagementProvider);

      await management.startTimer(
        unitId: widget.unitId,
        stepTimerId: stepTimerId,
        durationMinutes: durationMinutes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Timer started for $durationMinutes minutes'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (error) {
      _showError('Failed to start timer: $error');
    }
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

            // Print label button (only show if step has labels configured and on desktop)
            Consumer(
              builder: (context, ref, child) {
                final labelsAsync = ref.watch(stepLabelsProvider(widget.step.id));

                return labelsAsync.when(
                  data: (labels) {
                    if (labels.isEmpty ||
                        (!Platform.isMacOS &&
                            !Platform.isWindows &&
                            !Platform.isLinux)) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      children: [
                        OutlinedButton.icon(
                          onPressed: (_isSubmitting || _isPrinting)
                              ? null
                              : _printAllStepLabels,
                          icon: _isPrinting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.print),
                          label: Text(
                            _isPrinting
                                ? 'Printing...'
                                : 'Print Labels (${labels.length})',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SaturdayColors.primaryDark,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),

            // Timer controls (only show if step has timers configured)
            Consumer(
              builder: (context, ref, child) {
                final timersAsync = ref.watch(stepTimersProvider(widget.step.id));

                return timersAsync.when(
                  data: (timers) {
                    if (timers.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Timers',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        ...timers.map((timer) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: OutlinedButton.icon(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _startTimer(timer.id, timer.durationMinutes),
                              icon: const Icon(Icons.timer),
                              label: Text(
                                '${timer.timerName} (${timer.durationFormatted})',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: SaturdayColors.info,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),

            // Machine Control button (only show for machine steps on desktop)
            if (widget.step.stepType.requiresMachine &&
                (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) ...[
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _openMachineControl,
                icon: const Icon(Icons.precision_manufacturing),
                label: const Text('Open Machine Control'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SaturdayColors.info,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

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
