import 'package:equatable/equatable.dart';

/// BOM line defining a part needed to build one unit of a product
class BomLine extends Equatable {
  final String id;
  final String productId;
  final String partId;
  final String? productionStepId;
  final double quantity;
  final String? notes;

  const BomLine({
    required this.id,
    required this.productId,
    required this.partId,
    this.productionStepId,
    required this.quantity,
    this.notes,
  });

  factory BomLine.fromJson(Map<String, dynamic> json) {
    return BomLine(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      partId: json['part_id'] as String,
      productionStepId: json['production_step_id'] as String?,
      quantity: (json['quantity'] as num).toDouble(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'part_id': partId,
      'production_step_id': productionStepId,
      'quantity': quantity,
      'notes': notes,
    };
  }

  BomLine copyWith({
    String? id,
    String? productId,
    String? partId,
    String? productionStepId,
    double? quantity,
    String? notes,
  }) {
    return BomLine(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      partId: partId ?? this.partId,
      productionStepId: productionStepId ?? this.productionStepId,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [
        id, productId, partId, productionStepId, quantity, notes,
      ];

  @override
  String toString() =>
      'BomLine(id: $id, product: $productId, part: $partId, qty: $quantity)';
}
