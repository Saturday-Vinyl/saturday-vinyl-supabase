import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing parts
class PartsRepository {
  final _supabase = SupabaseService.instance.client;
  final _uuid = const Uuid();

  /// Get all active parts, optionally filtered by type and/or category
  Future<List<Part>> getParts({PartType? type, PartCategory? category}) async {
    try {
      var query = _supabase
          .from('parts')
          .select()
          .eq('is_active', true);

      if (type != null) {
        query = query.eq('part_type', type.value);
      }
      if (category != null) {
        query = query.eq('category', category.value);
      }

      final response = await query.order('name');

      return (response as List)
          .map((json) => Part.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch parts', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single part by ID
  Future<Part?> getPart(String id) async {
    try {
      final response = await _supabase
          .from('parts')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return Part.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch part $id', error, stackTrace);
      rethrow;
    }
  }

  /// Search parts by name or part number
  Future<List<Part>> searchParts(String query) async {
    try {
      final response = await _supabase
          .from('parts')
          .select()
          .eq('is_active', true)
          .or('name.ilike.%$query%,part_number.ilike.%$query%')
          .order('name');

      return (response as List)
          .map((json) => Part.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to search parts', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new part
  Future<Part> createPart({
    required String name,
    required String partNumber,
    String? description,
    required PartType partType,
    required PartCategory category,
    required UnitOfMeasure unitOfMeasure,
    double? reorderThreshold,
  }) async {
    try {
      final id = _uuid.v4();
      final now = DateTime.now();

      await _supabase.from('parts').insert({
        'id': id,
        'name': name,
        'part_number': partNumber,
        'description': description,
        'part_type': partType.value,
        'category': category.value,
        'unit_of_measure': unitOfMeasure.value,
        'reorder_threshold': reorderThreshold,
        'is_active': true,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      AppLogger.info('Created part: $name ($partNumber)');

      return Part(
        id: id,
        name: name,
        partNumber: partNumber,
        description: description,
        partType: partType,
        category: category,
        unitOfMeasure: unitOfMeasure,
        reorderThreshold: reorderThreshold,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create part', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing part
  Future<Part> updatePart(
    String id, {
    String? name,
    String? partNumber,
    String? description,
    PartType? partType,
    PartCategory? category,
    UnitOfMeasure? unitOfMeasure,
    double? reorderThreshold,
  }) async {
    try {
      final now = DateTime.now();
      final updates = <String, dynamic>{
        'updated_at': now.toIso8601String(),
      };

      if (name != null) updates['name'] = name;
      if (partNumber != null) updates['part_number'] = partNumber;
      if (description != null) updates['description'] = description;
      if (partType != null) updates['part_type'] = partType.value;
      if (category != null) updates['category'] = category.value;
      if (unitOfMeasure != null) updates['unit_of_measure'] = unitOfMeasure.value;
      if (reorderThreshold != null) updates['reorder_threshold'] = reorderThreshold;

      await _supabase.from('parts').update(updates).eq('id', id);

      AppLogger.info('Updated part: $id');

      final part = await getPart(id);
      if (part == null) throw Exception('Part not found after update');
      return part;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update part $id', error, stackTrace);
      rethrow;
    }
  }

  /// Soft delete a part
  Future<void> deletePart(String id) async {
    try {
      await _supabase.from('parts').update({
        'is_active': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      AppLogger.info('Deleted part: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete part $id', error, stackTrace);
      rethrow;
    }
  }

  /// Get inventory level for a single part
  Future<double> getInventoryLevel(String partId) async {
    try {
      final response = await _supabase
          .from('inventory_levels')
          .select('quantity_on_hand')
          .eq('part_id', partId)
          .maybeSingle();

      if (response == null) return 0.0;
      return (response['quantity_on_hand'] as num).toDouble();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get inventory level for $partId', error, stackTrace);
      rethrow;
    }
  }

  /// Get inventory levels for all parts
  Future<Map<String, double>> getInventoryLevels() async {
    try {
      final response = await _supabase
          .from('inventory_levels')
          .select();

      final levels = <String, double>{};
      for (final row in response as List) {
        final map = row as Map<String, dynamic>;
        levels[map['part_id'] as String] =
            (map['quantity_on_hand'] as num).toDouble();
      }
      return levels;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get inventory levels', error, stackTrace);
      rethrow;
    }
  }
}
