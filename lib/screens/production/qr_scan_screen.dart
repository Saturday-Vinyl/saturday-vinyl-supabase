import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/repositories/production_unit_repository.dart';
import 'package:saturday_app/screens/production/unit_detail_screen.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/production/qr_scanner_desktop.dart';
import 'package:saturday_app/widgets/production/qr_scanner_mobile.dart';

/// QR scan screen - detects platform and shows appropriate scanner
class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key});

  @override
  State<QRScanScreen> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  final _unitRepository = ProductionUnitRepository();

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

  Future<void> _navigateToUnit(BuildContext context, String uuid) async {
    try {
      AppLogger.info('Looking up unit by UUID: $uuid');

      // Fetch unit to get primary key id
      final unit = await _unitRepository.getUnitByUuid(uuid);

      if (!context.mounted) return;

      // Pop the scan screen and navigate to unit detail
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => UnitDetailScreen(unitId: unit.id),
        ),
      );

      AppLogger.info('Navigated to unit detail: ${unit.unitId}');
    } catch (e) {
      AppLogger.error('Failed to navigate to unit', e, StackTrace.current);

      if (!context.mounted) return;

      // Show error and pop back
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unit not found: $e'),
          backgroundColor: SaturdayColors.error,
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pop(context);
    }
  }
}
