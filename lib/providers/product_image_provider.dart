import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/services/product_image_service.dart';

/// Provider for fetching product image assets for a specific variant and angle.
///
/// Key format: "variantId:angle" (e.g., "abc-123:front").
final productImageAssetProvider =
    FutureProvider.family<ProductImageAsset?, String>((ref, key) async {
  final parts = key.split(':');
  if (parts.length != 2) return null;
  return ProductImageService.getAsset(variantId: parts[0], angle: parts[1]);
});

/// Provider for fetching product image slot data for a product/angle/capacity.
///
/// Key format: "productId:angle:capacity" (e.g., "abc-123:front:full").
final productImageSlotProvider =
    FutureProvider.family<ProductImageSlot?, String>((ref, key) async {
  final parts = key.split(':');
  if (parts.length != 3) return null;
  return ProductImageService.getSlot(
    productId: parts[0],
    angle: parts[1],
    capacity: parts[2],
  );
});
