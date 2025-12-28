import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/screens/auth/login_screen.dart';
import 'package:saturday_consumer_app/screens/now_playing/now_playing_screen.dart';
import 'package:saturday_consumer_app/screens/library/library_screen.dart';
import 'package:saturday_consumer_app/screens/account/account_screen.dart';
import 'package:saturday_consumer_app/widgets/common/scaffold_with_nav.dart';

/// Route paths for the app.
class RoutePaths {
  RoutePaths._();

  // Auth routes
  static const String login = '/login';
  static const String signup = '/signup';

  // Main tab routes
  static const String nowPlaying = '/now-playing';
  static const String library = '/library';
  static const String account = '/account';

  // Nested routes
  static const String albumDetails = 'album/:id';
  static const String deviceSetup = 'device-setup';
  static const String settings = 'settings';
  static const String search = '/search';
}

/// Route names for named navigation.
class RouteNames {
  RouteNames._();

  static const String login = 'login';
  static const String signup = 'signup';
  static const String nowPlaying = 'now-playing';
  static const String library = 'library';
  static const String account = 'account';
  static const String albumDetails = 'album-details';
  static const String deviceSetup = 'device-setup';
  static const String settings = 'settings';
  static const String search = 'search';
}

/// Global navigator key for accessing navigation from anywhere.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Shell navigator key for bottom navigation.
final GlobalKey<NavigatorState> shellNavigatorKey = GlobalKey<NavigatorState>();

/// App router configuration using go_router.
final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: RoutePaths.nowPlaying,
  debugLogDiagnostics: true,
  routes: [
    // Auth routes (outside shell)
    GoRoute(
      path: RoutePaths.login,
      name: RouteNames.login,
      builder: (context, state) => const LoginScreen(),
    ),

    // Main app shell with bottom navigation
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (context, state, child) => ScaffoldWithNav(child: child),
      routes: [
        // Now Playing tab
        GoRoute(
          path: RoutePaths.nowPlaying,
          name: RouteNames.nowPlaying,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: NowPlayingScreen(),
          ),
        ),

        // Library tab
        GoRoute(
          path: RoutePaths.library,
          name: RouteNames.library,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LibraryScreen(),
          ),
        ),

        // Account tab
        GoRoute(
          path: RoutePaths.account,
          name: RouteNames.account,
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AccountScreen(),
          ),
        ),
      ],
    ),

    // Search route (full screen overlay)
    GoRoute(
      path: RoutePaths.search,
      name: RouteNames.search,
      builder: (context, state) => const Scaffold(
        body: Center(child: Text('Search - Coming Soon')),
      ),
    ),
  ],

  // Redirect logic for auth
  redirect: (context, state) {
    // TODO: Implement auth state check
    // final isLoggedIn = ref.read(authProvider).isLoggedIn;
    // final isLoginRoute = state.matchedLocation == RoutePaths.login;
    //
    // if (!isLoggedIn && !isLoginRoute) {
    //   return RoutePaths.login;
    // }
    // if (isLoggedIn && isLoginRoute) {
    //   return RoutePaths.nowPlaying;
    // }
    return null;
  },

  // Error page
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 16),
          Text('Page not found: ${state.uri.path}'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.go(RoutePaths.nowPlaying),
            child: const Text('Go Home'),
          ),
        ],
      ),
    ),
  ),
);
