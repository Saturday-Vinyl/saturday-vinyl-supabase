import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:saturday_consumer_app/screens/auth/forgot_password_screen.dart';
import 'package:saturday_consumer_app/screens/auth/login_screen.dart';
import 'package:saturday_consumer_app/screens/auth/signup_screen.dart';
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
  static const String forgotPassword = '/forgot-password';

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
  static const String forgotPassword = 'forgot-password';
  static const String nowPlaying = 'now-playing';
  static const String library = 'library';
  static const String account = 'account';
  static const String albumDetails = 'album-details';
  static const String deviceSetup = 'device-setup';
  static const String settings = 'settings';
  static const String search = 'search';
}

/// Auth routes that don't require authentication.
const _authRoutes = [
  RoutePaths.login,
  RoutePaths.signup,
  RoutePaths.forgotPassword,
];

/// Global navigator key for accessing navigation from anywhere.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Shell navigator key for bottom navigation.
final GlobalKey<NavigatorState> shellNavigatorKey = GlobalKey<NavigatorState>();

/// Creates the app router with auth state from Riverpod.
///
/// This function creates a GoRouter that can access Riverpod providers
/// for auth state checking in redirects.
GoRouter createAppRouter(Ref ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RoutePaths.nowPlaying,
    debugLogDiagnostics: true,

    // Refresh router when auth state changes
    refreshListenable: GoRouterRefreshStream(
      ref.read(supabaseServiceProvider).authStateChanges,
    ),

    routes: [
      // Auth routes (outside shell)
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.signup,
        name: RouteNames.signup,
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        name: RouteNames.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
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
      final isAuthRoute = _authRoutes.contains(state.matchedLocation);

      // Get auth state synchronously from the service
      final supabaseService = ref.read(supabaseServiceProvider);
      final isLoggedIn = supabaseService.isAuthenticated;

      // If logged in and trying to access auth routes, redirect to home
      if (isLoggedIn && isAuthRoute) {
        return RoutePaths.nowPlaying;
      }

      // For now, allow access to main app without auth (guest mode)
      // This can be changed to require auth by uncommenting:
      // if (!isLoggedIn && !isAuthRoute) {
      //   return RoutePaths.login;
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
}

/// A [Listenable] that notifies when a [Stream] emits.
///
/// Used to refresh the router when auth state changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final dynamic _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Provider for the app router.
///
/// This allows the router to access auth state from Riverpod.
final appRouterProvider = Provider<GoRouter>((ref) {
  return createAppRouter(ref);
});
