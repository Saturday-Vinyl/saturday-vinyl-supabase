import 'dart:ui';

import 'package:saturday_consumer_app/config/env_config.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/services/supabase_service.dart';

/// Metadata for a product image asset (frame image per variant/angle).
class ProductImageAsset {
  final String id;
  final String variantId;
  final String angle;
  final String framePath;
  final int imageWidth;
  final int imageHeight;

  const ProductImageAsset({
    required this.id,
    required this.variantId,
    required this.angle,
    required this.framePath,
    required this.imageWidth,
    required this.imageHeight,
  });

  factory ProductImageAsset.fromJson(Map<String, dynamic> json) {
    return ProductImageAsset(
      id: json['id'] as String,
      variantId: json['variant_id'] as String,
      angle: json['angle'] as String,
      framePath: json['frame_path'] as String,
      imageWidth: json['image_width'] as int,
      imageHeight: json['image_height'] as int,
    );
  }

  String get frameUrl =>
      '${EnvConfig.supabaseUrl}/storage/v1/object/public/$framePath';
}

/// Defines how an album cover is composited into a product image slot.
///
/// Stored per product/angle/capacity (shared across all variants).
/// Contains the perspective transform (4 corners) and occlusion clip path.
class ProductImageSlot {
  final String id;
  final String productId;
  final String angle;
  final String capacity;

  /// 4 destination corners for perspective-mapping a square album cover.
  /// Order: top-left, top-right, bottom-right, bottom-left.
  /// Coordinates are in source image pixels.
  final List<Offset> transform;

  /// N-point polygon defining the visible area after crate occlusion.
  /// Coordinates are in source image pixels.
  final List<Offset> clip;

  const ProductImageSlot({
    required this.id,
    required this.productId,
    required this.angle,
    required this.capacity,
    required this.transform,
    required this.clip,
  });

  factory ProductImageSlot.fromJson(Map<String, dynamic> json) {
    final slotData = json['slot_data'] as Map<String, dynamic>? ?? {};

    final rawTransform = slotData['transform'] as List<dynamic>? ?? [];
    final transform = rawTransform
        .map((p) => Offset(
              (p['x'] as num).toDouble(),
              (p['y'] as num).toDouble(),
            ))
        .toList();

    final rawClip = slotData['clip'] as List<dynamic>? ?? [];
    final clip = rawClip
        .map((p) => Offset(
              (p['x'] as num).toDouble(),
              (p['y'] as num).toDouble(),
            ))
        .toList();

    return ProductImageSlot(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      angle: json['angle'] as String,
      capacity: json['capacity'] as String? ?? 'full',
      transform: transform,
      clip: clip,
    );
  }

  /// Whether this slot has valid data for compositing.
  bool get isValid => transform.length == 4 && clip.length >= 3;
}

/// Service for resolving product image URLs and fetching image metadata.
class ProductImageService {
  static const _assetsTable = 'product_image_assets';
  static const _slotsTable = 'product_image_slots';
  static const _bucketName = 'product-images';

  /// Builds the deterministic storage path for a product frame image.
  static String framePath(String productHandle, String sku, String angle) {
    return '$_bucketName/$productHandle/$sku/$angle.png';
  }

  /// Builds the full public URL for a product frame image.
  static String frameUrl(String productHandle, String sku, String angle) {
    return '${EnvConfig.supabaseUrl}/storage/v1/object/public/${framePath(productHandle, sku, angle)}';
  }

  /// Builds the full public URL for a product frame image from a device.
  static String? frameUrlForDevice(Device device, {String angle = 'front'}) {
    if (!device.hasProductImageData) return null;
    return frameUrl(device.productHandle!, device.sku!, angle);
  }

  /// Fetches image asset metadata for a specific variant and angle.
  static Future<ProductImageAsset?> getAsset({
    required String variantId,
    required String angle,
  }) async {
    final response = await SupabaseService.instance.client
        .from(_assetsTable)
        .select()
        .eq('variant_id', variantId)
        .eq('angle', angle)
        .maybeSingle();

    if (response == null) return null;
    return ProductImageAsset.fromJson(response);
  }

  /// Fetches slot compositing data for a product/angle/capacity.
  static Future<ProductImageSlot?> getSlot({
    required String productId,
    required String angle,
    String capacity = 'full',
  }) async {
    final response = await SupabaseService.instance.client
        .from(_slotsTable)
        .select()
        .eq('product_id', productId)
        .eq('angle', angle)
        .eq('capacity', capacity)
        .maybeSingle();

    if (response == null) return null;
    return ProductImageSlot.fromJson(response);
  }
}
