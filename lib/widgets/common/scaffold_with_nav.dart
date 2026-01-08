import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/widgets/common/adaptive_layout.dart';

/// Main scaffold with bottom navigation bar.
///
/// This widget wraps all main screens and provides consistent
/// navigation between the three main tabs: Now Playing, Library, and Account.
///
/// On tablets in landscape, may use a navigation rail instead of bottom bar.
class ScaffoldWithNav extends StatelessWidget {
  final Widget child;

  const ScaffoldWithNav({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final useNavigationRail = AdaptiveLayout.shouldShowDualPane(context);

    if (useNavigationRail) {
      return _TabletScaffold(child: child);
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: const SaturdayBottomNav(),
    );
  }
}

/// Tablet-optimized scaffold with navigation rail.
class _TabletScaffold extends StatelessWidget {
  final Widget child;

  const _TabletScaffold({required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(RoutePaths.nowPlaying)) return 0;
    if (location.startsWith(RoutePaths.library)) return 1;
    if (location.startsWith(RoutePaths.account)) return 2;
    return 0;
  }

  void _onDestinationSelected(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(RoutePaths.nowPlaying);
        break;
      case 1:
        context.go(RoutePaths.library);
        break;
      case 2:
        context.go(RoutePaths.account);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) =>
                _onDestinationSelected(context, index),
            labelType: NavigationRailLabelType.all,
            backgroundColor: SaturdayColors.white,
            indicatorColor: SaturdayColors.light,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle_filled),
                label: Text('Now Playing'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.album_outlined),
                selectedIcon: Icon(Icons.album),
                label: Text('Library'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: Text('Account'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Bottom navigation bar for the Saturday app.
class SaturdayBottomNav extends StatelessWidget {
  const SaturdayBottomNav({super.key});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith(RoutePaths.nowPlaying)) return 0;
    if (location.startsWith(RoutePaths.library)) return 1;
    if (location.startsWith(RoutePaths.account)) return 2;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(RoutePaths.nowPlaying);
        break;
      case 1:
        context.go(RoutePaths.library);
        break;
      case 2:
        context.go(RoutePaths.account);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Container(
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        boxShadow: [
          BoxShadow(
            color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) => _onItemTapped(context, index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.play_circle_outline),
              selectedIcon: Icon(Icons.play_circle_filled),
              label: 'Now Playing',
            ),
            NavigationDestination(
              icon: Icon(Icons.album_outlined),
              selectedIcon: Icon(Icons.album),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
