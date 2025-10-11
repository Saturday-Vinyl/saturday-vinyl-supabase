import 'package:equatable/equatable.dart';

/// ProductVariant model representing a variant of a product from Shopify
class ProductVariant extends Equatable {
  final String id; // UUID (internal database ID)
  final String productId; // Foreign key to Product
  final String shopifyVariantId; // Shopify's variant ID
  final String sku;
  final String name;
  final String? option1Name; // e.g., "Wood Species"
  final String? option1Value; // e.g., "Walnut"
  final String? option2Name; // e.g., "Liner Color"
  final String? option2Value; // e.g., "Black"
  final String? option3Name; // e.g., "Size"
  final String? option3Value; // e.g., "Large"
  final double price;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductVariant({
    required this.id,
    required this.productId,
    required this.shopifyVariantId,
    required this.sku,
    required this.name,
    this.option1Name,
    this.option1Value,
    this.option2Name,
    this.option2Value,
    this.option3Name,
    this.option3Value,
    required this.price,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Get formatted variant name (e.g., "Walnut / Black Liner")
  String getFormattedVariantName() {
    final options = <String>[];

    if (option1Value != null && option1Value!.isNotEmpty) {
      options.add(option1Value!);
    }
    if (option2Value != null && option2Value!.isNotEmpty) {
      options.add(option2Value!);
    }
    if (option3Value != null && option3Value!.isNotEmpty) {
      options.add(option3Value!);
    }

    return options.isEmpty ? name : options.join(' / ');
  }

  /// Create ProductVariant from JSON
  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      shopifyVariantId: json['shopify_variant_id'] as String,
      sku: json['sku'] as String,
      name: json['name'] as String,
      option1Name: json['option1_name'] as String?,
      option1Value: json['option1_value'] as String?,
      option2Name: json['option2_name'] as String?,
      option2Value: json['option2_value'] as String?,
      option3Name: json['option3_name'] as String?,
      option3Value: json['option3_value'] as String?,
      price: (json['price'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert ProductVariant to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'shopify_variant_id': shopifyVariantId,
      'sku': sku,
      'name': name,
      'option1_name': option1Name,
      'option1_value': option1Value,
      'option2_name': option2Name,
      'option2_value': option2Value,
      'option3_name': option3Name,
      'option3_value': option3Value,
      'price': price,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of ProductVariant with updated fields
  ProductVariant copyWith({
    String? id,
    String? productId,
    String? shopifyVariantId,
    String? sku,
    String? name,
    String? option1Name,
    String? option1Value,
    String? option2Name,
    String? option2Value,
    String? option3Name,
    String? option3Value,
    double? price,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductVariant(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      shopifyVariantId: shopifyVariantId ?? this.shopifyVariantId,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      option1Name: option1Name ?? this.option1Name,
      option1Value: option1Value ?? this.option1Value,
      option2Name: option2Name ?? this.option2Name,
      option2Value: option2Value ?? this.option2Value,
      option3Name: option3Name ?? this.option3Name,
      option3Value: option3Value ?? this.option3Value,
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        productId,
        shopifyVariantId,
        sku,
        name,
        option1Name,
        option1Value,
        option2Name,
        option2Value,
        option3Name,
        option3Value,
        price,
        isActive,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'ProductVariant(id: $id, sku: $sku, name: ${getFormattedVariantName()})';
  }
}
