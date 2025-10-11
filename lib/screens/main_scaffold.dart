import 'package:flutter/material.dart';
import 'package:saturday_app/screens/dashboard/dashboard_screen.dart';
import 'package:saturday_app/screens/device_types/device_type_list_screen.dart';
import 'package:saturday_app/screens/firmware/firmware_list_screen.dart';
import 'package:saturday_app/screens/products/product_list_screen.dart';
import 'package:saturday_app/screens/production/production_units_screen.dart';
import 'package:saturday_app/screens/settings/settings_screen.dart';
import 'package:saturday_app/screens/users/user_management_screen.dart';
import 'package:saturday_app/widgets/navigation/sidebar_nav.dart';

/// Main app scaffold with sidebar navigation
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  String _currentRoute = '/dashboard';

  void _navigateTo(String route) {
    setState(() {
      _currentRoute = route;
    });
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
    return Row(
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
    );
  }
}
