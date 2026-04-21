import 'package:saturday_app/models/sub_assembly_line.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing sub-assembly component lines
class SubAssemblyRepository {
  final _supabase = SupabaseService.instance.client;
  final _uuid = const Uuid();

  /// Get all component lines for a sub-assembly part
  Future<List<SubAssemblyLine>> getSubAssemblyLines(String parentPartId) async {
    try {
      final response = await _supabase
          .from('sub_assembly_lines')
          .select()
          .eq('parent_part_id', parentPartId)
          .order('reference_designator');

      return (response as List)
          .map((json) => SubAssemblyLine.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to fetch sub-assembly lines for $parentPartId', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new sub-assembly line
  Future<SubAssemblyLine> createSubAssemblyLine({
    required String parentPartId,
    required String childPartId,
    required double quantity,
    String? referenceDesignator,
    String? notes,
  }) async {
    try {
      final id = _uuid.v4();

      await _supabase.from('sub_assembly_lines').insert({
        'id': id,
        'parent_part_id': parentPartId,
        'child_part_id': childPartId,
        'quantity': quantity,
        'reference_designator': referenceDesignator,
        'notes': notes,
      });

      AppLogger.info('Created sub-assembly line for $parentPartId');

      return SubAssemblyLine(
        id: id,
        parentPartId: parentPartId,
        childPartId: childPartId,
        quantity: quantity,
        referenceDesignator: referenceDesignator,
        notes: notes,
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create sub-assembly line', error, stackTrace);
      rethrow;
    }
  }

  /// Update a sub-assembly line
  Future<void> updateSubAssemblyLine(
    String id, {
    String? childPartId,
    double? quantity,
    String? referenceDesignator,
    String? notes,
    bool? isBoardAssembled,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (childPartId != null) updates['child_part_id'] = childPartId;
      if (quantity != null) updates['quantity'] = quantity;
      if (referenceDesignator != null) updates['reference_designator'] = referenceDesignator;
      if (notes != null) updates['notes'] = notes;
      if (isBoardAssembled != null) updates['is_board_assembled'] = isBoardAssembled;

      await _supabase.from('sub_assembly_lines').update(updates).eq('id', id);
      AppLogger.info('Updated sub-assembly line: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update sub-assembly line $id', error, stackTrace);
      rethrow;
    }
  }

  /// Count how many sub-assembly lines reference a part as a child component
  Future<int> countUsagesAsChild(String childPartId) async {
    try {
      final response = await _supabase
          .from('sub_assembly_lines')
          .select('id')
          .eq('child_part_id', childPartId);

      return (response as List).length;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to count usages for $childPartId', error, stackTrace);
      return 0;
    }
  }

  /// Returns part IDs that are used in sub-assemblies but ONLY as
  /// board-assembled components (i.e. every usage has is_board_assembled=true).
  Future<Set<String>> getBoardAssembledOnlyPartIds() async {
    try {
      final response = await _supabase
          .from('sub_assembly_lines')
          .select('child_part_id, is_board_assembled');

      final rows = response as List;
      // Group by child_part_id: track whether ALL usages are board-assembled
      final allBoardAssembled = <String, bool>{};
      for (final row in rows) {
        final json = row as Map<String, dynamic>;
        final partId = json['child_part_id'] as String;
        final isBa = json['is_board_assembled'] as bool? ?? false;
        // If any usage is NOT board-assembled, mark as false
        allBoardAssembled[partId] = (allBoardAssembled[partId] ?? true) && isBa;
      }

      return allBoardAssembled.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toSet();
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get board-assembled-only part IDs', error, stackTrace);
      return {};
    }
  }

  /// Reassign all sub-assembly lines referencing one child part to another.
  /// Handles unique constraint (parent_part_id, child_part_id, reference_designator)
  /// by attempting each row individually and deleting duplicates.
  Future<void> reassignChildPart(String fromPartId, String toPartId) async {
    try {
      final response = await _supabase
          .from('sub_assembly_lines')
          .select()
          .eq('child_part_id', fromPartId);

      final rows = (response as List)
          .map((json) => SubAssemblyLine.fromJson(json as Map<String, dynamic>))
          .toList();

      for (final line in rows) {
        try {
          await _supabase
              .from('sub_assembly_lines')
              .update({'child_part_id': toPartId})
              .eq('id', line.id);
        } catch (_) {
          // Unique constraint conflict — delete the duplicate row
          await _supabase
              .from('sub_assembly_lines')
              .delete()
              .eq('id', line.id);
          AppLogger.info(
              'Deleted duplicate sub-assembly line ${line.id} during merge');
        }
      }
      AppLogger.info(
          'Reassigned sub-assembly child from $fromPartId to $toPartId');
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to reassign sub-assembly child', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a sub-assembly line
  Future<void> deleteSubAssemblyLine(String id) async {
    try {
      await _supabase.from('sub_assembly_lines').delete().eq('id', id);
      AppLogger.info('Deleted sub-assembly line: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete sub-assembly line $id', error, stackTrace);
      rethrow;
    }
  }
}
