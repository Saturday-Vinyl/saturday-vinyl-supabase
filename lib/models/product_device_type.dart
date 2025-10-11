import 'package:equatable/equatable.dart';

/// ProductDeviceType model representing the join table between products and device types
/// Indicates which devices are used in a product and how many
class ProductDeviceType extends Equatable {
  final String productId; // Foreign key to Product
  final String deviceTypeId; // Foreign key to DeviceType
  final int quantity; // Number of this device type used in the product

  const ProductDeviceType({
    required this.productId,
    required this.deviceTypeId,
    required this.quantity,
  });

  /// Create ProductDeviceType from JSON
  factory ProductDeviceType.fromJson(Map<String, dynamic> json) {
    return ProductDeviceType(
      productId: json['product_id'] as String,
      deviceTypeId: json['device_type_id'] as String,
      quantity: json['quantity'] as int,
    );
  }

  /// Convert ProductDeviceType to JSON
  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'device_type_id': deviceTypeId,
      'quantity': quantity,
    };
  }

  /// Create a copy of ProductDeviceType with updated fields
  ProductDeviceType copyWith({
    String? productId,
    String? deviceTypeId,
    int? quantity,
  }) {
    return ProductDeviceType(
      productId: productId ?? this.productId,
      deviceTypeId: deviceTypeId ?? this.deviceTypeId,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  List<Object?> get props => [productId, deviceTypeId, quantity];

  @override
  String toString() {
    return 'ProductDeviceType(productId: $productId, deviceTypeId: $deviceTypeId, quantity: $quantity)';
  }
}
