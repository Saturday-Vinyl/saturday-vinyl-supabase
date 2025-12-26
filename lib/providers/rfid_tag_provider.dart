import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/rfid_tag.dart';
import 'package:saturday_app/models/tag_filter.dart';
import 'package:saturday_app/repositories/rfid_tag_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Provider for RfidTagRepository
final rfidTagRepositoryProvider = Provider<RfidTagRepository>((ref) {
  return RfidTagRepository();
});

/// Provider for filtered list of tags
///
/// Use with TagFilter to get filtered, sorted, paginated results
final rfidTagsProvider =
    FutureProvider.family<List<RfidTag>, TagFilter>((ref, filter) async {
  final repository = ref.watch(rfidTagRepositoryProvider);
  return await repository.getTags(filter: filter);
});

/// Provider for all tags (default filter, newest first)
final allRfidTagsProvider = FutureProvider<List<RfidTag>>((ref) async {
  final repository = ref.watch(rfidTagRepositoryProvider);
  return await repository.getTags();
});

/// Provider for a single tag by EPC
final rfidTagByEpcProvider =
    FutureProvider.family<RfidTag?, String>((ref, epc) async {
  final repository = ref.watch(rfidTagRepositoryProvider);
  return await repository.getTagByEpc(epc);
});

/// Provider for a single tag by ID
final rfidTagByIdProvider =
    FutureProvider.family<RfidTag?, String>((ref, id) async {
  final repository = ref.watch(rfidTagRepositoryProvider);
  return await repository.getTagById(id);
});

/// Provider for tag count
final rfidTagCountProvider =
    FutureProvider.family<int, RfidTagStatus?>((ref, status) async {
  final repository = ref.watch(rfidTagRepositoryProvider);
  return await repository.getTagCount(status: status);
});

/// Provider for total tag count (all statuses)
final totalRfidTagCountProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(rfidTagRepositoryProvider);
  return await repository.getTagCount();
});

/// Provider for tag management actions
final rfidTagManagementProvider = Provider((ref) => RfidTagManagement(ref));

/// Tag management actions
class RfidTagManagement {
  final Ref ref;

  RfidTagManagement(this.ref);

  /// Create a new tag
  Future<RfidTag> createTag(String epc, String? createdBy) async {
    try {
      final repository = ref.read(rfidTagRepositoryProvider);
      final tag = await repository.createTag(epc, createdBy);

      // Invalidate tag lists to refresh
      _invalidateTagLists();

      AppLogger.info('Tag created successfully');
      return tag;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create tag', error, stackTrace);
      rethrow;
    }
  }

  /// Create and write a tag (convenience for bulk write workflow)
  Future<RfidTag> createAndWriteTag({
    required String epc,
    required String? createdBy,
    String? tid,
  }) async {
    try {
      final repository = ref.read(rfidTagRepositoryProvider);
      final tag = await repository.createAndWriteTag(
        epc: epc,
        createdBy: createdBy,
        tid: tid,
      );

      // Invalidate tag lists to refresh
      _invalidateTagLists();

      AppLogger.info('Tag created and written successfully');
      return tag;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create and write tag', error, stackTrace);
      rethrow;
    }
  }

  /// Update tag status
  Future<RfidTag> updateTagStatus(
    String id,
    RfidTagStatus status, {
    String? tid,
  }) async {
    try {
      final repository = ref.read(rfidTagRepositoryProvider);
      final tag = await repository.updateTagStatus(id, status, tid: tid);

      // Invalidate related providers
      _invalidateTagLists();
      ref.invalidate(rfidTagByIdProvider(id));

      AppLogger.info('Tag status updated successfully');
      return tag;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update tag status', error, stackTrace);
      rethrow;
    }
  }

  /// Retire a tag
  Future<RfidTag> retireTag(String id) async {
    try {
      final repository = ref.read(rfidTagRepositoryProvider);
      final tag = await repository.retireTag(id);

      // Invalidate related providers
      _invalidateTagLists();
      ref.invalidate(rfidTagByIdProvider(id));

      AppLogger.info('Tag retired successfully');
      return tag;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to retire tag', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a tag
  Future<void> deleteTag(String id) async {
    try {
      final repository = ref.read(rfidTagRepositoryProvider);
      await repository.deleteTag(id);

      // Invalidate tag lists
      _invalidateTagLists();

      AppLogger.info('Tag deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete tag', error, stackTrace);
      rethrow;
    }
  }

  /// Bulk lookup tags by EPCs
  Future<List<RfidTag>> getTagsByEpcs(List<String> epcs) async {
    try {
      final repository = ref.read(rfidTagRepositoryProvider);
      return await repository.getTagsByEpcs(epcs);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to bulk lookup tags', error, stackTrace);
      rethrow;
    }
  }

  /// Invalidate all tag list providers to trigger refresh
  void _invalidateTagLists() {
    ref.invalidate(allRfidTagsProvider);
    ref.invalidate(totalRfidTagCountProvider);
    // Note: rfidTagsProvider and rfidTagCountProvider are family providers
    // and will be invalidated when their specific filters/statuses are accessed again
  }

  /// Manually refresh all tag data
  void refreshTags() {
    _invalidateTagLists();
  }
}

/// State notifier for managing current tag filter
class TagFilterNotifier extends StateNotifier<TagFilter> {
  TagFilterNotifier() : super(TagFilter.defaultFilter);

  void setStatus(RfidTagStatus? status) {
    state = state.copyWith(status: status, clearStatus: status == null);
  }

  void setSearchQuery(String? query) {
    state = state.copyWith(
      searchQuery: query,
      clearSearch: query == null || query.isEmpty,
    );
  }

  void setSortBy(TagSortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  void setSortAscending(bool ascending) {
    state = state.copyWith(sortAscending: ascending);
  }

  void reset() {
    state = TagFilter.defaultFilter;
  }
}

/// Provider for current tag filter state
final tagFilterProvider =
    StateNotifierProvider<TagFilterNotifier, TagFilter>((ref) {
  return TagFilterNotifier();
});

/// Provider for tags using the current filter state
final filteredRfidTagsProvider = FutureProvider<List<RfidTag>>((ref) async {
  final filter = ref.watch(tagFilterProvider);
  final repository = ref.watch(rfidTagRepositoryProvider);
  return await repository.getTags(filter: filter);
});
