import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/product_image_asset.dart';
import 'package:saturday_app/models/product_image_slot.dart';
import 'package:saturday_app/models/slot_data.dart';
import 'package:saturday_app/repositories/image_slot_repository.dart';
import 'package:saturday_app/services/supabase_service.dart';

/// Provider for ImageSlotRepository
final imageSlotRepositoryProvider = Provider<ImageSlotRepository>((ref) {
  return ImageSlotRepository();
});

/// All slots for a product
final productImageSlotsProvider =
    FutureProvider.family<List<ProductImageSlot>, String>((ref, productId) async {
  final repository = ref.watch(imageSlotRepositoryProvider);
  return await repository.getSlotsForProduct(productId);
});

/// All frame image assets for a product (across all variants)
final productImageAssetsProvider =
    FutureProvider.family<List<ProductImageAsset>, String>((ref, productId) async {
  final repository = ref.watch(imageSlotRepositoryProvider);
  return await repository.getAssetsForProduct(productId);
});

/// Frame image assets for a single variant
final variantImageAssetsProvider =
    FutureProvider.family<List<ProductImageAsset>, String>((ref, variantId) async {
  final repository = ref.watch(imageSlotRepositoryProvider);
  return await repository.getAssetsForVariant(variantId);
});

/// Public URL for a frame image path (product-images bucket is public)
final frameImageUrlProvider = Provider.family<String, String>((ref, framePath) {
  return SupabaseService.instance.client.storage
      .from('product-images')
      .getPublicUrl(framePath);
});

/// Management class for image slot and asset CRUD operations
final imageSlotManagementProvider = Provider<ImageSlotManagement>((ref) {
  return ImageSlotManagement(ref);
});

class ImageSlotManagement {
  final Ref ref;

  ImageSlotManagement(this.ref);

  /// Save (upsert) a slot
  Future<ProductImageSlot> saveSlot({
    required String productId,
    required String angle,
    required String capacity,
    required SlotData slotData,
  }) async {
    final repository = ref.read(imageSlotRepositoryProvider);
    final result = await repository.upsertSlot(
      productId: productId,
      angle: angle,
      capacity: capacity,
      slotData: slotData,
    );

    ref.invalidate(productImageSlotsProvider(productId));
    return result;
  }

  /// Delete a slot
  Future<void> deleteSlot(String slotId, String productId) async {
    final repository = ref.read(imageSlotRepositoryProvider);
    await repository.deleteSlot(slotId);

    ref.invalidate(productImageSlotsProvider(productId));
  }

  /// Save (upsert) a frame image asset
  Future<ProductImageAsset> saveAsset({
    required String variantId,
    required String productId,
    required String angle,
    required String framePath,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final repository = ref.read(imageSlotRepositoryProvider);
    final result = await repository.upsertAsset(
      variantId: variantId,
      angle: angle,
      framePath: framePath,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );

    ref.invalidate(variantImageAssetsProvider(variantId));
    ref.invalidate(productImageAssetsProvider(productId));
    return result;
  }
}
