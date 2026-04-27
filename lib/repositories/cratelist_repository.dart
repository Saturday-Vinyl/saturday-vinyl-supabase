import 'package:saturday_consumer_app/models/cratelist.dart';
import 'package:saturday_consumer_app/models/cratelist_item.dart';
import 'package:saturday_consumer_app/models/cratelist_member.dart';
import 'package:saturday_consumer_app/repositories/base_repository.dart';

/// Lightweight preview of a cratelist for tile rendering: the first few
/// album cover URLs plus the total item count.
class CratelistPreview {
  final Cratelist cratelist;
  final List<String> coverUrls;
  final int itemCount;

  const CratelistPreview({
    required this.cratelist,
    required this.coverUrls,
    required this.itemCount,
  });
}

/// Repository for cratelist-related database operations.
class CratelistRepository extends BaseRepository {
  static const _cratelistsTable = 'cratelists';
  static const _membersTable = 'cratelist_members';
  static const _itemsTable = 'cratelist_items';

  // ==========================================================================
  // CRATELISTS
  // ==========================================================================

  /// Lists all cratelists the current user is a member of.
  ///
  /// Sorted by most-recently-updated first.
  Future<List<Cratelist>> getUserCratelists(String userId) async {
    final response = await client
        .from(_membersTable)
        .select('cratelist:cratelists(*)')
        .eq('user_id', userId);

    return (response as List)
        .map((row) =>
            Cratelist.fromJson(row['cratelist'] as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<Cratelist?> getCratelist(String cratelistId) async {
    final response = await client
        .from(_cratelistsTable)
        .select()
        .eq('id', cratelistId)
        .maybeSingle();

    if (response == null) return null;
    return Cratelist.fromJson(response);
  }

  /// Creates a new cratelist. The creator is added as an owner member by a
  /// database trigger.
  Future<Cratelist> createCratelist({
    required String name,
    String? description,
    required String userId,
  }) async {
    final response = await client
        .from(_cratelistsTable)
        .insert({
          'name': name,
          'description': description,
          'created_by': userId,
        })
        .select()
        .single();

    return Cratelist.fromJson(response);
  }

  Future<Cratelist> updateCratelist({
    required String id,
    String? name,
    String? description,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (description != null) updates['description'] = description;

    final response = await client
        .from(_cratelistsTable)
        .update(updates)
        .eq('id', id)
        .select()
        .single();

    return Cratelist.fromJson(response);
  }

  Future<void> deleteCratelist(String cratelistId) async {
    await client.from(_cratelistsTable).delete().eq('id', cratelistId);
  }

  // ==========================================================================
  // ITEMS
  // ==========================================================================

  /// Lightweight tile data for a cratelist: first 4 cover URLs (in position
  /// order) plus the total item count.
  Future<CratelistPreview> getCratelistPreview(Cratelist cratelist) async {
    final coverResponse = await client
        .from(_itemsTable)
        .select('library_album:library_albums(album:albums(cover_image_url))')
        .eq('cratelist_id', cratelist.id)
        .order('position')
        .limit(4);

    final coverUrls = (coverResponse as List)
        .map((row) {
          final libraryAlbum = row['library_album'] as Map<String, dynamic>?;
          final album = libraryAlbum?['album'] as Map<String, dynamic>?;
          return album?['cover_image_url'] as String?;
        })
        .whereType<String>()
        .toList();

    final countResponse = await client
        .from(_itemsTable)
        .select()
        .eq('cratelist_id', cratelist.id)
        .count();

    return CratelistPreview(
      cratelist: cratelist,
      coverUrls: coverUrls,
      itemCount: countResponse.count,
    );
  }

  /// Returns the items in a cratelist in their stored position order, with
  /// joined library_album + album metadata.
  Future<List<CratelistItem>> getCratelistItems(String cratelistId) async {
    final response = await client
        .from(_itemsTable)
        .select(
            '*, library_album:library_albums(*, album:albums(*))')
        .eq('cratelist_id', cratelistId)
        .order('position');

    return (response as List)
        .map((row) => CratelistItem.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Appends an album to a cratelist. The new item is placed at the end.
  ///
  /// Returns null if the album is already in the cratelist (DB unique
  /// constraint blocks duplicates).
  Future<CratelistItem> addItem({
    required String cratelistId,
    required String libraryAlbumId,
    required String userId,
  }) async {
    // Compute next position. Race with other clients is rare and would surface
    // as a unique-constraint violation; UI can retry.
    final maxPosResponse = await client
        .from(_itemsTable)
        .select('position')
        .eq('cratelist_id', cratelistId)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();

    final nextPosition =
        ((maxPosResponse?['position'] as int?) ?? 0) + 1;

    final response = await client
        .from(_itemsTable)
        .insert({
          'cratelist_id': cratelistId,
          'library_album_id': libraryAlbumId,
          'position': nextPosition,
          'added_by': userId,
        })
        .select(
            '*, library_album:library_albums(*, album:albums(*))')
        .single();

    return CratelistItem.fromJson(response);
  }

  /// Adds multiple albums to a cratelist in one batch, appending in the
  /// order given. Skips albums that are already present.
  Future<List<CratelistItem>> addItems({
    required String cratelistId,
    required List<String> libraryAlbumIds,
    required String userId,
  }) async {
    if (libraryAlbumIds.isEmpty) return [];

    final maxPosResponse = await client
        .from(_itemsTable)
        .select('position')
        .eq('cratelist_id', cratelistId)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();

    final basePosition = (maxPosResponse?['position'] as int?) ?? 0;

    final rows = [
      for (var i = 0; i < libraryAlbumIds.length; i++)
        {
          'cratelist_id': cratelistId,
          'library_album_id': libraryAlbumIds[i],
          'position': basePosition + i + 1,
          'added_by': userId,
        }
    ];

    final response = await client
        .from(_itemsTable)
        .insert(rows)
        .select(
            '*, library_album:library_albums(*, album:albums(*))');

    return (response as List)
        .map((row) => CratelistItem.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeItem(String itemId) async {
    await client.from(_itemsTable).delete().eq('id', itemId);
  }

  /// Sets the order of items in a cratelist via the
  /// `reorder_cratelist_items` RPC, which performs the positional update in
  /// a single statement so the deferrable unique constraint can be satisfied.
  ///
  /// [orderedItemIds] must contain exactly the cratelist's current item ids.
  Future<void> reorderItems({
    required String cratelistId,
    required List<String> orderedItemIds,
  }) async {
    await client.rpc(
      'reorder_cratelist_items',
      params: {
        'p_cratelist_id': cratelistId,
        'p_item_ids': orderedItemIds,
      },
    );
  }

  // ==========================================================================
  // MEMBERS (read-only in v1; sharing UI lands later)
  // ==========================================================================

  Future<List<CratelistMember>> getCratelistMembers(String cratelistId) async {
    final response = await client
        .from(_membersTable)
        .select()
        .eq('cratelist_id', cratelistId)
        .order('added_at');

    return (response as List)
        .map((row) => CratelistMember.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
