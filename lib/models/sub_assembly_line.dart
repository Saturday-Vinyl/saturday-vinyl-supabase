import 'package:equatable/equatable.dart';

/// Defines a component needed to build one unit of a sub-assembly
class SubAssemblyLine extends Equatable {
  final String id;
  final String parentPartId;
  final String childPartId;
  final double quantity;
  final String? referenceDesignator;
  final String? notes;
  final bool isBoardAssembled;

  const SubAssemblyLine({
    required this.id,
    required this.parentPartId,
    required this.childPartId,
    required this.quantity,
    this.referenceDesignator,
    this.notes,
    this.isBoardAssembled = false,
  });

  factory SubAssemblyLine.fromJson(Map<String, dynamic> json) {
    return SubAssemblyLine(
      id: json['id'] as String,
      parentPartId: json['parent_part_id'] as String,
      childPartId: json['child_part_id'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      referenceDesignator: json['reference_designator'] as String?,
      notes: json['notes'] as String?,
      isBoardAssembled: json['is_board_assembled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parent_part_id': parentPartId,
      'child_part_id': childPartId,
      'quantity': quantity,
      'reference_designator': referenceDesignator,
      'notes': notes,
      'is_board_assembled': isBoardAssembled,
    };
  }

  SubAssemblyLine copyWith({
    String? id,
    String? parentPartId,
    String? childPartId,
    double? quantity,
    String? referenceDesignator,
    String? notes,
    bool? isBoardAssembled,
  }) {
    return SubAssemblyLine(
      id: id ?? this.id,
      parentPartId: parentPartId ?? this.parentPartId,
      childPartId: childPartId ?? this.childPartId,
      quantity: quantity ?? this.quantity,
      referenceDesignator: referenceDesignator ?? this.referenceDesignator,
      notes: notes ?? this.notes,
      isBoardAssembled: isBoardAssembled ?? this.isBoardAssembled,
    );
  }

  @override
  List<Object?> get props => [
        id, parentPartId, childPartId, quantity, referenceDesignator, notes,
        isBoardAssembled,
      ];

  @override
  String toString() =>
      'SubAssemblyLine(id: $id, parent: $parentPartId, child: $childPartId, qty: $quantity)';
}
