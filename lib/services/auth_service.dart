import 'package:google_sign_in/google_sign_in.dart';
import 'package:saturday_app/config/constants.dart';
import 'package:saturday_app/config/env_config.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Authentication service for Google OAuth
class AuthService {
  AuthService._(); // Private constructor for singleton

  static AuthService? _instance;
  static GoogleSignIn? _googleSignIn;

  /// Get the singleton instance
  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }

  /// Initialize Google Sign In
  static void initialize() {
    _googleSignIn = GoogleSignIn(
      clientId: EnvConfig.googleClientId,
      scopes: [
        'email',
        'profile',
      ],
    );
    AppLogger.info('Google Sign In initialized');
  }

  /// Get GoogleSignIn instance
  GoogleSignIn get _googleSignInInstance {
    if (_googleSignIn == null) {
      throw Exception(
        'Google Sign In has not been initialized. Call AuthService.initialize() first.',
      );
    }
    return _googleSignIn!;
  }

  /// Sign in with Google
  /// Returns the authenticated Supabase user
  /// Throws exception if sign in fails or user domain is not allowed
  Future<supabase.User> signInWithGoogle() async {
    try {
      AppLogger.info('Starting Google Sign In...');

      // Sign in with Google
      final googleUser = await _googleSignInInstance.signIn();

      if (googleUser == null) {
        throw Exception('Google Sign In was cancelled by user');
      }

      AppLogger.info('Google Sign In successful for: ${googleUser.email}');

      // Validate email domain
      if (!googleUser.email.endsWith(AppConstants.allowedEmailDomain)) {
        await _googleSignInInstance.signOut();
        throw Exception(
          'Only ${AppConstants.allowedEmailDomain} accounts are allowed. '
          'Please sign in with your company email.',
        );
      }

      AppLogger.info('Email domain validated: ${googleUser.email}');

      // Get Google authentication tokens
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null || accessToken == null) {
        throw Exception('Failed to get Google authentication tokens');
      }

      // Sign in to Supabase with Google credentials
      final supabaseClient = SupabaseService.instance.client;
      final response = await supabaseClient.auth.signInWithIdToken(
        provider: supabase.OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      final user = response.user;
      if (user == null) {
        throw Exception('Failed to authenticate with Supabase');
      }

      AppLogger.info('Supabase authentication successful for user: ${user.id}');

      return user;
    } catch (error, stackTrace) {
      AppLogger.error('Google Sign In failed', error, stackTrace);
      rethrow;
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    try {
      AppLogger.info('Signing out user...');

      // Sign out from Google
      await _googleSignInInstance.signOut();

      // Sign out from Supabase
      await SupabaseService.instance.signOut();

      AppLogger.info('User signed out successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Sign out failed', error, stackTrace);
      rethrow;
    }
  }

  /// Get current authenticated user from Supabase
  supabase.User? getCurrentUser() {
    return SupabaseService.instance.currentUser;
  }

  /// Get auth state changes stream
  Stream<supabase.AuthState> get authStateChanges {
    return SupabaseService.instance.authStateChanges;
  }

  /// Check if user is currently signed in
  bool get isSignedIn {
    return getCurrentUser() != null;
  }

  /// Check if the session is valid and not expired
  bool isSessionValid() {
    final session = SupabaseService.instance.client.auth.currentSession;
    if (session == null) return false;

    // Check if session is expired
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      session.expiresAt! * 1000,
    );
    return DateTime.now().isBefore(expiresAt);
  }

  /// Get session expiry time
  DateTime? getSessionExpiry() {
    final session = SupabaseService.instance.client.auth.currentSession;
    if (session == null || session.expiresAt == null) return null;

    return DateTime.fromMillisecondsSinceEpoch(
      session.expiresAt! * 1000,
    );
  }

  /// Get time until session expires
  Duration? getTimeUntilExpiry() {
    final expiry = getSessionExpiry();
    if (expiry == null) return null;

    return expiry.difference(DateTime.now());
  }

  /// Refresh the current session
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

  /// Check if session needs refresh (less than 10 minutes until expiry)
  bool shouldRefreshSession() {
    final timeUntilExpiry = getTimeUntilExpiry();
    if (timeUntilExpiry == null) return false;

    // Refresh if less than 10 minutes remaining
    return timeUntilExpiry.inMinutes < 10;
  }
}
