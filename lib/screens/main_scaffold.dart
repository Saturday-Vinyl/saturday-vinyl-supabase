import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
// USB monitoring imports - re-enable when firmware responds to get_status
// import 'package:saturday_app/models/connected_device.dart';
// import 'package:saturday_app/providers/device_communication_provider.dart';
// import 'package:saturday_app/widgets/device_communication/usb_device_indicator.dart';
// import 'package:saturday_app/screens/units/unit_detail_screen.dart' as new_unit;
// import 'package:saturday_app/repositories/unit_repository.dart';
import 'package:saturday_app/repositories/unit_repository.dart';
import 'package:saturday_app/screens/dashboard/dashboard_screen.dart';
import 'package:saturday_app/screens/device_communication/device_communication_screen.dart';
import 'package:saturday_app/screens/device_types/device_type_list_screen.dart';
import 'package:saturday_app/screens/files/files_screen.dart';
import 'package:saturday_app/screens/products/product_list_screen.dart';
import 'package:saturday_app/screens/production/production_units_screen.dart';
import 'package:saturday_app/screens/production/qr_scan_screen.dart';
import 'package:saturday_app/screens/production/unit_detail_screen.dart';
import 'package:saturday_app/screens/units/units_list_screen.dart';
import 'package:saturday_app/screens/capabilities/capabilities_list_screen.dart';
import 'package:saturday_app/screens/settings/settings_screen.dart';
import 'package:saturday_app/screens/tags/tag_list_screen.dart';
import 'package:saturday_app/screens/rolls/roll_list_screen.dart';
import 'package:saturday_app/screens/users/user_management_screen.dart';
import 'package:saturday_app/services/keyboard_listener_service.dart';
import 'package:saturday_app/services/qr_scanner_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:saturday_app/widgets/navigation/sidebar_nav.dart';
import 'package:saturday_app/widgets/production/qr_fab_button.dart';

/// Main app scaffold with sidebar navigation
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  String _currentRoute = '/dashboard';
  KeyboardListenerService? _keyboardListener;
  final _qrScannerService = QRScannerService();
  final _unitRepository = UnitRepository();

  // USB monitoring - re-enable when firmware responds to get_status
  // final _newUnitRepository = UnitRepository();
  // bool _usbMonitorInitialized = false;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();

    // Initialize keyboard listener for desktop platforms
    if (_isDesktop) {
      _initializeKeyboardListener();
    }

    // NOTE: USB monitoring disabled for debugging
    // Re-enable once firmware responds correctly to get_status command
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (_isDesktop && !_usbMonitorInitialized) {
    //     _initializeUSBMonitoring();
    //     _usbMonitorInitialized = true;
    //   }
    // });
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
    // USB monitor cleanup is handled by Riverpod provider disposal
    super.dispose();
  }

  // USB monitoring - re-enable when firmware responds to get_status
  // void _initializeUSBMonitoring() {
  //   ref.read(usbMonitorProvider.notifier).startMonitoring();
  //   AppLogger.info('USB device monitoring initialized');
  // }

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

      // Verify unit exists before navigating (QR now encodes unit.id directly)
      AppLogger.info('Verifying unit exists: $uuid');
      final unit = await _unitRepository.getUnitById(uuid);

      if (!mounted) return;

      // Navigate to unit detail (use primary key id, not QR uuid)
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => UnitDetailScreen(unitId: unit.id),
        ),
      );

      AppLogger.info('Navigated to unit detail: ${unit.serialNumber}');
    } catch (e) {
      AppLogger.error('Failed to process scanned data', e, StackTrace.current);

      if (!mounted) return;

      // Determine error type and show appropriate message
      String errorMessage;
      if (e.toString().contains('PGRST116') || e.toString().contains('0 rows')) {
        errorMessage = 'Unit not found. This QR code may be invalid or the unit may have been deleted.';
      } else if (e.toString().contains('Invalid QR') || e.toString().contains('FormatException')) {
        errorMessage = 'Invalid QR code format. Please scan a valid production unit QR code.';
      } else {
        errorMessage = 'Error scanning QR code: ${e.toString()}';
      }

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: SaturdayColors.error,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
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
      case '/units':
        return const UnitsListScreen();
      case '/capabilities':
        return const CapabilitiesListScreen();
      case '/production':
        return const ProductionUnitsScreen();
      case '/device-communication':
        return const DeviceCommunicationScreen();
      case '/files':
        return const FilesScreen();
      case '/tags':
        return const TagListScreen();
      case '/rolls':
        return const RollListScreen();
      case '/settings':
        return const SettingsScreen();
      default:
        return const DashboardScreen();
    }
  }

  // USB indicator callbacks - re-enable when firmware responds to get_status
  // /// Navigate to unit detail screen by serial number
  // Future<void> _navigateToUnit(String serialNumber) async {
  //   try {
  //     final unit = await _newUnitRepository.getUnitBySerialNumber(serialNumber);
  //     if (unit != null && mounted) {
  //       Navigator.of(context).push(
  //         MaterialPageRoute(
  //           builder: (context) => new_unit.UnitDetailScreen(unitId: unit.id),
  //         ),
  //       );
  //     } else {
  //       if (mounted) {
  //         ScaffoldMessenger.of(context).showSnackBar(
  //           SnackBar(
  //             content: Text('Unit $serialNumber not found'),
  //             backgroundColor: SaturdayColors.error,
  //           ),
  //         );
  //       }
  //     }
  //   } catch (e) {
  //     AppLogger.error('Failed to navigate to unit', e);
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Error: $e'),
  //           backgroundColor: SaturdayColors.error,
  //         ),
  //       );
  //     }
  //   }
  // }
  //
  // /// Open device communication screen for a device
  // void _openDeviceCommunication(ConnectedDevice device) {
  //   Navigator.of(context).push(
  //     MaterialPageRoute(
  //       builder: (context) => DeviceCommunicationScreen(initialDevice: device),
  //     ),
  //   );
  // }
  //
  // /// Open provisioning flow for an unprovisioned device
  // void _openProvisioningFlow(ConnectedDevice device) {
  //   // For now, just open the device communication screen
  //   // A dedicated provisioning flow can be added later
  //   Navigator.of(context).push(
  //     MaterialPageRoute(
  //       builder: (context) => DeviceCommunicationScreen(initialDevice: device),
  //     ),
  //   );
  // }

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
