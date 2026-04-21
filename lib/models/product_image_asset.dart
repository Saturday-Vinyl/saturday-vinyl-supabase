import 'package:equatable/equatable.dart';

/// A frame image asset for a specific product variant and angle.
///
/// Assets are variant-specific — different wood finishes get different images.
class ProductImageAsset extends Equatable {
  final String id;
  final String variantId;
  final String angle;
  final String framePath;
  final int imageWidth;
  final int imageHeight;
  final DateTime createdAt;

  const ProductImageAsset({
    required this.id,
    required this.variantId,
    required this.angle,
    required this.framePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.createdAt,
  });

  factory ProductImageAsset.fromJson(Map<String, dynamic> json) {
    return ProductImageAsset(
      id: json['id'] as String,
      variantId: json['variant_id'] as String,
      angle: json['angle'] as String,
      framePath: json['frame_path'] as String,
      imageWidth: json['image_width'] as int,
      imageHeight: json['image_height'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'variant_id': variantId,
      'angle': angle,
      'frame_path': framePath,
      'image_width': imageWidth,
      'image_height': imageHeight,
      'created_at': createdAt.toIso8601String(),
    };
  }

  ProductImageAsset copyWith({
    String? id,
    String? variantId,
    String? angle,
    String? framePath,
    int? imageWidth,
    int? imageHeight,
    DateTime? createdAt,
  }) {
    return ProductImageAsset(
      id: id ?? this.id,
      variantId: variantId ?? this.variantId,
      angle: angle ?? this.angle,
      framePath: framePath ?? this.framePath,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Get the public URL for this frame image from Supabase Storage.
  String getPublicUrl(String supabaseUrl) {
    return '$supabaseUrl/storage/v1/object/public/product-images/$framePath';
  }

  @override
  List<Object?> get props => [
        id,
        variantId,
        angle,
        framePath,
        imageWidth,
        imageHeight,
        createdAt,
      ];

  @override
  String toString() {
    return 'ProductImageAsset(id: $id, variant: $variantId, angle: $angle, ${imageWidth}x$imageHeight)';
  }
}
