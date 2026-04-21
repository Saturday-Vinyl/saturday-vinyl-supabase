import 'package:equatable/equatable.dart';

/// Override for a BOM line specific to a product variant
class BomVariantOverride extends Equatable {
  final String id;
  final String bomLineId;
  final String variantId;
  final String partId;
  final double? quantity;

  const BomVariantOverride({
    required this.id,
    required this.bomLineId,
    required this.variantId,
    required this.partId,
    this.quantity,
  });

  factory BomVariantOverride.fromJson(Map<String, dynamic> json) {
    return BomVariantOverride(
      id: json['id'] as String,
      bomLineId: json['bom_line_id'] as String,
      variantId: json['variant_id'] as String,
      partId: json['part_id'] as String,
      quantity: json['quantity'] != null
          ? (json['quantity'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bom_line_id': bomLineId,
      'variant_id': variantId,
      'part_id': partId,
      'quantity': quantity,
    };
  }

  BomVariantOverride copyWith({
    String? id,
    String? bomLineId,
    String? variantId,
    String? partId,
    double? quantity,
  }) {
    return BomVariantOverride(
      id: id ?? this.id,
      bomLineId: bomLineId ?? this.bomLineId,
      variantId: variantId ?? this.variantId,
      partId: partId ?? this.partId,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  List<Object?> get props => [id, bomLineId, variantId, partId, quantity];

  @override
  String toString() =>
      'BomVariantOverride(id: $id, bomLine: $bomLineId, variant: $variantId)';
}
