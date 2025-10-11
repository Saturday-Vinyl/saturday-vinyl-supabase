import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/permission.dart';
import 'package:saturday_app/models/user.dart';
import 'package:saturday_app/providers/auth_provider.dart';
import 'package:saturday_app/repositories/user_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Provider for all users list (admin only)
final allUsersProvider = FutureProvider<List<User>>((ref) async {
  final currentUser = await ref.watch(currentUserProvider.future);

  if (currentUser == null || !currentUser.isAdmin) {
    AppLogger.warning('Non-admin user attempted to access all users');
    return [];
  }

  final userRepository = ref.watch(userRepositoryProvider);
  return await userRepository.getAllUsers();
});

/// Provider for all available permissions
final allPermissionsProvider = FutureProvider<List<Permission>>((ref) async {
  final userRepository = ref.watch(userRepositoryProvider);
  return await userRepository.getAllPermissions();
});

/// Provider for a specific user's permissions (with details)
final userPermissionDetailsProvider = FutureProvider.family<Map<String, bool>, String>((ref, userId) async {
  final userRepository = ref.watch(userRepositoryProvider);
  final allPermissions = await ref.watch(allPermissionsProvider.future);
  final userPermissionAssignments = await userRepository.getUserPermissionDetails(userId);

  // Create a map of permission ID -> has permission
  final permissionMap = <String, bool>{};
  for (final permission in allPermissions) {
    final hasPermission = userPermissionAssignments.any((up) => up.permissionId == permission.id);
    permissionMap[permission.id] = hasPermission;
  }

  return permissionMap;
});

/// Provider for user management actions
final userManagementProvider = Provider((ref) => UserManagementActions(ref));

/// User management actions
class UserManagementActions {
  final Ref ref;

  UserManagementActions(this.ref);

  /// Grant permission to user
  Future<void> grantPermission({
    required String userId,
    required String permissionId,
  }) async {
    try {
      final currentUser = await ref.read(currentUserProvider.future);
      if (currentUser == null) {
        throw Exception('No current user');
      }

      if (!currentUser.isAdmin) {
        throw Exception('Only admins can grant permissions');
      }

      final userRepository = ref.read(userRepositoryProvider);
      await userRepository.grantPermission(
        userId: userId,
        permissionId: permissionId,
        grantedBy: currentUser.id,
      );

      // Refresh the user's permissions
      ref.invalidate(userPermissionDetailsProvider(userId));
      ref.invalidate(allUsersProvider);

      AppLogger.info('Permission granted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to grant permission', error, stackTrace);
      rethrow;
    }
  }

  /// Revoke permission from user
  Future<void> revokePermission({
    required String userId,
    required String permissionId,
  }) async {
    try {
      final currentUser = await ref.read(currentUserProvider.future);
      if (currentUser == null) {
        throw Exception('No current user');
      }

      if (!currentUser.isAdmin) {
        throw Exception('Only admins can revoke permissions');
      }

      final userRepository = ref.read(userRepositoryProvider);
      await userRepository.revokePermission(
        userId: userId,
        permissionId: permissionId,
      );

      // Refresh the user's permissions
      ref.invalidate(userPermissionDetailsProvider(userId));
      ref.invalidate(allUsersProvider);

      AppLogger.info('Permission revoked successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to revoke permission', error, stackTrace);
      rethrow;
    }
  }

  /// Toggle user admin status
  Future<void> toggleAdminStatus({
    required String userId,
    required bool isAdmin,
  }) async {
    try {
      final currentUser = await ref.read(currentUserProvider.future);
      if (currentUser == null || !currentUser.isAdmin) {
        throw Exception('Only admins can change admin status');
      }

      if (currentUser.id == userId) {
        throw Exception('Cannot change your own admin status');
      }

      final userRepository = ref.read(userRepositoryProvider);
      await userRepository.updateUserAdminStatus(
        userId: userId,
        isAdmin: isAdmin,
      );

      // Refresh users list
      ref.invalidate(allUsersProvider);

      AppLogger.info('Admin status updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update admin status', error, stackTrace);
      rethrow;
    }
  }

  /// Toggle user active status
  Future<void> toggleActiveStatus({
    required String userId,
    required bool isActive,
  }) async {
    try {
      final currentUser = await ref.read(currentUserProvider.future);
      if (currentUser == null || !currentUser.isAdmin) {
        throw Exception('Only admins can change active status');
      }

      if (currentUser.id == userId) {
        throw Exception('Cannot deactivate your own account');
      }

      final userRepository = ref.read(userRepositoryProvider);
      await userRepository.updateUserActiveStatus(
        userId: userId,
        isActive: isActive,
      );

      // Refresh users list
      ref.invalidate(allUsersProvider);

      AppLogger.info('Active status updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update active status', error, stackTrace);
      rethrow;
    }
  }
}
