import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/screens/production/unit_detail_screen.dart';
import 'package:saturday_app/widgets/production/qr_scanner_desktop.dart';
import 'package:saturday_app/widgets/production/qr_scanner_mobile.dart';

/// QR scan screen - detects platform and shows appropriate scanner
class QRScanScreen extends StatelessWidget {
  const QRScanScreen({super.key});

  bool get _isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _isDesktop =>
      kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isMobile ? Colors.black : null,
      appBar: _isDesktop
          ? AppBar(
              title: const Text('Scan QR Code'),
              backgroundColor: SaturdayColors.primaryDark,
              foregroundColor: Colors.white,
            )
          : null,
      body: _isMobile
          ? QRScannerMobile(
              onScanned: (uuid) => _navigateToUnit(context, uuid),
              onCancel: () => Navigator.pop(context),
            )
          : QRScannerDesktop(
              onScanned: (uuid) => _navigateToUnit(context, uuid),
              onCancel: () => Navigator.pop(context),
            ),
    );
  }

  void _navigateToUnit(BuildContext context, String uuid) {
    // Pop the scan screen and navigate to unit detail
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => UnitDetailScreen(unitId: uuid),
      ),
    );
  }
}
