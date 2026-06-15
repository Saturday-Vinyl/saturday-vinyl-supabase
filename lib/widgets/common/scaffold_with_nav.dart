import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
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
    final colors = SaturdayColorTokens.of(context);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) =>
                _onDestinationSelected(context, index),
            labelType: NavigationRailLabelType.all,
            backgroundColor: colors.paperElevated,
            indicatorColor: colors.borderQuiet,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.album_outlined),
                selectedIcon: Icon(Icons.album),
                label: Text('Archive'),
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
    final colors = SaturdayColorTokens.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.paperElevated,
        border: Border(
          top: BorderSide(color: colors.borderQuiet),
        ),
      ),
      child: SafeArea(
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) => _onItemTapped(context, index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.album_outlined),
              selectedIcon: Icon(Icons.album),
              label: 'Archive',
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
