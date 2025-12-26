import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/screens/debug/scanner_debug_screen.dart';
import 'package:saturday_app/screens/production/qr_scan_screen.dart';
import 'package:saturday_app/services/keyboard_listener_service.dart';

/// Card for configuring USB barcode scanners with prefix characters
class ScannerConfigCard extends StatelessWidget {
  const ScannerConfigCard({super.key});

  // Placeholder QR code content (to be replaced with actual scanner programming codes)
  static const programmingModeQR = '[SCANNER_PROGRAMMING_MODE]';
  static const exitProgrammingQR = '[SCANNER_EXIT_PROGRAMMING_MODE]';

  @override
  Widget build(BuildContext context) {
    // Only show on desktop platforms
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.qr_code_scanner,
                  color: SaturdayColors.primaryDark,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Text(
                  'USB Scanner Configuration',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: SaturdayColors.primaryDark,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Explanation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SaturdayColors.info.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: SaturdayColors.info,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Configure your USB barcode scanner to work seamlessly with '
                      'Saturday! Admin. Scanning the EM barcode programs your scanner '
                      'to send F4 before each scan, allowing automatic detection. '
                      'Scan the QR codes below in sequence to program your scanner.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.info,
                          ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Step 1: Enter Programming Mode
            _buildStep(
              context: context,
              stepNumber: 1,
              title: 'Scan to Enter Programming Mode',
              qrData: programmingModeQR,
              helperText:
                  'This puts your scanner into programming mode. Check your '
                  'scanner\'s manual if this doesn\'t work.',
            ),

            const SizedBox(height: 24),

            // Step 2: Set Prefix Character
            _buildStep(
              context: context,
              stepNumber: 2,
              title: 'Scan to Set Prefix Key (EM → F4)',
              qrData: KeyboardListenerService.prefixChar,
              helperText:
                  'Scan the EM barcode. Your scanner will translate this to the F4 key, '
                  'which will be sent before each scan for automatic detection.',
            ),

            const SizedBox(height: 24),

            // Step 3: Exit Programming Mode
            _buildStep(
              context: context,
              stepNumber: 3,
              title: 'Scan to Exit Programming Mode (if needed)',
              qrData: exitProgrammingQR,
              helperText: 'Some scanners require this to save settings.',
            ),

            const SizedBox(height: 24),

            // Test Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openDebugScreen(context),
                  icon: const Icon(Icons.bug_report, size: 20),
                  label: const Text('Debug Scanner'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SaturdayColors.info,
                    side: BorderSide(color: SaturdayColors.info, width: 1.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () => _testScanner(context),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: const Text('Test Scanner'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SaturdayColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Build a configuration step
  Widget _buildStep({
    required BuildContext context,
    required int stepNumber,
    required String title,
    required String qrData,
    required String helperText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step number badge
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: SaturdayColors.primaryDark,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$stepNumber',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),

        const SizedBox(width: 16),

        // Content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: SaturdayColors.primaryDark,
                    ),
              ),

              const SizedBox(height: 8),

              // QR Code
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: SaturdayColors.secondaryGrey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 150,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
              ),

              const SizedBox(height: 8),

              // Helper text
              Text(
                helperText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.secondaryGrey,
                    ),
              ),

              const SizedBox(height: 8),

              // Copy button
              TextButton.icon(
                onPressed: () => _copyToClipboard(context, qrData),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy QR Data'),
                style: TextButton.styleFrom(
                  foregroundColor: SaturdayColors.info,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Copy QR data to clipboard
  void _copyToClipboard(BuildContext context, String data) {
    Clipboard.setData(ClipboardData(text: data));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard: $data'),
        backgroundColor: SaturdayColors.success,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Test scanner configuration
  void _testScanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const QRScanScreen(),
      ),
    );
  }

  /// Open debug screen to see raw scanner input
  void _openDebugScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ScannerDebugScreen(),
      ),
    );
  }
}
