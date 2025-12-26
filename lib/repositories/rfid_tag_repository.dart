import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/tag_filter.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing RFID tags in Supabase
class RfidTagRepository {
  final _supabase = SupabaseService.instance.client;

  /// Get tags with optional filtering and pagination
  ///
  /// [filter] - Optional filter parameters (status, search, sort)
  /// [limit] - Maximum number of tags to return (default 50)
  /// [offset] - Number of tags to skip for pagination (default 0)
  Future<List<RfidTag>> getTags({
    TagFilter? filter,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final effectiveFilter = filter ?? TagFilter.defaultFilter;
      AppLogger.info(
        'Fetching tags with filter: $effectiveFilter, limit: $limit, offset: $offset',
      );

      // Build query based on filter conditions
      final hasStatus = effectiveFilter.status != null;
      final hasSearch = effectiveFilter.searchQuery != null &&
          effectiveFilter.searchQuery!.isNotEmpty;

      late final List<dynamic> response;

      if (hasStatus && hasSearch) {
        response = await _supabase
            .from('rfid_tags')
            .select()
            .eq('status', effectiveFilter.status!.value)
            .ilike('epc_identifier', '%${effectiveFilter.searchQuery}%')
            .order(effectiveFilter.sortColumn,
                ascending: effectiveFilter.sortAscending)
            .range(offset, offset + limit - 1);
      } else if (hasStatus) {
        response = await _supabase
            .from('rfid_tags')
            .select()
            .eq('status', effectiveFilter.status!.value)
            .order(effectiveFilter.sortColumn,
                ascending: effectiveFilter.sortAscending)
            .range(offset, offset + limit - 1);
      } else if (hasSearch) {
        response = await _supabase
            .from('rfid_tags')
            .select()
            .ilike('epc_identifier', '%${effectiveFilter.searchQuery}%')
            .order(effectiveFilter.sortColumn,
                ascending: effectiveFilter.sortAscending)
            .range(offset, offset + limit - 1);
      } else {
        response = await _supabase
            .from('rfid_tags')
            .select()
            .order(effectiveFilter.sortColumn,
                ascending: effectiveFilter.sortAscending)
            .range(offset, offset + limit - 1);
      }

      final tags = response.map((json) => RfidTag.fromJson(json)).toList();

      AppLogger.info('Found ${tags.length} tags');
      return tags;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch tags', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single tag by EPC identifier
  ///
  /// Returns null if not found
  Future<RfidTag?> getTagByEpc(String epc) async {
    try {
      AppLogger.info('Fetching tag by EPC: $epc');

      final response = await _supabase
          .from('rfid_tags')
          .select()
          .eq('epc_identifier', epc.toUpperCase())
          .maybeSingle();

      if (response == null) {
        AppLogger.info('Tag not found for EPC: $epc');
        return null;
      }

      final tag = RfidTag.fromJson(response);
      AppLogger.info('Found tag: ${tag.id}');
      return tag;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch tag by EPC', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single tag by ID
  Future<RfidTag?> getTagById(String id) async {
    try {
      AppLogger.info('Fetching tag by ID: $id');

      final response = await _supabase
          .from('rfid_tags')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('Tag not found for ID: $id');
        return null;
      }

      final tag = RfidTag.fromJson(response);
      AppLogger.info('Found tag: ${tag.formattedEpc}');
      return tag;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch tag by ID', error, stackTrace);
      rethrow;
    }
  }

  /// Bulk lookup tags by EPC identifiers
  ///
  /// Used for scan mode to identify which tags in range are in the database
  Future<List<RfidTag>> getTagsByEpcs(List<String> epcs) async {
    try {
      if (epcs.isEmpty) {
        return [];
      }

      AppLogger.info('Bulk lookup for ${epcs.length} EPCs');

      // Normalize EPCs to uppercase
      final normalizedEpcs = epcs.map((e) => e.toUpperCase()).toList();

      final response = await _supabase
          .from('rfid_tags')
          .select()
          .inFilter('epc_identifier', normalizedEpcs);

      final tags =
          (response as List).map((json) => RfidTag.fromJson(json)).toList();

      AppLogger.info('Found ${tags.length} of ${epcs.length} tags in database');
      return tags;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to bulk lookup tags', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new tag with generated EPC
  ///
  /// [epc] - The EPC identifier (should be generated with RfidTag.generateEpc())
  /// [createdBy] - User ID of the creator
  Future<RfidTag> createTag(String epc, String? createdBy) async {
    try {
      AppLogger.info('Creating tag with EPC: $epc');

      final data = {
        'epc_identifier': epc.toUpperCase(),
        'status': RfidTagStatus.generated.value,
        'created_by': createdBy,
      };

      final response =
          await _supabase.from('rfid_tags').insert(data).select().single();

      final tag = RfidTag.fromJson(response);
      AppLogger.info('Tag created successfully: ${tag.id}');
      return tag;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create tag', error, stackTrace);
      rethrow;
    }
  }

  /// Update tag status
  ///
  /// Automatically sets written_at when transitioning to 'written'
  /// Automatically sets locked_at when transitioning to 'locked'
  ///
  /// [id] - Tag ID
  /// [status] - New status
  /// [tid] - Optional TID to store (captured during write)
  Future<RfidTag> updateTagStatus(
    String id,
    RfidTagStatus status, {
    String? tid,
  }) async {
    try {
      AppLogger.info('Updating tag $id status to ${status.value}');

      final data = <String, dynamic>{
        'status': status.value,
      };

      // Set timestamps for specific status transitions
      if (status == RfidTagStatus.written) {
        data['written_at'] = DateTime.now().toIso8601String();
      } else if (status == RfidTagStatus.locked) {
        data['locked_at'] = DateTime.now().toIso8601String();
      }

      // Optionally set TID
      if (tid != null) {
        data['tid'] = tid;
      }

      final response = await _supabase
          .from('rfid_tags')
          .update(data)
          .eq('id', id)
          .select()
          .single();

      final tag = RfidTag.fromJson(response);
      AppLogger.info('Tag status updated: ${tag.formattedEpc} -> ${status.value}');
      return tag;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update tag status', error, stackTrace);
      rethrow;
    }
  }

  /// Retire a tag (mark as no longer in circulation)
  Future<RfidTag> retireTag(String id) async {
    try {
      AppLogger.info('Retiring tag: $id');
      return await updateTagStatus(id, RfidTagStatus.retired);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to retire tag', error, stackTrace);
      rethrow;
    }
  }

  /// Get count of tags, optionally filtered by status
  Future<int> getTagCount({RfidTagStatus? status}) async {
    try {
      AppLogger.info(
        'Getting tag count${status != null ? ' for status: ${status.value}' : ''}',
      );

      late final List<dynamic> response;

      if (status != null) {
        response = await _supabase
            .from('rfid_tags')
            .select('id')
            .eq('status', status.value);
      } else {
        response = await _supabase.from('rfid_tags').select('id');
      }

      final count = response.length;

      AppLogger.info('Tag count: $count');
      return count;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get tag count', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a tag (use sparingly - prefer retiring)
  Future<void> deleteTag(String id) async {
    try {
      AppLogger.info('Deleting tag: $id');

      await _supabase.from('rfid_tags').delete().eq('id', id);

      AppLogger.info('Tag deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete tag', error, stackTrace);
      rethrow;
    }
  }

  /// Create tag and immediately update to written status
  ///
  /// Convenience method for bulk write workflow
  Future<RfidTag> createAndWriteTag({
    required String epc,
    required String? createdBy,
    String? tid,
  }) async {
    try {
      AppLogger.info('Creating and writing tag with EPC: $epc');

      final data = {
        'epc_identifier': epc.toUpperCase(),
        'status': RfidTagStatus.written.value,
        'created_by': createdBy,
        'written_at': DateTime.now().toIso8601String(),
        if (tid != null) 'tid': tid,
      };

      final response =
          await _supabase.from('rfid_tags').insert(data).select().single();

      final tag = RfidTag.fromJson(response);
      AppLogger.info('Tag created and marked as written: ${tag.id}');
      return tag;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create and write tag', error, stackTrace);
      rethrow;
    }
  }
}
