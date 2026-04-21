import 'package:saturday_app/models/supplier_part.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing supplier-part links
class SupplierPartsRepository {
  final _supabase = SupabaseService.instance.client;
  final _uuid = const Uuid();

  /// Get all supplier parts for a given part
  Future<List<SupplierPart>> getSupplierPartsForPart(String partId) async {
    try {
      final response = await _supabase
          .from('supplier_parts')
          .select()
          .eq('part_id', partId)
          .order('is_preferred', ascending: false);

      return (response as List)
          .map((json) => SupplierPart.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch supplier parts for part $partId', error, stackTrace);
      rethrow;
    }
  }

  /// Get all parts from a given supplier
  Future<List<SupplierPart>> getSupplierPartsForSupplier(String supplierId) async {
    try {
      final response = await _supabase
          .from('supplier_parts')
          .select()
          .eq('supplier_id', supplierId);

      return (response as List)
          .map((json) => SupplierPart.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch supplier parts for supplier $supplierId', error, stackTrace);
      rethrow;
    }
  }

  /// Find supplier part by barcode value
  Future<SupplierPart?> findByBarcode(String barcodeValue) async {
    try {
      final response = await _supabase
          .from('supplier_parts')
          .select()
          .eq('barcode_value', barcodeValue)
          .maybeSingle();

      if (response == null) return null;
      return SupplierPart.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to find supplier part by barcode', error, stackTrace);
      rethrow;
    }
  }

  /// Find supplier part by supplier SKU
  Future<SupplierPart?> findBySupplierSku(String sku) async {
    try {
      final response = await _supabase
          .from('supplier_parts')
          .select()
          .eq('supplier_sku', sku)
          .maybeSingle();

      if (response == null) return null;
      return SupplierPart.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to find supplier part by SKU', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new supplier part link
  Future<SupplierPart> createSupplierPart({
    required String partId,
    required String supplierId,
    required String supplierSku,
    String? barcodeValue,
    String? barcodeFormat,
    double? unitCost,
    String costCurrency = 'USD',
    bool isPreferred = false,
    String? url,
    String? notes,
  }) async {
    try {
      final id = _uuid.v4();

      await _supabase.from('supplier_parts').insert({
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
      });

      AppLogger.info('Created supplier part link: $supplierSku');

      return SupplierPart(
        id: id,
        partId: partId,
        supplierId: supplierId,
        supplierSku: supplierSku,
        barcodeValue: barcodeValue,
        barcodeFormat: barcodeFormat,
        unitCost: unitCost,
        costCurrency: costCurrency,
        isPreferred: isPreferred,
        url: url,
        notes: notes,
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create supplier part', error, stackTrace);
      rethrow;
    }
  }

  /// Update a supplier part link
  Future<void> updateSupplierPart(
    String id, {
    String? supplierSku,
    String? barcodeValue,
    String? barcodeFormat,
    double? unitCost,
    String? costCurrency,
    bool? isPreferred,
    String? url,
    String? notes,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (supplierSku != null) updates['supplier_sku'] = supplierSku;
      if (barcodeValue != null) updates['barcode_value'] = barcodeValue;
      if (barcodeFormat != null) updates['barcode_format'] = barcodeFormat;
      if (unitCost != null) updates['unit_cost'] = unitCost;
      if (costCurrency != null) updates['cost_currency'] = costCurrency;
      if (isPreferred != null) updates['is_preferred'] = isPreferred;
      if (url != null) updates['url'] = url;
      if (notes != null) updates['notes'] = notes;

      await _supabase.from('supplier_parts').update(updates).eq('id', id);

      AppLogger.info('Updated supplier part: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update supplier part $id', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a supplier part link
  Future<void> deleteSupplierPart(String id) async {
    try {
      await _supabase.from('supplier_parts').delete().eq('id', id);
      AppLogger.info('Deleted supplier part: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete supplier part $id', error, stackTrace);
      rethrow;
    }
  }

  /// Reassign all supplier parts from one part to another.
  /// Handles unique constraint (part_id, supplier_id, supplier_sku) by
  /// attempting each row individually and deleting duplicates.
  Future<void> reassignSupplierParts(String fromPartId, String toPartId) async {
    try {
      final rows = await getSupplierPartsForPart(fromPartId);
      for (final sp in rows) {
        try {
          await _supabase
              .from('supplier_parts')
              .update({'part_id': toPartId})
              .eq('id', sp.id);
        } catch (_) {
          // Unique constraint conflict — target already has this link, delete the duplicate
          await _supabase.from('supplier_parts').delete().eq('id', sp.id);
          AppLogger.info(
              'Deleted duplicate supplier part ${sp.supplierSku} during merge');
        }
      }
      AppLogger.info('Reassigned supplier parts from $fromPartId to $toPartId');
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to reassign supplier parts', error, stackTrace);
      rethrow;
    }
  }

  /// Get preferred supplier unit costs for all parts (partId → unitCost)
  Future<Map<String, double>> getAllPreferredCosts() async {
    try {
      final response = await _supabase
          .from('supplier_parts')
          .select('part_id, unit_cost')
          .eq('is_preferred', true)
          .not('unit_cost', 'is', null);

      final result = <String, double>{};
      for (final row in response as List) {
        final json = row as Map<String, dynamic>;
        result[json['part_id'] as String] =
            (json['unit_cost'] as num).toDouble();
      }
      return result;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch preferred costs', error, stackTrace);
      rethrow;
    }
  }
}
