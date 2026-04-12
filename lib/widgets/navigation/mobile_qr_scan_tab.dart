import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/repositories/unit_repository.dart';
import 'package:saturday_app/screens/production/unit_detail_screen.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/production/qr_scanner_mobile.dart';

/// Embedded QR scanner tab for mobile bottom navigation.
///
/// Unlike [QRScanScreen], this widget does not wrap itself in a [Scaffold] —
/// it is meant to live inside the mobile shell's [IndexedStack]. Accepts an
/// [isActive] flag to pause/resume the camera when the tab is off-screen.
class MobileQRScanTab extends StatefulWidget {
  final bool isActive;

  const MobileQRScanTab({
    super.key,
    required this.isActive,
  });

  @override
  State<MobileQRScanTab> createState() => _MobileQRScanTabState();
}

class _MobileQRScanTabState extends State<MobileQRScanTab> {
  final _unitRepository = UnitRepository();
  bool _isNavigating = false;

  Future<void> _handleScanned(String uuid) async {
    if (_isNavigating) return;
    _isNavigating = true;

    try {
      AppLogger.info('Mobile scan tab: looking up unit $uuid');
      final unit = await _unitRepository.getUnitById(uuid);

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => UnitDetailScreen(unitId: unit.id),
        ),
      );

      // Reset after returning from unit detail so scanning can resume
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    } catch (e) {
      AppLogger.error('Mobile scan tab: failed to look up unit', e, StackTrace.current);

      if (!mounted) return;

      String errorMessage;
      if (e.toString().contains('PGRST116') || e.toString().contains('0 rows')) {
        errorMessage = 'Unit not found. QR code may be invalid.';
      } else {
        errorMessage = 'Error looking up unit: $e';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: SaturdayColors.error,
          duration: const Duration(seconds: 3),
        ),
      );

      setState(() {
        _isNavigating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      // Show a placeholder when the tab is not visible so the camera is not
      // running in the background (QRScannerMobile starts the camera on init).
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Icon(
            Icons.qr_code_scanner,
            color: SaturdayColors.secondaryGrey,
            size: 64,
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: QRScannerMobile(
        onScanned: _handleScanned,
        // No onCancel — the scanner tab is persistent, not dismissable
      ),
    );
  }
}
