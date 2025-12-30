import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/user.dart' as models;
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:saturday_consumer_app/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Provider for the AuthService singleton instance.
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService.instance;
});

/// Stream provider for authentication state changes.
///
/// Emits events when the user signs in, signs out, or token refreshes.
final authStateChangesProvider = StreamProvider<supabase.AuthState>((ref) {
  return ref.watch(supabaseServiceProvider).authStateChanges;
});

/// Provider for the current Supabase auth user.
///
/// Returns null if not authenticated.
final currentSupabaseUserProvider = Provider<supabase.User?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.whenOrNull(
    data: (state) => state.session?.user,
  );
});

/// FutureProvider for the current User model from the database.
///
/// Creates the user record if it doesn't exist (first login).
/// Returns null if not authenticated.
final currentUserProvider = FutureProvider<models.User?>((ref) async {
  final authUser = ref.watch(currentSupabaseUserProvider);
  if (authUser == null) return null;

  final userRepo = ref.watch(userRepositoryProvider);
  return userRepo.getOrCreateUser(authUser);
});

/// Provider that returns whether a user is currently signed in.
final isSignedInProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.whenOrNull(
        data: (state) => state.session != null,
      ) ??
      false;
});

/// Provider for the current user's database ID, or null if not signed in.
///
/// Note: This returns the `users.id` from the database, not the Supabase auth UID.
/// Use this for database operations that reference user_id foreign keys.
final currentUserIdProvider = Provider<String?>((ref) {
  final user = ref.watch(currentUserProvider);
  return user.whenOrNull(data: (u) => u?.id);
});

/// Provider for signing in with email and password.
///
/// Usage:
/// ```dart
/// final result = await ref.read(signInWithEmailProvider({
///   'email': email,
///   'password': password,
/// }).future);
/// ```
final signInWithEmailProvider = FutureProvider.family<AuthResult, Map<String, String>>((ref, credentials) async {
  final authService = ref.read(authServiceProvider);
  return authService.signInWithEmail(
    email: credentials['email']!,
    password: credentials['password']!,
  );
});

/// Provider for signing up with email and password.
///
/// Usage:
/// ```dart
/// final result = await ref.read(signUpWithEmailProvider({
///   'email': email,
///   'password': password,
///   'fullName': name, // optional
/// }).future);
/// ```
final signUpWithEmailProvider = FutureProvider.family<AuthResult, Map<String, String>>((ref, data) async {
  final authService = ref.read(authServiceProvider);
  return authService.signUpWithEmail(
    email: data['email']!,
    password: data['password']!,
    fullName: data['fullName'],
  );
});

/// Provider for signing in with Apple.
final signInWithAppleProvider = FutureProvider<AuthResult>((ref) async {
  final authService = ref.read(authServiceProvider);
  return authService.signInWithApple();
});

/// Provider for signing in with Google.
final signInWithGoogleProvider = FutureProvider<AuthResult>((ref) async {
  final authService = ref.read(authServiceProvider);
  return authService.signInWithGoogle();
});

/// Provider for resetting password.
final resetPasswordProvider = FutureProvider.family<AuthResult, String>((ref, email) async {
  final authService = ref.read(authServiceProvider);
  return authService.resetPassword(email);
});

/// Provider for signing out.
final signOutProvider = FutureProvider<void>((ref) async {
  final authService = ref.read(authServiceProvider);
  await authService.signOut();
});
