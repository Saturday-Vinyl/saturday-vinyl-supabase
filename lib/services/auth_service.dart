import 'package:saturday_app/config/constants.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Authentication service for Google OAuth via Supabase.
///
/// Uses Supabase's `signInWithOAuth` which opens the user's default browser,
/// handles the Google handshake server-side, and redirects back to
/// `saturday://login-callback`. The deep link is routed to Supabase via
/// `DeepLinkService`, which resolves the session.
class AuthService {
  AuthService._();

  static AuthService? _instance;
  static AuthService get instance => _instance ??= AuthService._();

  /// Sign in with Google via Supabase OAuth.
  ///
  /// Opens the browser for the OAuth handshake, then awaits the session that
  /// arrives via the `saturday://login-callback` deep link. Enforces the
  /// `@saturdayvinyl.com` email domain — signs the user out and throws if the
  /// returned account doesn't qualify.
  Future<supabase.User> signInWithGoogle() async {
    final client = SupabaseService.instance.client;

    try {
      AppLogger.info('Starting Google Sign In via Supabase OAuth...');

      // Begin watching for the next signed-in state BEFORE launching the
      // browser, so we don't miss the event if the redirect is very fast.
      final sessionFuture = client.auth.onAuthStateChange
          .where((state) =>
              state.event == supabase.AuthChangeEvent.signedIn &&
              state.session != null)
          .map((state) => state.session!)
          .first
          .timeout(const Duration(minutes: 5));

      await client.auth.signInWithOAuth(
        supabase.OAuthProvider.google,
        redirectTo: 'saturday://login-callback',
        authScreenLaunchMode: supabase.LaunchMode.externalApplication,
      );

      final session = await sessionFuture;
      final user = session.user;
      final email = user.email ?? '';

      if (!email.endsWith(AppConstants.allowedEmailDomain)) {
        AppLogger.warning('Rejecting non-${AppConstants.allowedEmailDomain} account: $email');
        await client.auth.signOut();
        throw Exception(
          'Only ${AppConstants.allowedEmailDomain} accounts are allowed. '
          'Please sign in with your company email.',
        );
      }

      AppLogger.info('Supabase authentication successful for user: ${user.id}');
      return user;
    } catch (error, stackTrace) {
      AppLogger.error('Google Sign In failed', error, stackTrace);
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      AppLogger.info('Signing out user...');
      await SupabaseService.instance.signOut();
      AppLogger.info('User signed out successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Sign out failed', error, stackTrace);
      rethrow;
    }
  }

  supabase.User? getCurrentUser() => SupabaseService.instance.currentUser;

  Stream<supabase.AuthState> get authStateChanges =>
      SupabaseService.instance.authStateChanges;

  bool get isSignedIn => getCurrentUser() != null;

  bool isSessionValid() {
    final session = SupabaseService.instance.client.auth.currentSession;
    if (session == null) return false;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      session.expiresAt! * 1000,
    );
    return DateTime.now().isBefore(expiresAt);
  }

  DateTime? getSessionExpiry() {
    final session = SupabaseService.instance.client.auth.currentSession;
    if (session == null || session.expiresAt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000);
  }

  Duration? getTimeUntilExpiry() {
    final expiry = getSessionExpiry();
    if (expiry == null) return null;
    return expiry.difference(DateTime.now());
  }

  Future<bool> refreshSession() async {
    try {
      AppLogger.info('Refreshing session...');
      final session = await SupabaseService.instance.client.auth.refreshSession();
      if (session.session == null) {
        AppLogger.warning('Session refresh returned null');
        return false;
      }
      AppLogger.info('Session refreshed successfully');
      return true;
    } catch (error, stackTrace) {
      AppLogger.error('Session refresh failed', error, stackTrace);
      return false;
    }
  }

  bool shouldRefreshSession() {
    final timeUntilExpiry = getTimeUntilExpiry();
    if (timeUntilExpiry == null) return false;
    return timeUntilExpiry.inMinutes < 10;
  }
}
