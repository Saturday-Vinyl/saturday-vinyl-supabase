import 'package:equatable/equatable.dart';
import 'customer.dart';
import 'order_line_item.dart';

/// Represents a customer order from Shopify
class Order extends Equatable {
  final String id;
  final String shopifyOrderId;
  final String shopifyOrderNumber;
  final String? customerId;
  final DateTime orderDate;
  final String status;
  final DateTime createdAt;
  final Customer? customer; // Customer object (expanded in Prompt 27)
  final List<OrderLineItem> lineItems; // Line items (expanded in Prompt 27)
  final String? fulfillmentStatus; // unfulfilled, fulfilled, etc.
  final String? assignedUnitId; // Production unit assigned to this order
  final String? financialStatus; // Payment status (PAID, PENDING, etc.)
  final List<String> tags; // Order tags from Shopify
  final String? totalPrice; // Total order price with currency

  const Order({
    required this.id,
    required this.shopifyOrderId,
    required this.shopifyOrderNumber,
    this.customerId,
    required this.orderDate,
    required this.status,
    required this.createdAt,
    this.customer,
    this.lineItems = const [],
    this.fulfillmentStatus,
    this.assignedUnitId,
    this.financialStatus,
    this.tags = const [],
    this.totalPrice,
  });

  /// Get customer name or email
  String get customerName {
    if (customer != null) {
      return customer!.fullName;
    }
    return 'Unknown Customer';
  }

  /// Check if order needs a production unit (has line items and not assigned)
  bool needsProductionUnit() {
    return lineItems.isNotEmpty && assignedUnitId == null;
  }

  /// Create from JSON (database format)
  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      shopifyOrderId: json['shopify_order_id'] as String,
      shopifyOrderNumber: json['shopify_order_number'] as String,
      customerId: json['customer_id'] as String?,
      orderDate: DateTime.parse(json['order_date'] as String),
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      customer: json['customer'] != null
          ? Customer.fromJson(json['customer'] as Map<String, dynamic>)
          : null,
      lineItems: json['line_items'] != null
          ? (json['line_items'] as List)
              .map((item) => OrderLineItem.fromJson(item as Map<String, dynamic>))
              .toList()
          : const [],
      fulfillmentStatus: json['fulfillment_status'] as String?,
      assignedUnitId: json['assigned_unit_id'] as String?,
      financialStatus: json['financial_status'] as String?,
      tags: json['tags'] != null
          ? List<String>.from(json['tags'] as List)
          : const [],
      totalPrice: json['total_price'] as String?,
    );
  }

  /// Create from Shopify GraphQL response
  /// Note: Customer data may not be available on Basic Shopify plans
  factory Order.fromShopify(Map<String, dynamic> shopifyData) {
    // Extract customer data (may not be available on Basic plans)
    Customer? customer;
    // Customer data is not available on Basic Shopify plans
    // We only have the order ID and line items
    // Customer info will remain null

    // Extract order number from name (format: #1001)
    final orderName = shopifyData['name'] as String? ?? '';
    final orderNumber = orderName.replaceFirst('#', '');

    // Parse line items
    final lineItemsData = shopifyData['lineItems'] as Map<String, dynamic>?;
    final lineItemEdges = lineItemsData?['edges'] as List<dynamic>? ?? [];
    final lineItems = lineItemEdges
        .map((edge) {
          final node = edge['node'] as Map<String, dynamic>;
          return OrderLineItem.fromShopify(node, ''); // orderId will be set after insert
        })
        .toList();

    // Extract financial status
    final financialStatus = shopifyData['displayFinancialStatus'] as String?;

    // Extract tags (comes as comma-separated string or list)
    List<String> tags = [];
    final tagsData = shopifyData['tags'];
    if (tagsData != null) {
      if (tagsData is List) {
        tags = List<String>.from(tagsData);
      } else if (tagsData is String && tagsData.isNotEmpty) {
        tags = tagsData.split(',').map((t) => t.trim()).toList();
      }
    }

    // Extract total price
    String? totalPrice;
    final priceSet = shopifyData['currentTotalPriceSet'] as Map<String, dynamic>?;
    if (priceSet != null) {
      final shopMoney = priceSet['shopMoney'] as Map<String, dynamic>?;
      if (shopMoney != null) {
        final amount = shopMoney['amount'] as String?;
        final currency = shopMoney['currencyCode'] as String?;
        totalPrice = currency != null ? '$currency $amount' : amount;
      }
    }

    return Order(
      id: '', // Will be generated when inserted to database
      shopifyOrderId: shopifyData['id'] as String,
      shopifyOrderNumber: orderNumber,
      customerId: customer?.shopifyCustomerId,
      orderDate: DateTime.parse(shopifyData['createdAt'] as String),
      status: shopifyData['displayFulfillmentStatus'] as String? ?? 'unfulfilled',
      createdAt: DateTime.now(),
      customer: customer,
      lineItems: lineItems,
      fulfillmentStatus: shopifyData['displayFulfillmentStatus'] as String?,
      assignedUnitId: null,
      financialStatus: financialStatus,
      tags: tags,
      totalPrice: totalPrice,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shopify_order_id': shopifyOrderId,
      'shopify_order_number': shopifyOrderNumber,
      'customer_id': customerId,
      'order_date': orderDate.toIso8601String(),
      'status': status,
      'created_at': createdAt.toIso8601String(),
      if (customer != null) 'customer': customer!.toJson(),
      'line_items': lineItems.map((item) => item.toJson()).toList(),
      'fulfillment_status': fulfillmentStatus,
      'assigned_unit_id': assignedUnitId,
      'financial_status': financialStatus,
      'tags': tags,
      'total_price': totalPrice,
    };
  }

  /// Copy with method
  Order copyWith({
    String? id,
    String? shopifyOrderId,
    String? shopifyOrderNumber,
    String? customerId,
    DateTime? orderDate,
    String? status,
    DateTime? createdAt,
    Customer? customer,
    List<OrderLineItem>? lineItems,
    String? fulfillmentStatus,
    String? assignedUnitId,
    String? financialStatus,
    List<String>? tags,
    String? totalPrice,
  }) {
    return Order(
      id: id ?? this.id,
      shopifyOrderId: shopifyOrderId ?? this.shopifyOrderId,
      shopifyOrderNumber: shopifyOrderNumber ?? this.shopifyOrderNumber,
      customerId: customerId ?? this.customerId,
      orderDate: orderDate ?? this.orderDate,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      customer: customer ?? this.customer,
      lineItems: lineItems ?? this.lineItems,
      fulfillmentStatus: fulfillmentStatus ?? this.fulfillmentStatus,
      assignedUnitId: assignedUnitId ?? this.assignedUnitId,
      financialStatus: financialStatus ?? this.financialStatus,
      tags: tags ?? this.tags,
      totalPrice: totalPrice ?? this.totalPrice,
    );
  }

  @override
  List<Object?> get props => [
        id,
        shopifyOrderId,
        shopifyOrderNumber,
        customerId,
        orderDate,
        status,
        createdAt,
        customer,
        lineItems,
        fulfillmentStatus,
        assignedUnitId,
        financialStatus,
        tags,
        totalPrice,
      ];

  @override
  String toString() {
    return 'Order(id: $id, orderNumber: $shopifyOrderNumber, customer: ${customer?.fullName ?? "Unknown"}, items: ${lineItems.length})';
  }
}
