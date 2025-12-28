import 'package:saturday_consumer_app/models/tag.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Repository for tag-related database operations.
class TagRepository extends BaseRepository {
  static const _tableName = 'tags';

  /// Gets a tag by ID.
  Future<Tag?> getTag(String tagId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('id', tagId)
        .maybeSingle();

    if (response == null) return null;
    return Tag.fromJson(response);
  }

  /// Gets a tag by its EPC identifier.
  Future<Tag?> getTagByEpc(String epc) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('epc_identifier', epc)
        .maybeSingle();

    if (response == null) return null;
    return Tag.fromJson(response);
  }

  /// Associates a tag with a library album.
  ///
  /// Creates the tag if it doesn't exist.
  Future<Tag> associateTag(
    String epc,
    String libraryAlbumId,
    String userId,
  ) async {
    final existing = await getTagByEpc(epc);
    final now = DateTime.now().toIso8601String();

    if (existing != null) {
      // Update existing tag
      final response = await client
          .from(_tableName)
          .update({
            'library_album_id': libraryAlbumId,
            'associated_at': now,
            'associated_by': userId,
            'status': TagStatus.active.name,
          })
          .eq('id', existing.id)
          .select()
          .single();

      return Tag.fromJson(response);
    }

    // Create new tag
    final response = await client
        .from(_tableName)
        .insert({
          'epc_identifier': epc,
          'library_album_id': libraryAlbumId,
          'status': TagStatus.active.name,
          'associated_at': now,
          'associated_by': userId,
          'created_at': now,
        })
        .select()
        .single();

    return Tag.fromJson(response);
  }

  /// Disassociates a tag from its album.
  Future<Tag> disassociateTag(String tagId) async {
    final response = await client
        .from(_tableName)
        .update({
          'library_album_id': null,
          'associated_at': null,
          'associated_by': null,
        })
        .eq('id', tagId)
        .select()
        .single();

    return Tag.fromJson(response);
  }

  /// Gets all tags associated with a library album.
  Future<List<Tag>> getTagsForLibraryAlbum(String libraryAlbumId) async {
    final response = await client
        .from(_tableName)
        .select()
        .eq('library_album_id', libraryAlbumId)
        .eq('status', TagStatus.active.name);

    return (response as List).map((row) => Tag.fromJson(row)).toList();
  }

  /// Updates the last seen timestamp for a tag.
  Future<void> updateLastSeen(String tagId) async {
    await client.from(_tableName).update({
      'last_seen_at': DateTime.now().toIso8601String(),
    }).eq('id', tagId);
  }

  /// Updates the last seen timestamp for a tag by EPC.
  Future<void> updateLastSeenByEpc(String epc) async {
    await client.from(_tableName).update({
      'last_seen_at': DateTime.now().toIso8601String(),
    }).eq('epc_identifier', epc);
  }

  /// Retires a tag so it's no longer active.
  Future<Tag> retireTag(String tagId) async {
    final response = await client
        .from(_tableName)
        .update({
          'status': TagStatus.retired.name,
          'library_album_id': null,
        })
        .eq('id', tagId)
        .select()
        .single();

    return Tag.fromJson(response);
  }
}
