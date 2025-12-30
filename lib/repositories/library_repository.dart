import 'package:saturday_consumer_app/models/library.dart';
import 'package:saturday_consumer_app/models/library_member.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for library-related database operations.
class LibraryRepository extends BaseRepository {
  static const _librariesTable = 'libraries';
  static const _membersTable = 'library_members';

  /// Gets all libraries the user has access to.
  ///
  /// Returns libraries along with the user's role in each.
  Future<List<({Library library, LibraryRole role})>> getUserLibraries(
      String userId) async {
    final response = await client
        .from(_membersTable)
        .select('*, library:libraries(*)')
        .eq('user_id', userId);

    return (response as List).map((row) {
      final libraryData = row['library'] as Map<String, dynamic>;
      return (
        library: Library.fromJson(libraryData),
        role: LibraryRole.fromString(row['role'] as String),
      );
    }).toList();
  }

  /// Gets a single library by ID.
  Future<Library?> getLibrary(String libraryId) async {
    final response = await client
        .from(_librariesTable)
        .select()
        .eq('id', libraryId)
        .maybeSingle();

    if (response == null) return null;
    return Library.fromJson(response);
  }

  /// Creates a new library.
  ///
  /// The creating user is automatically added as owner via database trigger.
  Future<Library> createLibrary(String name, String userId,
      {String? description}) async {
    final now = DateTime.now().toIso8601String();

    // Create the library
    // Note: The database trigger `on_library_created` automatically adds
    // the creator as an owner in library_members
    final libraryResponse = await client
        .from(_librariesTable)
        .insert({
          'name': name,
          'description': description,
          'created_by': userId,
          'created_at': now,
          'updated_at': now,
        })
        .select()
        .single();

    return Library.fromJson(libraryResponse);
  }

  /// Updates a library.
  Future<Library> updateLibrary(Library library) async {
    final response = await client
        .from(_librariesTable)
        .update({
          'name': library.name,
          'description': library.description,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', library.id)
        .select()
        .single();

    return Library.fromJson(response);
  }

  /// Deletes a library.
  ///
  /// Note: This should cascade delete members and library_albums.
  Future<void> deleteLibrary(String libraryId) async {
    await client.from(_librariesTable).delete().eq('id', libraryId);
  }

  /// Gets all members of a library.
  Future<List<LibraryMember>> getLibraryMembers(String libraryId) async {
    final response = await client
        .from(_membersTable)
        .select()
        .eq('library_id', libraryId)
        .order('joined_at');

    return (response as List)
        .map((row) => LibraryMember.fromJson(row))
        .toList();
  }

  /// Adds a member to a library by email.
  ///
  /// The user must already exist in the system.
  Future<LibraryMember?> addLibraryMember(
    String libraryId,
    String email,
    LibraryRole role,
    String invitedBy,
  ) async {
    // First find the user by email
    final userResponse = await client
        .from('users')
        .select('id')
        .eq('email', email)
        .maybeSingle();

    if (userResponse == null) return null;

    final userId = userResponse['id'] as String;

    // Check if already a member
    final existing = await client
        .from(_membersTable)
        .select()
        .eq('library_id', libraryId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      return LibraryMember.fromJson(existing);
    }

    // Add new member
    final response = await client
        .from(_membersTable)
        .insert({
          'library_id': libraryId,
          'user_id': userId,
          'role': role.name,
          'joined_at': DateTime.now().toIso8601String(),
          'invited_by': invitedBy,
        })
        .select()
        .single();

    return LibraryMember.fromJson(response);
  }

  /// Updates a member's role.
  Future<LibraryMember> updateMemberRole(
      String memberId, LibraryRole role) async {
    final response = await client
        .from(_membersTable)
        .update({'role': role.name})
        .eq('id', memberId)
        .select()
        .single();

    return LibraryMember.fromJson(response);
  }

  /// Removes a member from a library.
  Future<void> removeMember(String memberId) async {
    await client.from(_membersTable).delete().eq('id', memberId);
  }

  /// Gets the user's role in a specific library.
  Future<LibraryRole?> getUserRole(String libraryId, String userId) async {
    final response = await client
        .from(_membersTable)
        .select('role')
        .eq('library_id', libraryId)
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) return null;
    return LibraryRole.fromString(response['role'] as String);
  }
}
