import 'package:saturday_app/models/permission.dart';
import 'package:saturday_app/models/user.dart';
import 'package:saturday_app/models/user_permission.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Repository for user data operations
class UserRepository {
  final SupabaseService _supabaseService;

  UserRepository({SupabaseService? supabaseService})
      : _supabaseService = supabaseService ?? SupabaseService.instance;

  /// Get or create user after Google authentication
  /// If user doesn't exist, creates a new user with default viewer permissions
  /// If user exists, updates lastLogin timestamp
  /// Returns the User model
  Future<User> getOrCreateUser(supabase.User supabaseUser) async {
    try {
      final client = _supabaseService.client;
      final email = supabaseUser.email;
      final googleId = supabaseUser.id;

      if (email == null) {
        throw Exception('User email is required');
      }

      AppLogger.info('Getting or creating user for email: $email');

      // Check if user exists
      final response = await client
          .from('users')
          .select()
          .eq('google_id', googleId)
          .maybeSingle();

      if (response != null) {
        // User exists, update last login
        AppLogger.info('User found, updating last login');

        final updatedResponse = await client
            .from('users')
            .update({
              'last_login': DateTime.now().toIso8601String(),
            })
            .eq('google_id', googleId)
            .select()
            .single();

        return User.fromJson(updatedResponse);
      } else {
        // User doesn't exist, create new user
        AppLogger.info('User not found, creating new user');

        final newUser = {
          'google_id': googleId,
          'email': email,
          'full_name': supabaseUser.userMetadata?['full_name'] as String?,
          'is_admin': false, // Default to non-admin
          'is_active': true,
          'created_at': DateTime.now().toIso8601String(),
          'last_login': DateTime.now().toIso8601String(),
        };

        final createdResponse = await client
            .from('users')
            .insert(newUser)
            .select()
            .single();

        AppLogger.info('User created successfully');

        return User.fromJson(createdResponse);
      }
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get or create user', error, stackTrace);
      rethrow;
    }
  }

  /// Get user permissions from database
  /// Returns list of permission names that the user has
  Future<List<String>> getUserPermissions(String userId) async {
    try {
      final client = _supabaseService.client;

      AppLogger.debug('Fetching permissions for user: $userId');

      final response = await client
          .from('user_permissions')
          .select('permissions(name)')
          .eq('user_id', userId);

      final permissions = (response as List)
          .map((item) => item['permissions']['name'] as String)
          .toList();

      AppLogger.debug('User has ${permissions.length} permissions');

      return permissions;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get user permissions', error, stackTrace);
      rethrow;
    }
  }

  /// Check if user has a specific permission
  /// Returns true if user has the permission or is an admin
  Future<bool> hasPermission(String userId, String permissionName) async {
    try {
      // Get user to check if admin
      final user = await getUser(userId);

      // Admins have all permissions
      if (user.isAdmin) {
        return true;
      }

      // Check specific permission
      final permissions = await getUserPermissions(userId);
      return permissions.contains(permissionName);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to check permission', error, stackTrace);
      return false;
    }
  }

  /// Get user by ID
  Future<User> getUser(String userId) async {
    try {
      final client = _supabaseService.client;

      final response = await client
          .from('users')
          .select()
          .eq('id', userId)
          .single();

      return User.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get user', error, stackTrace);
      rethrow;
    }
  }

  /// Get user by Google ID
  Future<User?> getUserByGoogleId(String googleId) async {
    try {
      final client = _supabaseService.client;

      final response = await client
          .from('users')
          .select()
          .eq('google_id', googleId)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return User.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get user by Google ID', error, stackTrace);
      rethrow;
    }
  }

  // ============================================================================
  // ADMIN-ONLY METHODS
  // ============================================================================

  /// Get all users (admin only)
  Future<List<User>> getAllUsers() async {
    try {
      final client = _supabaseService.client;

      AppLogger.info('Fetching all users');

      final response = await client
          .from('users')
          .select()
          .order('created_at', ascending: false);

      final users = (response as List)
          .map((item) => User.fromJson(item))
          .toList();

      AppLogger.info('Fetched ${users.length} users');

      return users;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get all users', error, stackTrace);
      rethrow;
    }
  }

  /// Get all available permissions
  Future<List<Permission>> getAllPermissions() async {
    try {
      final client = _supabaseService.client;

      AppLogger.debug('Fetching all permissions');

      final response = await client
          .from('permissions')
          .select()
          .order('name', ascending: true);

      final permissions = (response as List)
          .map((item) => Permission.fromJson(item))
          .toList();

      AppLogger.debug('Fetched ${permissions.length} permissions');

      return permissions;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get all permissions', error, stackTrace);
      rethrow;
    }
  }

  /// Get user's permission assignments with details
  Future<List<UserPermission>> getUserPermissionDetails(String userId) async {
    try {
      final client = _supabaseService.client;

      AppLogger.debug('Fetching permission details for user: $userId');

      final response = await client
          .from('user_permissions')
          .select()
          .eq('user_id', userId);

      final userPermissions = (response as List)
          .map((item) => UserPermission.fromJson(item))
          .toList();

      return userPermissions;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get user permission details', error, stackTrace);
      rethrow;
    }
  }

  /// Grant a permission to a user (admin only)
  Future<void> grantPermission({
    required String userId,
    required String permissionId,
    required String grantedBy,
  }) async {
    try {
      final client = _supabaseService.client;

      AppLogger.info('Granting permission $permissionId to user $userId');

      await client.from('user_permissions').insert({
        'user_id': userId,
        'permission_id': permissionId,
        'granted_by': grantedBy,
        'granted_at': DateTime.now().toIso8601String(),
      });

      AppLogger.info('Permission granted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to grant permission', error, stackTrace);
      rethrow;
    }
  }

  /// Revoke a permission from a user (admin only)
  Future<void> revokePermission({
    required String userId,
    required String permissionId,
  }) async {
    try {
      final client = _supabaseService.client;

      AppLogger.info('Revoking permission $permissionId from user $userId');

      await client
          .from('user_permissions')
          .delete()
          .eq('user_id', userId)
          .eq('permission_id', permissionId);

      AppLogger.info('Permission revoked successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to revoke permission', error, stackTrace);
      rethrow;
    }
  }

  /// Update user admin status (admin only)
  Future<void> updateUserAdminStatus({
    required String userId,
    required bool isAdmin,
  }) async {
    try {
      final client = _supabaseService.client;

      AppLogger.info('Updating admin status for user $userId to $isAdmin');

      await client
          .from('users')
          .update({'is_admin': isAdmin})
          .eq('id', userId);

      AppLogger.info('Admin status updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update admin status', error, stackTrace);
      rethrow;
    }
  }

  /// Update user active status (admin only)
  Future<void> updateUserActiveStatus({
    required String userId,
    required bool isActive,
  }) async {
    try {
      final client = _supabaseService.client;

      AppLogger.info('Updating active status for user $userId to $isActive');

      await client
          .from('users')
          .update({'is_active': isActive})
          .eq('id', userId);

      AppLogger.info('Active status updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update active status', error, stackTrace);
      rethrow;
    }
  }
}
