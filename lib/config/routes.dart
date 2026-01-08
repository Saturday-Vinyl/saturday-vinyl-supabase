import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:saturday_consumer_app/providers/intro_splash_provider.dart';
import 'package:saturday_consumer_app/screens/auth/forgot_password_screen.dart';
import 'package:saturday_consumer_app/screens/auth/login_screen.dart';
import 'package:saturday_consumer_app/screens/auth/signup_screen.dart';
import 'package:saturday_consumer_app/screens/intro/intro_splash_screen.dart';
import 'package:saturday_consumer_app/screens/now_playing/now_playing_screen.dart';
import 'package:saturday_consumer_app/screens/now_playing/set_now_playing_screen.dart';
import 'package:saturday_consumer_app/screens/library/library_screen.dart';
import 'package:saturday_consumer_app/screens/library/album_detail_screen.dart';
import 'package:saturday_consumer_app/screens/library/discogs_search_screen.dart';
import 'package:saturday_consumer_app/screens/library/barcode_scanner_screen.dart';
import 'package:saturday_consumer_app/screens/library/confirm_album_screen.dart';
import 'package:saturday_consumer_app/screens/library/tag_association_screen.dart';
import 'package:saturday_consumer_app/screens/library/create_library_screen.dart';
import 'package:saturday_consumer_app/screens/account/account_screen.dart';
import 'package:saturday_consumer_app/screens/account/device_list_screen.dart';
import 'package:saturday_consumer_app/screens/account/device_detail_screen.dart';
import 'package:saturday_consumer_app/screens/account/device_setup_screen.dart';
import 'package:saturday_consumer_app/screens/onboarding/quick_start_screen.dart';
import 'package:saturday_consumer_app/screens/onboarding/add_album_intro_screen.dart';
import 'package:saturday_consumer_app/screens/search/search_screen.dart';
import 'package:saturday_consumer_app/widgets/common/scaffold_with_nav.dart';

/// Route paths for the app.
class RoutePaths {
  RoutePaths._();

  // Intro route
  static const String introSplash = '/intro-splash';

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
  static const String addAlbum = 'add';
  static const String addAlbumScan = 'add/scan';
  static const String addAlbumSearch = 'add/search';
  static const String addAlbumConfirm = 'add/confirm';
  static const String tagAssociation = 'album/:id/tag';
  static const String createLibrary = 'create';
  static const String deviceList = 'devices';
  static const String deviceDetail = 'devices/:id';
  static const String deviceSetup = 'devices/setup';
  static const String settings = 'settings';
  static const String search = '/search';

  // Now Playing nested routes
  static const String setNowPlaying = 'set';

  // Onboarding routes
  static const String onboardingQuickStart = '/onboarding/quick-start';
  static const String onboardingAddAlbumIntro = '/onboarding/add-album-intro';
}

/// Route names for named navigation.
class RouteNames {
  RouteNames._();

  static const String introSplash = 'intro-splash';
  static const String login = 'login';
  static const String signup = 'signup';
  static const String forgotPassword = 'forgot-password';
  static const String nowPlaying = 'now-playing';
  static const String library = 'library';
  static const String account = 'account';
  static const String albumDetails = 'album-details';
  static const String addAlbum = 'add-album';
  static const String addAlbumScan = 'add-album-scan';
  static const String addAlbumSearch = 'add-album-search';
  static const String addAlbumConfirm = 'add-album-confirm';
  static const String tagAssociation = 'tag-association';
  static const String createLibrary = 'create-library';
  static const String deviceList = 'device-list';
  static const String deviceDetail = 'device-detail';
  static const String deviceSetup = 'device-setup';
  static const String settings = 'settings';
  static const String search = 'search';
  static const String setNowPlaying = 'set-now-playing';
  static const String onboardingQuickStart = 'onboarding-quick-start';
  static const String onboardingAddAlbumIntro = 'onboarding-add-album-intro';
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
      // Intro splash route (outside shell)
      GoRoute(
        path: RoutePaths.introSplash,
        name: RouteNames.introSplash,
        builder: (context, state) => const IntroSplashScreen(),
      ),

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

      // Onboarding routes (outside shell)
      GoRoute(
        path: RoutePaths.onboardingQuickStart,
        name: RouteNames.onboardingQuickStart,
        builder: (context, state) => const QuickStartScreen(),
      ),
      GoRoute(
        path: RoutePaths.onboardingAddAlbumIntro,
        name: RouteNames.onboardingAddAlbumIntro,
        builder: (context, state) => const AddAlbumIntroScreen(),
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
            routes: [
              // Set now playing screen
              GoRoute(
                path: RoutePaths.setNowPlaying,
                name: RouteNames.setNowPlaying,
                builder: (context, state) => const SetNowPlayingScreen(),
              ),
            ],
          ),

          // Library tab
          GoRoute(
            path: RoutePaths.library,
            name: RouteNames.library,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: LibraryScreen(),
            ),
            routes: [
              // Album detail (nested under library, uses root navigator for fullscreen)
              GoRoute(
                path: RoutePaths.albumDetails,
                name: RouteNames.albumDetails,
                parentNavigatorKey: rootNavigatorKey,
                builder: (context, state) {
                  final albumId = state.pathParameters['id']!;
                  return AlbumDetailScreen(libraryAlbumId: albumId);
                },
              ),
              // Add album flow - camera scanner (uses root navigator for fullscreen)
              GoRoute(
                path: RoutePaths.addAlbumScan,
                name: RouteNames.addAlbumScan,
                parentNavigatorKey: rootNavigatorKey,
                builder: (context, state) => const BarcodeScannerScreen(),
              ),
              GoRoute(
                path: RoutePaths.addAlbumSearch,
                name: RouteNames.addAlbumSearch,
                builder: (context, state) => const DiscogsSearchScreen(),
              ),
              GoRoute(
                path: RoutePaths.addAlbumConfirm,
                name: RouteNames.addAlbumConfirm,
                parentNavigatorKey: rootNavigatorKey,
                builder: (context, state) => const ConfirmAlbumScreen(),
              ),
              // Tag association (uses root navigator for fullscreen camera)
              GoRoute(
                path: RoutePaths.tagAssociation,
                name: RouteNames.tagAssociation,
                parentNavigatorKey: rootNavigatorKey,
                builder: (context, state) {
                  final albumId = state.pathParameters['id']!;
                  return TagAssociationScreen(libraryAlbumId: albumId);
                },
              ),
              // Create library
              GoRoute(
                path: RoutePaths.createLibrary,
                name: RouteNames.createLibrary,
                builder: (context, state) => const CreateLibraryScreen(),
              ),
            ],
          ),

          // Account tab
          GoRoute(
            path: RoutePaths.account,
            name: RouteNames.account,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: AccountScreen(),
            ),
            routes: [
              // Device list
              GoRoute(
                path: RoutePaths.deviceList,
                name: RouteNames.deviceList,
                builder: (context, state) => const DeviceListScreen(),
              ),
              // Device setup (uses root navigator for fullscreen)
              // NOTE: Must come before deviceDetail to avoid :id matching "setup"
              GoRoute(
                path: RoutePaths.deviceSetup,
                name: RouteNames.deviceSetup,
                parentNavigatorKey: rootNavigatorKey,
                builder: (context, state) => const DeviceSetupScreen(),
              ),
              // Device detail
              GoRoute(
                path: RoutePaths.deviceDetail,
                name: RouteNames.deviceDetail,
                parentNavigatorKey: rootNavigatorKey,
                builder: (context, state) {
                  final deviceId = state.pathParameters['id']!;
                  return DeviceDetailScreen(deviceId: deviceId);
                },
              ),
            ],
          ),
        ],
      ),

      // Search route (full screen overlay)
      GoRoute(
        path: RoutePaths.search,
        name: RouteNames.search,
        builder: (context, state) => const SearchScreen(),
      ),
    ],

    // Redirect logic for auth and intro splash
    redirect: (context, state) {
      final matchedLocation = state.matchedLocation;
      final isAuthRoute = _authRoutes.contains(matchedLocation);
      final isIntroSplashRoute = matchedLocation == RoutePaths.introSplash;

      // Check if intro splash should be shown
      final shouldShowSplash = ref.read(introSplashNotifierProvider);

      // If splash should be shown and we're not already on splash route,
      // redirect to splash (but not from auth routes)
      if (shouldShowSplash && !isIntroSplashRoute && !isAuthRoute) {
        return RoutePaths.introSplash;
      }

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
