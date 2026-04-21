import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/supplier.dart';
import 'package:saturday_app/repositories/suppliers_repository.dart';

/// Provider for SuppliersRepository
final suppliersRepositoryProvider = Provider<SuppliersRepository>((ref) {
  return SuppliersRepository();
});

/// Provider for all active suppliers
final suppliersListProvider = FutureProvider<List<Supplier>>((ref) async {
  final repository = ref.watch(suppliersRepositoryProvider);
  return await repository.getSuppliers();
});

/// Provider for a single supplier by ID
final supplierDetailProvider =
    FutureProvider.family<Supplier?, String>((ref, supplierId) async {
  final repository = ref.watch(suppliersRepositoryProvider);
  return await repository.getSupplier(supplierId);
});

/// Management class for supplier CRUD operations
class SuppliersManagement {
  final Ref ref;

  SuppliersManagement(this.ref);

  Future<Supplier> createSupplier({
    required String name,
    String? website,
    String? notes,
  }) async {
    final repository = ref.read(suppliersRepositoryProvider);
    final supplier = await repository.createSupplier(
      name: name,
      website: website,
      notes: notes,
    );

    ref.invalidate(suppliersListProvider);
    return supplier;
  }

  Future<Supplier> updateSupplier(
    String id, {
    String? name,
    String? website,
    String? notes,
  }) async {
    final repository = ref.read(suppliersRepositoryProvider);
    final supplier = await repository.updateSupplier(
      id,
      name: name,
      website: website,
      notes: notes,
    );

    ref.invalidate(supplierDetailProvider(id));
    ref.invalidate(suppliersListProvider);
    return supplier;
  }

  Future<void> deleteSupplier(String id) async {
    final repository = ref.read(suppliersRepositoryProvider);
    await repository.deleteSupplier(id);

    ref.invalidate(supplierDetailProvider(id));
    ref.invalidate(suppliersListProvider);
  }
}

/// Provider for supplier management operations
final suppliersManagementProvider = Provider<SuppliersManagement>((ref) {
  return SuppliersManagement(ref);
});
