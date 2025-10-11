import 'package:equatable/equatable.dart';

/// Represents a production unit - a single item being manufactured
class ProductionUnit extends Equatable {
  final String id;
  final String uuid;
  final String unitId; // Format: SV-{PRODUCT_CODE}-{NUMBER}
  final String productId;
  final String variantId;
  final String? shopifyOrderId; // Shopify order ID (for reference only)
  final String? shopifyOrderNumber; // Human-readable order number
  final String? customerName; // Cached customer name
  final String? currentOwnerId;
  final String qrCodeUrl;
  final DateTime? productionStartedAt;
  final DateTime? productionCompletedAt;
  final bool isCompleted;
  final DateTime createdAt;
  final String createdBy;

  const ProductionUnit({
    required this.id,
    required this.uuid,
    required this.unitId,
    required this.productId,
    required this.variantId,
    this.shopifyOrderId,
    this.shopifyOrderNumber,
    this.customerName,
    this.currentOwnerId,
    required this.qrCodeUrl,
    this.productionStartedAt,
    this.productionCompletedAt,
    required this.isCompleted,
    required this.createdAt,
    required this.createdBy,
  });

  /// Get formatted unit ID
  String getFormattedUnitId() => unitId;

  /// Check if unit is in progress (started but not completed)
  bool isInProgress() =>
      productionStartedAt != null && productionCompletedAt == null;

  /// Validate unit ID format (SV-{CODE}-{NUMBER})
  static bool validateUnitIdFormat(String unitId) {
    final pattern = RegExp(r'^SV-[A-Z0-9]+-\d{5,}$');
    return pattern.hasMatch(unitId);
  }

  /// Create from JSON
  factory ProductionUnit.fromJson(Map<String, dynamic> json) {
    return ProductionUnit(
      id: json['id'] as String,
      uuid: json['uuid'] as String,
      unitId: json['unit_id'] as String,
      productId: json['product_id'] as String,
      variantId: json['variant_id'] as String,
      shopifyOrderId: json['shopify_order_id'] as String?,
      shopifyOrderNumber: json['shopify_order_number'] as String?,
      customerName: json['customer_name'] as String?,
      currentOwnerId: json['current_owner_id'] as String?,
      qrCodeUrl: json['qr_code_url'] as String,
      productionStartedAt: json['production_started_at'] != null
          ? DateTime.parse(json['production_started_at'] as String)
          : null,
      productionCompletedAt: json['production_completed_at'] != null
          ? DateTime.parse(json['production_completed_at'] as String)
          : null,
      isCompleted: json['is_completed'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'unit_id': unitId,
      'product_id': productId,
      'variant_id': variantId,
      'shopify_order_id': shopifyOrderId,
      'shopify_order_number': shopifyOrderNumber,
      'customer_name': customerName,
      'current_owner_id': currentOwnerId,
      'qr_code_url': qrCodeUrl,
      'production_started_at': productionStartedAt?.toIso8601String(),
      'production_completed_at': productionCompletedAt?.toIso8601String(),
      'is_completed': isCompleted,
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
    };
  }

  /// Copy with method for immutability
  ProductionUnit copyWith({
    String? id,
    String? uuid,
    String? unitId,
    String? productId,
    String? variantId,
    String? shopifyOrderId,
    String? shopifyOrderNumber,
    String? customerName,
    String? currentOwnerId,
    String? qrCodeUrl,
    DateTime? productionStartedAt,
    DateTime? productionCompletedAt,
    bool? isCompleted,
    DateTime? createdAt,
    String? createdBy,
  }) {
    return ProductionUnit(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      unitId: unitId ?? this.unitId,
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      shopifyOrderId: shopifyOrderId ?? this.shopifyOrderId,
      shopifyOrderNumber: shopifyOrderNumber ?? this.shopifyOrderNumber,
      customerName: customerName ?? this.customerName,
      currentOwnerId: currentOwnerId ?? this.currentOwnerId,
      qrCodeUrl: qrCodeUrl ?? this.qrCodeUrl,
      productionStartedAt: productionStartedAt ?? this.productionStartedAt,
      productionCompletedAt:
          productionCompletedAt ?? this.productionCompletedAt,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        uuid,
        unitId,
        productId,
        variantId,
        shopifyOrderId,
        shopifyOrderNumber,
        customerName,
        currentOwnerId,
        qrCodeUrl,
        productionStartedAt,
        productionCompletedAt,
        isCompleted,
        createdAt,
        createdBy,
      ];
}
