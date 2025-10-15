import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';

/// Floating Action Button for global QR code scanning
class QRFABButton extends StatelessWidget {
  final VoidCallback onPressed;

  const QRFABButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: 'Scan QR Code (Ctrl+Shift+Q)',
      backgroundColor: SaturdayColors.primaryDark,
      foregroundColor: Colors.white,
      elevation: 6,
      child: const Icon(
        Icons.qr_code_scanner,
        size: 28,
      ),
    );
  }
}
