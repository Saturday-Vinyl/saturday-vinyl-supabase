import 'package:saturday_consumer_app/models/user.dart' as models;
import 'package:saturday_consumer_app/repositories/base_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Repository for user-related database operations.
class UserRepository extends BaseRepository {
  static const _tableName = 'users';

  /// Gets a user by their ID.
  Future<models.User?> getUser(String userId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (response == null) return null;
    return models.User.fromJson(response);
  }

  /// Gets or creates a user record based on Supabase auth user.
  ///
  /// Called on first login to ensure user exists in database.
  Future<models.User> getOrCreateUser(supabase.User authUser) async {
    // First try to find existing user by auth_user_id
    var response = await client
        .from(_tableName)
        .select()
        .eq('auth_user_id', authUser.id)
        .maybeSingle();

    // If not found, try by email (for users created before auth_user_id was added)
    if (response == null && authUser.email != null) {
      response = await client
          .from(_tableName)
          .select()
          .eq('email', authUser.email!)
          .maybeSingle();

      // If found by email, update auth_user_id for future lookups
      if (response != null) {
        await client
            .from(_tableName)
            .update({
              'auth_user_id': authUser.id,
              'last_login': DateTime.now().toIso8601String(),
            })
            .eq('id', response['id']);

        // Refresh the response with updated data
        response = await client
            .from(_tableName)
            .select()
            .eq('id', response['id'])
            .single();
      }
    }

    if (response != null) {
      // Update last login for existing user
      await client.from(_tableName).update({
        'last_login': DateTime.now().toIso8601String(),
      }).eq('id', response['id']);

      return models.User.fromJson(response);
    }

    // Create new user record
    final newUser = {
      'auth_user_id': authUser.id,
      'email': authUser.email ?? '',
      'full_name': authUser.userMetadata?['full_name'] as String?,
      'avatar_url': authUser.userMetadata?['avatar_url'] as String?,
      'created_at': DateTime.now().toIso8601String(),
      'last_login': DateTime.now().toIso8601String(),
    };

    final insertResponse = await client
        .from(_tableName)
        .insert(newUser)
        .select()
        .single();

    return models.User.fromJson(insertResponse);
  }

  /// Updates an existing user.
  Future<models.User> updateUser(models.User user) async {
    final response = await client
        .from(_tableName)
        .update({
          'full_name': user.fullName,
          'avatar_url': user.avatarUrl,
          'preferences': user.preferences,
        })
        .eq('id', user.id)
        .select()
        .single();

    return models.User.fromJson(response);
  }

  /// Updates the last login timestamp for a user.
  Future<void> updateLastLogin(String userId) async {
    await client.from(_tableName).update({
      'last_login': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Updates last login and ensures auth_user_id is set.
  ///
  /// This handles migration of existing users who don't have auth_user_id set.
  Future<void> updateLastLoginAndAuthId(String userId) async {
    await client.from(_tableName).update({
      'last_login': DateTime.now().toIso8601String(),
      'auth_user_id': userId,
    }).eq('id', userId);
  }
}
