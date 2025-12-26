import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/models/unit_step_completion.dart';
import 'package:saturday_app/providers/production_unit_provider.dart';
import 'package:saturday_app/providers/product_provider.dart';
import 'package:saturday_app/providers/unit_timer_provider.dart';
import 'package:saturday_app/screens/production/complete_step_screen.dart';
import 'package:saturday_app/screens/production/firmware_flash_screen.dart';
import 'package:saturday_app/services/qr_service.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/production/completion_confirmation.dart';
import 'package:saturday_app/widgets/production/print_preview_dialog.dart';
import 'package:saturday_app/widgets/production/qr_code_display.dart';
import 'package:saturday_app/widgets/production/step_list_item.dart';
import 'package:saturday_app/widgets/production/unit_progress_bar.dart';

/// Detail screen for a production unit
class UnitDetailScreen extends ConsumerStatefulWidget {
  final String unitId;

  const UnitDetailScreen({
    super.key,
    required this.unitId,
  });

  @override
  ConsumerState<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends ConsumerState<UnitDetailScreen> {
  bool _isRegeneratingQR = false;
  Timer? _timerUpdateTimer;

  @override
  void initState() {
    super.initState();
    // Start a timer to refresh active timers every second for countdown
    _timerUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        ref.invalidate(activeUnitTimersWithDetailsProvider(widget.unitId));
      }
    });
  }

  @override
  void dispose() {
    _timerUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unitAsync = ref.watch(unitByIdProvider(widget.unitId));
    final stepsAsync = ref.watch(unitStepsProvider(widget.unitId));
    final completionsAsync = ref.watch(unitStepCompletionsProvider(widget.unitId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Production Unit'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        actions: [
          // Only show print button on desktop platforms
          if (Platform.isMacOS || Platform.isWindows || Platform.isLinux)
            IconButton(
              icon: const Icon(Icons.print),
              onPressed: () => _printLabel(context, ref),
              tooltip: 'Print Label',
            ),
        ],
      ),
      body: unitAsync.when(
        data: (unit) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // QR Code
                Center(
                  child: QRCodeDisplay(
                    qrCodeUrl: unit.qrCodeUrl,
                    unitId: unit.unitId,
                    size: 200,
                    onRegenerate: _isRegeneratingQR
                        ? null
                        : () => _regenerateQRCode(context, unit),
                  ),
                ),

                const SizedBox(height: 32),

                // Unit Info Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unit Information',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Divider(height: 24),
                        _buildInfoRow(
                          context,
                          'Unit ID',
                          unit.unitId,
                        ),
                        _buildInfoRow(
                          context,
                          'Status',
                          unit.isCompleted
                              ? 'Complete'
                              : unit.isInProgress()
                                  ? 'In Progress'
                                  : 'Not Started',
                        ),
                        if (unit.shopifyOrderNumber != null)
                          _buildInfoRow(
                            context,
                            'Order',
                            unit.shopifyOrderNumber!,
                          ),
                        if (unit.customerName != null)
                          _buildInfoRow(
                            context,
                            'Customer',
                            unit.customerName!,
                          ),
                        _buildInfoRow(
                          context,
                          'Created',
                          _formatDate(unit.createdAt),
                        ),
                        if (unit.productionStartedAt != null)
                          _buildInfoRow(
                            context,
                            'Started',
                            _formatDate(unit.productionStartedAt!),
                          ),
                        if (unit.productionCompletedAt != null)
                          _buildInfoRow(
                            context,
                            'Completed',
                            _formatDate(unit.productionCompletedAt!),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Progress
                stepsAsync.when(
                  data: (steps) {
                    return completionsAsync.when(
                      data: (completions) {
                        return UnitProgressBar(
                          completedSteps: completions.length,
                          totalSteps: steps.length,
                        );
                      },
                      loading: () => const CircularProgressIndicator(),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                  loading: () => const CircularProgressIndicator(),
                  error: (_, __) => const SizedBox.shrink(),
                ),

                const SizedBox(height: 24),

                // Active Timers
                Consumer(
                  builder: (context, ref, child) {
                    final activeTimersAsync =
                        ref.watch(activeUnitTimersWithDetailsProvider(widget.unitId));

                    return activeTimersAsync.when(
                      data: (activeTimers) {
                        if (activeTimers.isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Timers',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 12),
                            ...activeTimers.map((timerWithDetails) {
                              final unitTimer = timerWithDetails.unitTimer;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        unitTimer.isExpired
                                            ? Icons.alarm
                                            : Icons.timer,
                                        color: unitTimer.isExpired
                                            ? SaturdayColors.error
                                            : SaturdayColors.info,
                                        size: 32,
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              timerWithDetails.timerName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              unitTimer.isExpired
                                                  ? 'EXPIRED!'
                                                  : 'Time remaining: ${unitTimer.remainingFormatted}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: unitTimer.isExpired
                                                        ? SaturdayColors.error
                                                        : SaturdayColors
                                                            .secondaryGrey,
                                                    fontWeight:
                                                        unitTimer.isExpired
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () => _completeTimer(
                                            unitTimer.id, widget.unitId),
                                        child: const Text('Complete'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 24),
                          ],
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                ),

                // Production Steps
                Text(
                  'Production Steps',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),

                stepsAsync.when(
                  data: (steps) {
                    if (steps.isEmpty) {
                      return const Center(
                        child: Text('No production steps defined'),
                      );
                    }

                    return completionsAsync.when(
                      data: (completions) {
                        // Create map of completions by step ID
                        final completionMap = <String, UnitStepCompletion>{};
                        for (final completion in completions) {
                          completionMap[completion.stepId] = completion;
                        }

                        return Column(
                          children: steps.map((step) {
                            final completion = completionMap[step.id];
                            return StepListItem(
                              step: step,
                              completion: completion,
                              onTap: () => _completeStep(context, ref, step),
                            );
                          }).toList(),
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (error, _) => Center(
                        child: Text('Error loading completions: $error'),
                      ),
                    );
                  },
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => Center(
                    child: Text('Error loading steps: $error'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Error loading unit: $error'),
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _regenerateQRCode(
    BuildContext context,
    ProductionUnit unit,
  ) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate QR Code'),
        content: const Text(
          'This will regenerate the QR code with the new branded design. '
          'The existing QR code will be replaced. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isRegeneratingQR = true;
    });

    try {
      final qrService = QRService();
      final supabase = SupabaseService.instance.client;

      AppLogger.info('Regenerating QR code for unit: ${unit.uuid}');

      // Generate new branded QR code
      final qrImageData = await qrService.generateQRCode(
        unit.uuid,
        size: 512,
        embedLogo: true,
      );

      AppLogger.info('QR code generated, size: ${qrImageData.length} bytes');

      // Upload to Supabase storage (remove old file first if it exists)
      final filePath = 'qr-codes/${unit.uuid}.png';

      try {
        // Try to remove existing file
        await supabase.storage.from('qr-codes').remove([filePath]);
        AppLogger.info('Removed existing QR code');
      } catch (e) {
        // File might not exist, that's OK
        AppLogger.info('No existing QR code to remove (or removal failed)');
      }

      // Upload new QR code
      await supabase.storage
          .from('qr-codes')
          .uploadBinary(filePath, qrImageData);

      AppLogger.info('Successfully regenerated QR code');

      if (context.mounted) {
        // Refresh the UI to show the new QR code
        ref.invalidate(unitByIdProvider(widget.unitId));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ QR code regenerated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to regenerate QR code', error, stackTrace);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to regenerate QR code: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRegeneratingQR = false;
        });
      }
    }
  }

  Future<void> _printLabel(BuildContext context, WidgetRef ref) async {
    try {
      // Get the current unit
      final unitAsync = ref.read(unitByIdProvider(widget.unitId));
      final unit = unitAsync.value;

      if (unit == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unit data not available')),
          );
        }
        return;
      }

      // Get product and variant info
      final productAsync = ref.read(productProvider(unit.productId));
      final product = productAsync.value;

      if (product == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product data not available')),
          );
        }
        return;
      }

      final variantAsync = ref.read(variantProvider(unit.variantId));
      final variant = variantAsync.value;

      if (variant == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Variant data not available')),
          );
        }
        return;
      }

      // Download QR code image
      Uint8List? qrImageData;
      try {
        final response = await http.get(Uri.parse(unit.qrCodeUrl));
        if (response.statusCode == 200) {
          qrImageData = response.bodyBytes;
        } else {
          // If download fails, generate QR code
          final qrService = QRService();
          qrImageData = await qrService.generateQRCode(
            unit.uuid,
            size: 200,
          );
        }
      } catch (e) {
        AppLogger.error('Error loading QR code', e);
        // Generate QR code as fallback
        final qrService = QRService();
        qrImageData = await qrService.generateQRCode(
          unit.uuid,
          size: 200,
        );
      }

      // Show print preview dialog
      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) => PrintPreviewDialog(
            unit: unit,
            productName: product.name,
            variantName: variant.name,
            qrImageData: qrImageData!,
          ),
        );
      }
    } catch (e) {
      AppLogger.error('Error printing label', e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _completeTimer(String timerId, String unitId) async {
    try {
      final management = ref.read(unitTimerManagementProvider);
      await management.completeTimer(timerId, unitId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timer completed'),
            backgroundColor: SaturdayColors.success,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete timer: $error'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  Future<void> _completeStep(
    BuildContext context,
    WidgetRef ref,
    ProductionStep step,
  ) async {
    final unitAsync = ref.read(unitByIdProvider(widget.unitId));
    final unit = unitAsync.value;

    if (unit == null) return;

    // Check if this is a firmware provisioning step
    if (step.isFirmwareStep()) {
      // Navigate to firmware flash screen instead
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => FirmwareFlashScreen(
            unit: unit,
            stepId: step.id,
          ),
        ),
      );

      // If firmware was flashed successfully, refresh the UI
      if (result == true && context.mounted) {
        ref.invalidate(unitByIdProvider(widget.unitId));
        ref.invalidate(unitStepCompletionsProvider(widget.unitId));

        // Check if unit is fully complete
        final stepsAsync = ref.read(unitStepsProvider(widget.unitId));
        final completionsAsync = ref.read(unitStepCompletionsProvider(widget.unitId));

        final isUnitComplete = stepsAsync.value != null &&
            completionsAsync.value != null &&
            stepsAsync.value!.length == completionsAsync.value!.length;

        // Show confirmation dialog
        await showDialog(
          context: context,
          builder: (context) => CompletionConfirmation(
            isUnitComplete: isUnitComplete,
            onPrintLabel: () {
              Navigator.of(context).pop();
              _printLabel(context, ref);
            },
            onClose: () => Navigator.of(context).pop(),
          ),
        );
      }
      return;
    }

    // Show normal completion dialog for non-firmware steps
    final updatedUnit = await showDialog<ProductionUnit>(
      context: context,
      builder: (context) => CompleteStepScreen(
        unitId: unit.id,
        unitName: unit.unitId,
        step: step,
      ),
    );

    // If step was completed, show confirmation
    if (updatedUnit != null && context.mounted) {
      // Invalidate providers to refresh UI
      ref.invalidate(unitByIdProvider(widget.unitId));
      ref.invalidate(unitStepCompletionsProvider(widget.unitId));

      // Check if unit is fully complete
      final stepsAsync = ref.read(unitStepsProvider(widget.unitId));
      final completionsAsync = ref.read(unitStepCompletionsProvider(widget.unitId));

      final isUnitComplete = stepsAsync.value != null &&
          completionsAsync.value != null &&
          stepsAsync.value!.length == completionsAsync.value!.length;

      // Show confirmation dialog
      await showDialog(
        context: context,
        builder: (context) => CompletionConfirmation(
          isUnitComplete: isUnitComplete,
          onPrintLabel: () {
            Navigator.of(context).pop(); // Close confirmation
            _printLabel(context, ref);
          },
          onClose: () => Navigator.of(context).pop(),
        ),
      );
    }
  }
}
