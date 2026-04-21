import 'package:saturday_app/models/product_image_asset.dart';
import 'package:saturday_app/models/product_image_slot.dart';
import 'package:saturday_app/models/slot_data.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing product image slots and frame image assets
class ImageSlotRepository {
  final _supabase = SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // product_image_slots
  // ---------------------------------------------------------------------------

  /// Get a slot for a specific product/angle/capacity combination
  Future<ProductImageSlot?> getSlot(
    String productId,
    String angle,
    String capacity,
  ) async {
    try {
      final response = await _supabase
          .from('product_image_slots')
          .select()
          .eq('product_id', productId)
          .eq('angle', angle)
          .eq('capacity', capacity)
          .maybeSingle();

      if (response == null) return null;
      return ProductImageSlot.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get image slot', error, stackTrace);
      rethrow;
    }
  }

  /// Get all slots for a product
  Future<List<ProductImageSlot>> getSlotsForProduct(String productId) async {
    try {
      final response = await _supabase
          .from('product_image_slots')
          .select()
          .eq('product_id', productId)
          .order('angle')
          .order('capacity');

      return response.map<ProductImageSlot>((json) => ProductImageSlot.fromJson(json)).toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get image slots for product', error, stackTrace);
      rethrow;
    }
  }

  /// Upsert a slot (insert or update based on unique constraint)
  Future<ProductImageSlot> upsertSlot({
    required String productId,
    required String angle,
    required String capacity,
    required SlotData slotData,
  }) async {
    try {
      final data = {
        'product_id': productId,
        'angle': angle,
        'capacity': capacity,
        'slot_data': slotData.toJson(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from('product_image_slots')
          .upsert(data, onConflict: 'product_id,angle,capacity')
          .select()
          .single();

      AppLogger.info('Upserted image slot for $productId/$angle/$capacity');
      return ProductImageSlot.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upsert image slot', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a slot
  Future<void> deleteSlot(String slotId) async {
    try {
      await _supabase
          .from('product_image_slots')
          .delete()
          .eq('id', slotId);

      AppLogger.info('Deleted image slot $slotId');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete image slot', error, stackTrace);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // product_image_assets
  // ---------------------------------------------------------------------------

  /// Get all assets for a specific product (across all its variants)
  Future<List<ProductImageAsset>> getAssetsForProduct(String productId) async {
    try {
      final response = await _supabase
          .from('product_image_assets')
          .select('*, product_variants!inner(product_id)')
          .eq('product_variants.product_id', productId)
          .order('angle');

      return response.map<ProductImageAsset>((json) => ProductImageAsset.fromJson(json)).toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get image assets for product', error, stackTrace);
      rethrow;
    }
  }

  /// Get all assets for a specific variant
  Future<List<ProductImageAsset>> getAssetsForVariant(String variantId) async {
    try {
      final response = await _supabase
          .from('product_image_assets')
          .select()
          .eq('variant_id', variantId)
          .order('angle');

      return response.map<ProductImageAsset>((json) => ProductImageAsset.fromJson(json)).toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get image assets for variant', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single asset for a variant/angle
  Future<ProductImageAsset?> getAsset(String variantId, String angle) async {
    try {
      final response = await _supabase
          .from('product_image_assets')
          .select()
          .eq('variant_id', variantId)
          .eq('angle', angle)
          .maybeSingle();

      if (response == null) return null;
      return ProductImageAsset.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get image asset', error, stackTrace);
      rethrow;
    }
  }

  /// Upsert a frame image asset
  Future<ProductImageAsset> upsertAsset({
    required String variantId,
    required String angle,
    required String framePath,
    required int imageWidth,
    required int imageHeight,
  }) async {
    try {
      final data = {
        'variant_id': variantId,
        'angle': angle,
        'frame_path': framePath,
        'image_width': imageWidth,
        'image_height': imageHeight,
      };

      final response = await _supabase
          .from('product_image_assets')
          .upsert(data, onConflict: 'variant_id,angle')
          .select()
          .single();

      AppLogger.info('Upserted image asset for variant $variantId/$angle');
      return ProductImageAsset.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to upsert image asset', error, stackTrace);
      rethrow;
    }
  }
}
