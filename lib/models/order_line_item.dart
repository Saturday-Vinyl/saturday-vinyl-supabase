import 'package:equatable/equatable.dart';

/// Represents a line item (product/variant) in an order
class OrderLineItem extends Equatable {
  final String id;
  final String orderId;
  final String? productId; // Maps to our internal product ID
  final String? variantId; // Maps to our internal variant ID
  final String shopifyProductId; // Shopify's product ID
  final String shopifyVariantId; // Shopify's variant ID
  final String title; // Product title from Shopify
  final int quantity;
  final String? price; // Price as string (e.g., "29.99")
  final String? variantTitle; // Variant title (e.g., "Quarter Sawn White Oak / Natural Wool")
  final String? variantOptions; // Formatted variant options (e.g., "Wood: Walnut, Liner: Black")

  const OrderLineItem({
    required this.id,
    required this.orderId,
    this.productId,
    this.variantId,
    required this.shopifyProductId,
    required this.shopifyVariantId,
    required this.title,
    required this.quantity,
    this.price,
    this.variantTitle,
    this.variantOptions,
  });

  /// Create from JSON (database format)
  factory OrderLineItem.fromJson(Map<String, dynamic> json) {
    return OrderLineItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      productId: json['product_id'] as String?,
      variantId: json['variant_id'] as String?,
      shopifyProductId: json['shopify_product_id'] as String,
      shopifyVariantId: json['shopify_variant_id'] as String,
      title: json['title'] as String,
      quantity: json['quantity'] as int,
      price: json['price'] as String?,
      variantTitle: json['variant_title'] as String?,
      variantOptions: json['variant_options'] as String?,
    );
  }

  /// Create from Shopify GraphQL response
  factory OrderLineItem.fromShopify(Map<String, dynamic> shopifyData, String orderId) {
    final variant = shopifyData['variant'] as Map<String, dynamic>?;
    final product = variant?['product'] as Map<String, dynamic>?;

    // Extract price
    String? price;
    final priceSet = shopifyData['originalUnitPriceSet'] as Map<String, dynamic>?;
    if (priceSet != null) {
      final shopMoney = priceSet['shopMoney'] as Map<String, dynamic>?;
      if (shopMoney != null) {
        final amount = shopMoney['amount'] as String?;
        final currency = shopMoney['currencyCode'] as String?;
        price = currency != null ? '$currency $amount' : amount;
      }
    }

    // Extract variant title
    final variantTitle = variant?['title'] as String?;

    // Format variant options (e.g., "Wood: Walnut, Liner: Black")
    String? variantOptions;
    final selectedOptions = variant?['selectedOptions'] as List<dynamic>?;
    if (selectedOptions != null && selectedOptions.isNotEmpty) {
      variantOptions = selectedOptions
          .map((opt) {
            final option = opt as Map<String, dynamic>;
            final name = option['name'] as String? ?? '';
            final value = option['value'] as String? ?? '';
            return '$name: $value';
          })
          .join(', ');
    }

    return OrderLineItem(
      id: '', // Will be generated when inserted to database
      orderId: orderId,
      productId: null, // Will be matched during sync
      variantId: null, // Will be matched during sync
      shopifyProductId: product?['id'] as String? ?? '',
      shopifyVariantId: variant?['id'] as String? ?? '',
      title: shopifyData['title'] as String? ?? 'Unknown Product',
      quantity: shopifyData['quantity'] as int? ?? 1,
      price: price,
      variantTitle: variantTitle,
      variantOptions: variantOptions,
    );
  }

  /// Convert to JSON (database format)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'product_id': productId,
      'variant_id': variantId,
      'shopify_product_id': shopifyProductId,
      'shopify_variant_id': shopifyVariantId,
      'title': title,
      'quantity': quantity,
      'price': price,
      'variant_title': variantTitle,
      'variant_options': variantOptions,
    };
  }

  /// Copy with method
  OrderLineItem copyWith({
    String? id,
    String? orderId,
    String? productId,
    String? variantId,
    String? shopifyProductId,
    String? shopifyVariantId,
    String? title,
    int? quantity,
    String? price,
    String? variantTitle,
    String? variantOptions,
  }) {
    return OrderLineItem(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      shopifyProductId: shopifyProductId ?? this.shopifyProductId,
      shopifyVariantId: shopifyVariantId ?? this.shopifyVariantId,
      title: title ?? this.title,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      variantTitle: variantTitle ?? this.variantTitle,
      variantOptions: variantOptions ?? this.variantOptions,
    );
  }

  @override
  List<Object?> get props => [
        id,
        orderId,
        productId,
        variantId,
        shopifyProductId,
        shopifyVariantId,
        title,
        quantity,
        price,
        variantTitle,
        variantOptions,
      ];

  @override
  String toString() {
    return 'OrderLineItem(id: $id, title: $title, quantity: $quantity)';
  }
}
