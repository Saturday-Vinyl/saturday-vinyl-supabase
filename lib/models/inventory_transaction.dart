import 'package:equatable/equatable.dart';

/// Type of inventory transaction
enum TransactionType {
  receive,
  consume,
  build,
  adjust,
  returnStock; // 'return' is reserved in Dart

  String get value {
    switch (this) {
      case TransactionType.receive:
        return 'receive';
      case TransactionType.consume:
        return 'consume';
      case TransactionType.build:
        return 'build';
      case TransactionType.adjust:
        return 'adjust';
      case TransactionType.returnStock:
        return 'return';
    }
  }

  String get displayName {
    switch (this) {
      case TransactionType.receive:
        return 'Received';
      case TransactionType.consume:
        return 'Consumed';
      case TransactionType.build:
        return 'Built';
      case TransactionType.adjust:
        return 'Adjusted';
      case TransactionType.returnStock:
        return 'Returned';
    }
  }

  static TransactionType fromString(String value) {
    switch (value) {
      case 'receive':
        return TransactionType.receive;
      case 'consume':
        return TransactionType.consume;
      case 'build':
        return TransactionType.build;
      case 'adjust':
        return TransactionType.adjust;
      case 'return':
        return TransactionType.returnStock;
      default:
        return TransactionType.adjust;
    }
  }
}

/// Inventory transaction recording a stock change
class InventoryTransaction extends Equatable {
  final String id;
  final String partId;
  final TransactionType transactionType;
  final double quantity;
  final String? unitId;
  final String? stepCompletionId;
  final String? supplierId;
  final String? buildBatchId;
  final String? reference;
  final String performedBy;
  final DateTime performedAt;

  const InventoryTransaction({
    required this.id,
    required this.partId,
    required this.transactionType,
    required this.quantity,
    this.unitId,
    this.stepCompletionId,
    this.supplierId,
    this.buildBatchId,
    this.reference,
    required this.performedBy,
    required this.performedAt,
  });

  factory InventoryTransaction.fromJson(Map<String, dynamic> json) {
    return InventoryTransaction(
      id: json['id'] as String,
      partId: json['part_id'] as String,
      transactionType:
          TransactionType.fromString(json['transaction_type'] as String),
      quantity: (json['quantity'] as num).toDouble(),
      unitId: json['unit_id'] as String?,
      stepCompletionId: json['step_completion_id'] as String?,
      supplierId: json['supplier_id'] as String?,
      buildBatchId: json['build_batch_id'] as String?,
      reference: json['reference'] as String?,
      performedBy: json['performed_by'] as String,
      performedAt: DateTime.parse(json['performed_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'part_id': partId,
      'transaction_type': transactionType.value,
      'quantity': quantity,
      'unit_id': unitId,
      'step_completion_id': stepCompletionId,
      'supplier_id': supplierId,
      'build_batch_id': buildBatchId,
      'reference': reference,
      'performed_by': performedBy,
      'performed_at': performedAt.toIso8601String(),
    };
  }

  InventoryTransaction copyWith({
    String? id,
    String? partId,
    TransactionType? transactionType,
    double? quantity,
    String? unitId,
    String? stepCompletionId,
    String? supplierId,
    String? buildBatchId,
    String? reference,
    String? performedBy,
    DateTime? performedAt,
  }) {
    return InventoryTransaction(
      id: id ?? this.id,
      partId: partId ?? this.partId,
      transactionType: transactionType ?? this.transactionType,
      quantity: quantity ?? this.quantity,
      unitId: unitId ?? this.unitId,
      stepCompletionId: stepCompletionId ?? this.stepCompletionId,
      supplierId: supplierId ?? this.supplierId,
      buildBatchId: buildBatchId ?? this.buildBatchId,
      reference: reference ?? this.reference,
      performedBy: performedBy ?? this.performedBy,
      performedAt: performedAt ?? this.performedAt,
    );
  }

  @override
  List<Object?> get props => [
        id, partId, transactionType, quantity, unitId,
        stepCompletionId, supplierId, buildBatchId, reference,
        performedBy, performedAt,
      ];

  @override
  String toString() =>
      'InventoryTransaction(id: $id, part: $partId, type: ${transactionType.displayName}, qty: $quantity)';
}
