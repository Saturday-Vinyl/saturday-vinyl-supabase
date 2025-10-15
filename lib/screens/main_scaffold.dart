import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/screens/dashboard/dashboard_screen.dart';
import 'package:saturday_app/screens/device_types/device_type_list_screen.dart';
import 'package:saturday_app/screens/firmware/firmware_list_screen.dart';
import 'package:saturday_app/screens/products/product_list_screen.dart';
import 'package:saturday_app/screens/production/production_units_screen.dart';
import 'package:saturday_app/screens/production/qr_scan_screen.dart';
import 'package:saturday_app/screens/production/unit_detail_screen.dart';
import 'package:saturday_app/screens/settings/settings_screen.dart';
import 'package:saturday_app/screens/users/user_management_screen.dart';
import 'package:saturday_app/services/keyboard_listener_service.dart';
import 'package:saturday_app/services/qr_scanner_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/navigation/sidebar_nav.dart';
import 'package:saturday_app/widgets/production/qr_fab_button.dart';

/// Main app scaffold with sidebar navigation
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  String _currentRoute = '/dashboard';
  KeyboardListenerService? _keyboardListener;
  final _qrScannerService = QRScannerService();

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();

    // Initialize keyboard listener for desktop platforms
    if (_isDesktop) {
      _initializeKeyboardListener();
    }
  }

  @override
  void dispose() {
    // Clean up keyboard listener
    if (_keyboardListener != null) {
      ServicesBinding.instance.keyboard.removeHandler(
        _keyboardListener!.handleKeyEvent,
      );
      _keyboardListener!.dispose();
    }
    super.dispose();
  }

  void _initializeKeyboardListener() {
    _keyboardListener = KeyboardListenerService()
      ..onScanDetected = _handleScannedData
      ..onManualShortcut = _openQRScanner;

    ServicesBinding.instance.keyboard.addHandler(
      _keyboardListener!.handleKeyEvent,
    );

    AppLogger.info('Keyboard listener initialized for QR scanning');
  }

  void _navigateTo(String route) {
    setState(() {
      _currentRoute = route;
    });
  }

  /// Handle scanned data from USB scanner
  Future<void> _handleScannedData(String scannedData) async {
    try {
      AppLogger.info('Processing scanned data: $scannedData');
      final uuid = await _qrScannerService.processScannedCode(scannedData);

      if (!mounted) return;

      // Navigate directly to unit detail
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => UnitDetailScreen(unitId: uuid),
        ),
      );

      AppLogger.info('Navigated to unit detail: $uuid');
    } catch (e) {
      AppLogger.error('Failed to process scanned data', e, StackTrace.current);

      if (!mounted) return;

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid QR code: $e'),
          backgroundColor: SaturdayColors.error,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Open QR scan screen (manual keyboard shortcut)
  void _openQRScanner() {
    AppLogger.info('Opening QR scan screen via keyboard shortcut');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const QRScanScreen(),
      ),
    );
  }

  Widget _getCurrentScreen() {
    switch (_currentRoute) {
      case '/dashboard':
        return const DashboardScreen();
      case '/users':
        return const UserManagementScreen();
      case '/products':
        return const ProductListScreen();
      case '/device-types':
        return const DeviceTypeListScreen();
      case '/production':
        return const ProductionUnitsScreen();
      case '/firmware':
        return const FirmwareListScreen();
      case '/settings':
        return const SettingsScreen();
      default:
        return const DashboardScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar navigation
          SidebarNav(
            currentRoute: _currentRoute,
            onNavigate: _navigateTo,
          ),

          // Main content area
          Expanded(
            child: _getCurrentScreen(),
          ),
        ],
      ),
      // Global FAB for QR scanning
      floatingActionButton: QRFABButton(
        onPressed: _openQRScanner,
      ),
    );
  }
}
