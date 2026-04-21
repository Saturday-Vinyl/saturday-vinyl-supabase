import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/supplier_part.dart';
import 'package:saturday_app/repositories/supplier_parts_repository.dart';

/// Provider for SupplierPartsRepository
final supplierPartsRepositoryProvider =
    Provider<SupplierPartsRepository>((ref) {
  return SupplierPartsRepository();
});

/// Provider for supplier parts linked to a specific part
final supplierPartsForPartProvider =
    FutureProvider.family<List<SupplierPart>, String>((ref, partId) async {
  final repository = ref.watch(supplierPartsRepositoryProvider);
  return await repository.getSupplierPartsForPart(partId);
});

/// Provider for parts from a specific supplier
final supplierPartsForSupplierProvider =
    FutureProvider.family<List<SupplierPart>, String>((ref, supplierId) async {
  final repository = ref.watch(supplierPartsRepositoryProvider);
  return await repository.getSupplierPartsForSupplier(supplierId);
});

/// Get the preferred supplier's unit cost for a part (null if no preferred supplier or no cost set)
final preferredUnitCostProvider =
    FutureProvider.family<double?, String>((ref, partId) async {
  final supplierParts =
      await ref.watch(supplierPartsForPartProvider(partId).future);
  final preferred =
      supplierParts.where((sp) => sp.isPreferred).firstOrNull;
  return preferred?.unitCost;
});

/// Map of partId → preferred unit cost for all parts that have one
final allPreferredCostsProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final repository = ref.watch(supplierPartsRepositoryProvider);
  return await repository.getAllPreferredCosts();
});
