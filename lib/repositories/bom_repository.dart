import 'package:saturday_app/models/bom_line.dart';
import 'package:saturday_app/models/bom_variant_override.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing BOMs and variant overrides
class BomRepository {
  final _supabase = SupabaseService.instance.client;
  final _uuid = const Uuid();

  /// Get all BOM lines for a product
  Future<List<BomLine>> getBomLines(String productId) async {
    try {
      final response = await _supabase
          .from('bom_lines')
          .select()
          .eq('product_id', productId)
          .order('created_at');

      return (response as List)
          .map((json) => BomLine.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch BOM lines for product $productId', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new BOM line
  Future<BomLine> createBomLine({
    required String productId,
    required String partId,
    String? productionStepId,
    required double quantity,
    String? notes,
  }) async {
    try {
      final id = _uuid.v4();

      await _supabase.from('bom_lines').insert({
        'id': id,
        'product_id': productId,
        'part_id': partId,
        'production_step_id': productionStepId,
        'quantity': quantity,
        'notes': notes,
      });

      AppLogger.info('Created BOM line for product $productId');

      return BomLine(
        id: id,
        productId: productId,
        partId: partId,
        productionStepId: productionStepId,
        quantity: quantity,
        notes: notes,
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create BOM line', error, stackTrace);
      rethrow;
    }
  }

  /// Update a BOM line
  Future<void> updateBomLine(
    String id, {
    String? partId,
    String? productionStepId,
    double? quantity,
    String? notes,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (partId != null) updates['part_id'] = partId;
      if (productionStepId != null) updates['production_step_id'] = productionStepId;
      if (quantity != null) updates['quantity'] = quantity;
      if (notes != null) updates['notes'] = notes;

      await _supabase.from('bom_lines').update(updates).eq('id', id);
      AppLogger.info('Updated BOM line: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update BOM line $id', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a BOM line
  Future<void> deleteBomLine(String id) async {
    try {
      await _supabase.from('bom_lines').delete().eq('id', id);
      AppLogger.info('Deleted BOM line: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete BOM line $id', error, stackTrace);
      rethrow;
    }
  }

  /// Get variant overrides for a specific BOM line
  Future<List<BomVariantOverride>> getVariantOverrides(String bomLineId) async {
    try {
      final response = await _supabase
          .from('bom_variant_overrides')
          .select()
          .eq('bom_line_id', bomLineId);

      return (response as List)
          .map((json) => BomVariantOverride.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch variant overrides for BOM line $bomLineId', error, stackTrace);
      rethrow;
    }
  }

  /// Get all variant overrides for a product variant
  Future<List<BomVariantOverride>> getVariantOverridesForProduct(
      String productId, String variantId) async {
    try {
      // Get all BOM lines for the product, then filter overrides by variant
      final bomLines = await getBomLines(productId);
      final bomLineIds = bomLines.map((l) => l.id).toList();

      if (bomLineIds.isEmpty) return [];

      final response = await _supabase
          .from('bom_variant_overrides')
          .select()
          .inFilter('bom_line_id', bomLineIds)
          .eq('variant_id', variantId);

      return (response as List)
          .map((json) => BomVariantOverride.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to fetch variant overrides for product $productId, variant $variantId',
          error, stackTrace);
      rethrow;
    }
  }

  /// Create a variant override
  Future<BomVariantOverride> createVariantOverride({
    required String bomLineId,
    required String variantId,
    required String partId,
    double? quantity,
  }) async {
    try {
      final id = _uuid.v4();

      await _supabase.from('bom_variant_overrides').insert({
        'id': id,
        'bom_line_id': bomLineId,
        'variant_id': variantId,
        'part_id': partId,
        'quantity': quantity,
      });

      AppLogger.info('Created variant override for BOM line $bomLineId');

      return BomVariantOverride(
        id: id,
        bomLineId: bomLineId,
        variantId: variantId,
        partId: partId,
        quantity: quantity,
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create variant override', error, stackTrace);
      rethrow;
    }
  }

  /// Update a variant override
  Future<void> updateVariantOverride(
    String id, {
    String? partId,
    double? quantity,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (partId != null) updates['part_id'] = partId;
      if (quantity != null) updates['quantity'] = quantity;

      await _supabase.from('bom_variant_overrides').update(updates).eq('id', id);
      AppLogger.info('Updated variant override: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update variant override $id', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a variant override
  Future<void> deleteVariantOverride(String id) async {
    try {
      await _supabase.from('bom_variant_overrides').delete().eq('id', id);
      AppLogger.info('Deleted variant override: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete variant override $id', error, stackTrace);
      rethrow;
    }
  }
}
