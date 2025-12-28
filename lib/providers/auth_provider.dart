import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/models/user.dart' as models;
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/providers/supabase_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

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

/// Provider for the current user's ID, or null if not signed in.
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentSupabaseUserProvider)?.id;
});
