import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/slot_data.dart';

/// A compositing slot definition for a product/angle/capacity combination.
///
/// Slots are product-level — the same geometry applies across all variants.
class ProductImageSlot extends Equatable {
  final String id;
  final String productId;
  final String angle;
  final String capacity;
  final SlotData slotData;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProductImageSlot({
    required this.id,
    required this.productId,
    required this.angle,
    required this.capacity,
    required this.slotData,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductImageSlot.fromJson(Map<String, dynamic> json) {
    return ProductImageSlot(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      angle: json['angle'] as String,
      capacity: json['capacity'] as String,
      slotData: SlotData.fromJson(json['slot_data'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'angle': angle,
      'capacity': capacity,
      'slot_data': slotData.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  ProductImageSlot copyWith({
    String? id,
    String? productId,
    String? angle,
    String? capacity,
    SlotData? slotData,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductImageSlot(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      angle: angle ?? this.angle,
      capacity: capacity ?? this.capacity,
      slotData: slotData ?? this.slotData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        productId,
        angle,
        capacity,
        slotData,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'ProductImageSlot(id: $id, product: $productId, angle: $angle, capacity: $capacity)';
  }
}
