import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of an authentication operation.
class AuthResult {
  final bool success;
  final String? errorMessage;
  final User? user;

  const AuthResult._({
    required this.success,
    this.errorMessage,
    this.user,
  });

  factory AuthResult.success(User user) {
    return AuthResult._(success: true, user: user);
  }

  factory AuthResult.failure(String message) {
    return AuthResult._(success: false, errorMessage: message);
  }
}

/// Singleton service for authentication operations.
///
/// Provides methods for email/password auth, social auth (Apple, Google),
/// and session management. Uses Supabase Auth under the hood.
class AuthService {
  AuthService._();

  static AuthService? _instance;
  static bool _initialized = false;

  /// Returns the singleton instance.
  ///
  /// Throws [StateError] if [initialize] has not been called.
  static AuthService get instance {
    if (_instance == null || !_initialized) {
      throw StateError(
        'AuthService has not been initialized. '
        'Call AuthService.initialize() before accessing instance.',
      );
    }
    return _instance!;
  }

  /// Initializes the AuthService.
  ///
  /// Must be called after Supabase has been initialized.
  static void initialize() {
    if (_initialized) return;

    _instance = AuthService._();
    _initialized = true;
  }

  /// Returns whether the service has been initialized.
  static bool get isInitialized => _initialized;

  /// The Supabase auth client.
  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// The current authenticated user, or null if not signed in.
  User? get currentUser => _auth.currentUser;

  /// Stream of authentication state changes.
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  /// Returns true if a user is currently authenticated.
  bool get isAuthenticated => currentUser != null;

  /// The current session, or null if not authenticated.
  Session? get currentSession => _auth.currentSession;

  /// Checks if there is a valid session.
  bool isSessionValid() {
    final session = currentSession;
    if (session == null) return false;

    final expiresAt = session.expiresAt;
    if (expiresAt == null) return false;

    final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    // Consider valid if expires more than 60 seconds from now
    return DateTime.now().add(const Duration(seconds: 60)).isBefore(expiryTime);
  }

  /// Signs up a new user with email and password.
  ///
  /// Returns [AuthResult] indicating success or failure.
  /// On success, an email confirmation may be sent depending on Supabase settings.
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async {
    try {
      final response = await _auth.signUp(
        email: email,
        password: password,
        data: fullName != null ? {'full_name': fullName} : null,
      );

      if (response.user != null) {
        return AuthResult.success(response.user!);
      }

      return AuthResult.failure(
        'Sign up failed. Please try again.',
      );
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e));
    } catch (e) {
      return AuthResult.failure('An unexpected error occurred: $e');
    }
  }

  /// Signs in a user with email and password.
  ///
  /// Returns [AuthResult] indicating success or failure.
  Future<AuthResult> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        return AuthResult.success(response.user!);
      }

      return AuthResult.failure(
        'Sign in failed. Please check your credentials.',
      );
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e));
    } catch (e) {
      return AuthResult.failure('An unexpected error occurred: $e');
    }
  }

  /// Signs in with Apple.
  ///
  /// Only available on iOS/macOS.
  /// Returns [AuthResult] indicating success or failure.
  Future<AuthResult> signInWithApple() async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      return AuthResult.failure('Apple Sign In is only available on iOS and macOS');
    }

    try {
      final response = await _auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb ? null : 'com.saturdayvinyl.consumer://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      if (!response) {
        return AuthResult.failure('Apple Sign In was cancelled');
      }

      // OAuth sign-in redirects, so we wait for the auth state to change
      // The actual user will be available after the redirect callback
      return AuthResult.failure('Waiting for OAuth callback...');
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e));
    } catch (e) {
      return AuthResult.failure('Apple Sign In failed: $e');
    }
  }

  /// Signs in with Google.
  ///
  /// Available on all platforms.
  /// Returns [AuthResult] indicating success or failure.
  Future<AuthResult> signInWithGoogle() async {
    try {
      final response = await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'com.saturdayvinyl.consumer://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: {
          'access_type': 'offline',
          'prompt': 'consent',
        },
      );

      if (!response) {
        return AuthResult.failure('Google Sign In was cancelled');
      }

      // OAuth sign-in redirects, so we wait for the auth state to change
      return AuthResult.failure('Waiting for OAuth callback...');
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e));
    } catch (e) {
      return AuthResult.failure('Google Sign In failed: $e');
    }
  }

  /// Sends a password reset email.
  ///
  /// Returns true if the email was sent successfully.
  Future<AuthResult> resetPassword(String email) async {
    try {
      await _auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.saturdayvinyl.consumer://reset-password',
      );
      // Return success with no user since it's just an email send
      return const AuthResult._(success: true);
    } on AuthException catch (e) {
      return AuthResult.failure(_mapAuthError(e));
    } catch (e) {
      return AuthResult.failure('Failed to send reset email: $e');
    }
  }

  /// Signs out the current user.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Refreshes the current session.
  ///
  /// Returns the new session, or null if refresh failed.
  Future<Session?> refreshSession() async {
    try {
      final response = await _auth.refreshSession();
      return response.session;
    } catch (e) {
      debugPrint('Failed to refresh session: $e');
      return null;
    }
  }

  /// Maps Supabase auth errors to user-friendly messages.
  String _mapAuthError(AuthException e) {
    final message = e.message.toLowerCase();

    if (message.contains('invalid login credentials') ||
        message.contains('invalid email or password')) {
      return 'Invalid email or password. Please try again.';
    }

    if (message.contains('email not confirmed')) {
      return 'Please verify your email before signing in.';
    }

    if (message.contains('user already registered') ||
        message.contains('user already exists')) {
      return 'An account with this email already exists.';
    }

    if (message.contains('password')) {
      if (message.contains('too short') || message.contains('at least')) {
        return 'Password must be at least 8 characters long.';
      }
      if (message.contains('weak')) {
        return 'Please choose a stronger password.';
      }
    }

    if (message.contains('rate limit') || message.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }

    if (message.contains('network') || message.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    }

    if (message.contains('email')) {
      if (message.contains('invalid') || message.contains('format')) {
        return 'Please enter a valid email address.';
      }
    }

    // Default to the original message if no mapping found
    return e.message;
  }
}
