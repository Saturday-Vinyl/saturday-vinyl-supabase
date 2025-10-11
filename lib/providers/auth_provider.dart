import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/user.dart';
import 'package:saturday_app/repositories/user_repository.dart';
import 'package:saturday_app/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Provider for AuthService singleton
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService.instance;
});

/// Provider for UserRepository
final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

/// Provider for auth state changes stream
/// Emits AuthState whenever authentication state changes
final authStateProvider = StreamProvider<supabase.AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

/// Provider for current authenticated Supabase user
/// Returns null if not authenticated
final currentSupabaseUserProvider = Provider<supabase.User?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.when(
    data: (state) => state.session?.user,
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Provider for current User model from database
/// Returns AsyncValue<User?> which can be loading, error, or data
final currentUserProvider = FutureProvider<User?>((ref) async {
  final supabaseUser = ref.watch(currentSupabaseUserProvider);

  if (supabaseUser == null) {
    return null;
  }

  final userRepository = ref.watch(userRepositoryProvider);

  try {
    // Get or create user in database
    final user = await userRepository.getOrCreateUser(supabaseUser);
    return user;
  } catch (error) {
    // Return null if there's an error fetching user
    return null;
  }
});

/// Provider for current user's permissions
/// Returns AsyncValue<List<String>> of permission names
final userPermissionsProvider = FutureProvider<List<String>>((ref) async {
  final user = await ref.watch(currentUserProvider.future);

  if (user == null) {
    return [];
  }

  final userRepository = ref.watch(userRepositoryProvider);

  try {
    final permissions = await userRepository.getUserPermissions(user.id);
    return permissions;
  } catch (error) {
    return [];
  }
});

/// Provider to check if current user has a specific permission
/// Usage: ref.watch(hasPermissionProvider('manage_products'))
final hasPermissionProvider = FutureProvider.family<bool, String>((ref, permissionName) async {
  final user = await ref.watch(currentUserProvider.future);

  if (user == null) {
    return false;
  }

  // Admins have all permissions
  if (user.isAdmin) {
    return true;
  }

  final permissions = await ref.watch(userPermissionsProvider.future);
  return permissions.contains(permissionName);
});

/// Provider to check if current user is admin
final isAdminProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(currentUserProvider.future);
  return user?.isAdmin ?? false;
});

/// Provider to check if user is signed in
final isSignedInProvider = Provider<bool>((ref) {
  final supabaseUser = ref.watch(currentSupabaseUserProvider);
  return supabaseUser != null;
});
