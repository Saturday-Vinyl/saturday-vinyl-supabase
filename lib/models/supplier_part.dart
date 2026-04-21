import 'package:equatable/equatable.dart';

/// Maps a part to a supplier with their SKU and barcode info
class SupplierPart extends Equatable {
  final String id;
  final String partId;
  final String supplierId;
  final String supplierSku;
  final String? barcodeValue;
  final String? barcodeFormat;
  final double? unitCost;
  final String costCurrency;
  final bool isPreferred;
  final String? url;
  final String? notes;

  const SupplierPart({
    required this.id,
    required this.partId,
    required this.supplierId,
    required this.supplierSku,
    this.barcodeValue,
    this.barcodeFormat,
    this.unitCost,
    this.costCurrency = 'USD',
    required this.isPreferred,
    this.url,
    this.notes,
  });

  factory SupplierPart.fromJson(Map<String, dynamic> json) {
    return SupplierPart(
      id: json['id'] as String,
      partId: json['part_id'] as String,
      supplierId: json['supplier_id'] as String,
      supplierSku: json['supplier_sku'] as String,
      barcodeValue: json['barcode_value'] as String?,
      barcodeFormat: json['barcode_format'] as String?,
      unitCost: json['unit_cost'] != null
          ? (json['unit_cost'] as num).toDouble()
          : null,
      costCurrency: json['cost_currency'] as String? ?? 'USD',
      isPreferred: json['is_preferred'] as bool? ?? false,
      url: json['url'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'part_id': partId,
      'supplier_id': supplierId,
      'supplier_sku': supplierSku,
      'barcode_value': barcodeValue,
      'barcode_format': barcodeFormat,
      'unit_cost': unitCost,
      'cost_currency': costCurrency,
      'is_preferred': isPreferred,
      'url': url,
      'notes': notes,
    };
  }

  SupplierPart copyWith({
    String? id,
    String? partId,
    String? supplierId,
    String? supplierSku,
    String? barcodeValue,
    String? barcodeFormat,
    double? unitCost,
    String? costCurrency,
    bool? isPreferred,
    String? url,
    String? notes,
  }) {
    return SupplierPart(
      id: id ?? this.id,
      partId: partId ?? this.partId,
      supplierId: supplierId ?? this.supplierId,
      supplierSku: supplierSku ?? this.supplierSku,
      barcodeValue: barcodeValue ?? this.barcodeValue,
      barcodeFormat: barcodeFormat ?? this.barcodeFormat,
      unitCost: unitCost ?? this.unitCost,
      costCurrency: costCurrency ?? this.costCurrency,
      isPreferred: isPreferred ?? this.isPreferred,
      url: url ?? this.url,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [
        id, partId, supplierId, supplierSku, barcodeValue,
        barcodeFormat, unitCost, costCurrency, isPreferred, url, notes,
      ];

  @override
  String toString() =>
      'SupplierPart(id: $id, partId: $partId, supplierSku: $supplierSku)';
}
