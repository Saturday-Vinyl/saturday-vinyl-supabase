import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A reusable QR code scanner widget.
///
/// Provides a camera viewfinder with scanning frame overlay,
/// flash toggle, and detection callback.
class QrScanner extends StatefulWidget {
  const QrScanner({
    super.key,
    required this.onDetect,
    this.onError,
    this.showFlashToggle = true,
    this.scanningMessage = 'Point your camera at the QR code',
  });

  /// Callback when a QR code is detected.
  final void Function(String code) onDetect;

  /// Callback for scanner errors.
  final void Function(String error)? onError;

  /// Whether to show the flash toggle button.
  final bool showFlashToggle;

  /// Message to display below the scanning frame.
  final String scanningMessage;

  @override
  State<QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<QrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _hasDetected = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_hasDetected) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    // Only process QR codes
    if (barcode.format != BarcodeFormat.qrCode) return;

    setState(() => _hasDetected = true);
    _controller.stop();
    widget.onDetect(barcode.rawValue!);
  }

  /// Reset the scanner to allow a new scan.
  void reset() {
    setState(() => _hasDetected = false);
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Camera preview
        MobileScanner(
          controller: _controller,
          onDetect: _onBarcodeDetected,
          errorBuilder: (context, error, child) {
            return _buildErrorState(error.errorDetails?.message ?? 'Camera error');
          },
        ),

        // Scanning frame overlay
        _buildScanningOverlay(),

        // Flash toggle
        if (widget.showFlashToggle)
          Positioned(
            top: 16,
            right: 16,
            child: _buildFlashToggle(),
          ),

        // Instructions
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _buildInstructions(),
        ),
      ],
    );
  }

  Widget _buildScanningOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scanAreaSize = constraints.maxWidth * 0.6;
        final scanAreaTop = (constraints.maxHeight - scanAreaSize) / 2 - 50;

        return Stack(
          children: [
            // Dark overlay with cutout
            ColorFiltered(
              colorFilter: const ColorFilter.mode(
                Colors.black54,
                BlendMode.srcOut,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    top: scanAreaTop,
                    left: (constraints.maxWidth - scanAreaSize) / 2,
                    child: Container(
                      width: scanAreaSize,
                      height: scanAreaSize,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scan area border with corners
            Positioned(
              top: scanAreaTop,
              left: (constraints.maxWidth - scanAreaSize) / 2,
              child: _buildScanFrame(scanAreaSize),
            ),
          ],
        );
      },
    );
  }

  Widget _buildScanFrame(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ScanFramePainter(
          color: SaturdayColors.primaryDark,
          cornerLength: 32,
          cornerWidth: 4,
        ),
      ),
    );
  }

  Widget _buildFlashToggle() {
    return ValueListenableBuilder(
      valueListenable: _controller,
      builder: (context, state, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(24),
          ),
          child: IconButton(
            icon: Icon(
              state.torchState == TorchState.on
                  ? Icons.flash_on
                  : Icons.flash_off,
              color: Colors.white,
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        );
      },
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(Spacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.scanningMessage,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: SaturdayColors.error,
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'Camera Error',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the scanning frame corners.
class _ScanFramePainter extends CustomPainter {
  _ScanFramePainter({
    required this.color,
    required this.cornerLength,
    required this.cornerWidth,
  });

  final Color color;
  final double cornerLength;
  final double cornerWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = cornerWidth
      ..strokeCap = StrokeCap.round;

    final radius = 16.0;

    // Top-left corner
    final topLeftPath = Path()
      ..moveTo(0, cornerLength)
      ..lineTo(0, radius)
      ..arcToPoint(
        Offset(radius, 0),
        radius: Radius.circular(radius),
      )
      ..lineTo(cornerLength, 0);
    canvas.drawPath(topLeftPath, paint);

    // Top-right corner
    final topRightPath = Path()
      ..moveTo(size.width - cornerLength, 0)
      ..lineTo(size.width - radius, 0)
      ..arcToPoint(
        Offset(size.width, radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(size.width, cornerLength);
    canvas.drawPath(topRightPath, paint);

    // Bottom-left corner
    final bottomLeftPath = Path()
      ..moveTo(0, size.height - cornerLength)
      ..lineTo(0, size.height - radius)
      ..arcToPoint(
        Offset(radius, size.height),
        radius: Radius.circular(radius),
      )
      ..lineTo(cornerLength, size.height);
    canvas.drawPath(bottomLeftPath, paint);

    // Bottom-right corner
    final bottomRightPath = Path()
      ..moveTo(size.width - cornerLength, size.height)
      ..lineTo(size.width - radius, size.height)
      ..arcToPoint(
        Offset(size.width, size.height - radius),
        radius: Radius.circular(radius),
      )
      ..lineTo(size.width, size.height - cornerLength);
    canvas.drawPath(bottomRightPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
