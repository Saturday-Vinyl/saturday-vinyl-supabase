import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';

/// Confirmation dialog shown after completing a step
class CompletionConfirmation extends StatelessWidget {
  final bool isUnitComplete;
  final VoidCallback? onScanNext;
  final VoidCallback? onPrintLabel;
  final VoidCallback? onClose;

  const CompletionConfirmation({
    super.key,
    required this.isUnitComplete,
    this.onScanNext,
    this.onPrintLabel,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Success icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: SaturdayColors.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isUnitComplete ? Icons.celebration : Icons.check_circle,
                size: 48,
                color: SaturdayColors.success,
              ),
            ),

            const SizedBox(height: 24),

            // Title
            Text(
              isUnitComplete ? 'Unit Complete! 🎉' : 'Step Completed!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: SaturdayColors.primaryDark,
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Message
            Text(
              isUnitComplete
                  ? 'All production steps are complete. This unit is ready for shipment!'
                  : 'Production step marked as complete.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Action buttons
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (onScanNext != null)
                  ElevatedButton.icon(
                    onPressed: onScanNext,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan Next Unit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaturdayColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                if (onScanNext != null && onPrintLabel != null)
                  const SizedBox(height: 12),
                if (onPrintLabel != null)
                  OutlinedButton.icon(
                    onPressed: onPrintLabel,
                    icon: const Icon(Icons.print),
                    label: const Text('Print Label'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SaturdayColors.primaryDark,
                      side: const BorderSide(color: SaturdayColors.secondaryGrey),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                if ((onScanNext != null || onPrintLabel != null) &&
                    onClose != null)
                  const SizedBox(height: 12),
                if (onClose != null)
                  TextButton(
                    onPressed: onClose,
                    child: const Text('Close'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
