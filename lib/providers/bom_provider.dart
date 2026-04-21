import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/bom_line.dart';
import 'package:saturday_app/models/bom_variant_override.dart';
import 'package:saturday_app/repositories/bom_repository.dart';

/// Provider for BomRepository
final bomRepositoryProvider = Provider<BomRepository>((ref) {
  return BomRepository();
});

/// Provider for BOM lines of a product
final productBomProvider =
    FutureProvider.family<List<BomLine>, String>((ref, productId) async {
  final repository = ref.watch(bomRepositoryProvider);
  return await repository.getBomLines(productId);
});

/// Parameter type for variant overrides query
typedef VariantOverrideParams = ({String productId, String variantId});

/// Provider for variant overrides for a product + variant combination
final bomVariantOverridesProvider = FutureProvider.family<
    List<BomVariantOverride>, VariantOverrideParams>((ref, params) async {
  final repository = ref.watch(bomRepositoryProvider);
  return await repository.getVariantOverridesForProduct(
      params.productId, params.variantId);
});

/// Management class for BOM CRUD operations
class BomManagement {
  final Ref ref;

  BomManagement(this.ref);

  Future<BomLine> createBomLine({
    required String productId,
    required String partId,
    String? productionStepId,
    required double quantity,
    String? notes,
  }) async {
    final repository = ref.read(bomRepositoryProvider);
    final line = await repository.createBomLine(
      productId: productId,
      partId: partId,
      productionStepId: productionStepId,
      quantity: quantity,
      notes: notes,
    );

    ref.invalidate(productBomProvider(productId));
    return line;
  }

  Future<void> updateBomLine(
    String id, {
    required String productId,
    String? partId,
    String? productionStepId,
    double? quantity,
    String? notes,
  }) async {
    final repository = ref.read(bomRepositoryProvider);
    await repository.updateBomLine(
      id,
      partId: partId,
      productionStepId: productionStepId,
      quantity: quantity,
      notes: notes,
    );

    ref.invalidate(productBomProvider(productId));
  }

  Future<void> deleteBomLine(String id, {required String productId}) async {
    final repository = ref.read(bomRepositoryProvider);
    await repository.deleteBomLine(id);

    ref.invalidate(productBomProvider(productId));
  }

  Future<BomVariantOverride> createVariantOverride({
    required String bomLineId,
    required String variantId,
    required String partId,
    required String productId,
    double? quantity,
  }) async {
    final repository = ref.read(bomRepositoryProvider);
    final override = await repository.createVariantOverride(
      bomLineId: bomLineId,
      variantId: variantId,
      partId: partId,
      quantity: quantity,
    );

    ref.invalidate(bomVariantOverridesProvider(
        (productId: productId, variantId: variantId)));
    return override;
  }

  Future<void> deleteVariantOverride(
    String id, {
    required String productId,
    required String variantId,
  }) async {
    final repository = ref.read(bomRepositoryProvider);
    await repository.deleteVariantOverride(id);

    ref.invalidate(bomVariantOverridesProvider(
        (productId: productId, variantId: variantId)));
  }
}

/// Provider for BOM management operations
final bomManagementProvider = Provider<BomManagement>((ref) {
  return BomManagement(ref);
});
