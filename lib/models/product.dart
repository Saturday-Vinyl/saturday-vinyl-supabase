import 'package:equatable/equatable.dart';

/// Product model representing a Saturday! product from Shopify
class Product extends Equatable {
  final String id; // UUID (internal database ID)
  final String shopifyProductId; // Shopify's product ID
  final String shopifyProductHandle; // Shopify's URL handle
  final String name;
  final String productCode; // e.g., "PROD1"
  final String? description;

  /// Short name for device provisioning (e.g., "Crate" not "Saturday Crate").
  /// Used in BLE advertising and mDNS hostnames.
  /// If null, derived from [name] by stripping "Saturday " prefix.
  final String? shortName;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastSyncedAt; // Last time synced from Shopify

  const Product({
    required this.id,
    required this.shopifyProductId,
    required this.shopifyProductHandle,
    required this.name,
    required this.productCode,
    this.description,
    this.shortName,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.lastSyncedAt,
  });

  /// Gets the device-friendly name for provisioning.
  /// Returns [shortName] if set, otherwise derives from [name] by stripping "Saturday " prefix.
  String get deviceName {
    if (shortName != null && shortName!.isNotEmpty) {
      return shortName!;
    }
    // Derive from full name
    if (name.startsWith('Saturday ')) {
      return name.substring(9);
    }
    return name;
  }

  /// Create Product from JSON
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      shopifyProductId: json['shopify_product_id'] as String,
      shopifyProductHandle: json['shopify_product_handle'] as String,
      name: json['name'] as String,
      productCode: json['product_code'] as String,
      description: json['description'] as String?,
      shortName: json['short_name'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastSyncedAt: json['last_synced_at'] != null
          ? DateTime.parse(json['last_synced_at'] as String)
          : null,
    );
  }

  /// Convert Product to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shopify_product_id': shopifyProductId,
      'shopify_product_handle': shopifyProductHandle,
      'name': name,
      'product_code': productCode,
      'description': description,
      'short_name': shortName,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_synced_at': lastSyncedAt?.toIso8601String(),
    };
  }

  /// Create a copy of Product with updated fields
  Product copyWith({
    String? id,
    String? shopifyProductId,
    String? shopifyProductHandle,
    String? name,
    String? productCode,
    String? description,
    String? shortName,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    return Product(
      id: id ?? this.id,
      shopifyProductId: shopifyProductId ?? this.shopifyProductId,
      shopifyProductHandle: shopifyProductHandle ?? this.shopifyProductHandle,
      name: name ?? this.name,
      productCode: productCode ?? this.productCode,
      description: description ?? this.description,
      shortName: shortName ?? this.shortName,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        shopifyProductId,
        shopifyProductHandle,
        name,
        productCode,
        description,
        shortName,
        isActive,
        createdAt,
        updatedAt,
        lastSyncedAt,
      ];

  @override
  String toString() {
    return 'Product(id: $id, name: $name, productCode: $productCode)';
  }
}
