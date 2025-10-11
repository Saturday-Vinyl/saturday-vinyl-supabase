import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/services/qr_scanner_service.dart';

/// Mobile QR scanner widget - uses device camera
class QRScannerMobile extends StatefulWidget {
  final Function(String uuid) onScanned;
  final VoidCallback? onCancel;

  const QRScannerMobile({
    super.key,
    required this.onScanned,
    this.onCancel,
  });

  @override
  State<QRScannerMobile> createState() => _QRScannerMobileState();
}

class _QRScannerMobileState extends State<QRScannerMobile> {
  final _scannerService = QRScannerService();
  final _controller = MobileScannerController();
  bool _isProcessing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleBarcode(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final scannedText = barcode.rawValue!;
      final uuid = await _scannerService.processScannedCode(scannedText);

      if (mounted) {
        widget.onScanned(uuid);
      }
    } catch (error) {
      setState(() {
        _errorMessage = 'Invalid QR code';
        _isProcessing = false;
      });

      // Reset after showing error
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Camera view
        MobileScanner(
          controller: _controller,
          onDetect: _handleBarcode,
        ),

        // Overlay with scanning frame
        _buildOverlay(context),

        // Top bar with close and flash buttons
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Close button
                if (widget.onCancel != null)
                  IconButton(
                    onPressed: widget.onCancel,
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      foregroundColor: Colors.white,
                    ),
                  ),

                const Spacer(),

                // Flash toggle button
                IconButton(
                  onPressed: () => _controller.toggleTorch(),
                  icon: const Icon(Icons.flash_on),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Error message
        if (_errorMessage != null)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: SaturdayColors.error,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),

        // Processing indicator
        if (_isProcessing)
          Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
      ),
      child: Stack(
        children: [
          // Transparent center square
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: SaturdayColors.success,
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
          ),

          // Instructions
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Position QR code in the center to scan',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
