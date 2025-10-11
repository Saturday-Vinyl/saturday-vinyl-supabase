import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/models/production_unit.dart';
import 'package:saturday_app/models/unit_step_completion.dart';
import 'package:saturday_app/repositories/production_unit_repository.dart';

/// Provider for ProductionUnitRepository singleton
final productionUnitRepositoryProvider = Provider<ProductionUnitRepository>((ref) {
  return ProductionUnitRepository();
});

/// Provider for units in production (not completed)
final unitsInProductionProvider = FutureProvider<List<ProductionUnit>>((ref) async {
  final repository = ref.watch(productionUnitRepositoryProvider);
  return repository.getUnitsInProduction();
});

/// Provider for completed units
final completedUnitsProvider = FutureProvider<List<ProductionUnit>>((ref) async {
  final repository = ref.watch(productionUnitRepositoryProvider);
  return repository.getCompletedUnits();
});

/// Provider for a single unit by UUID (for QR code lookup)
final unitByUuidProvider = FutureProvider.family<ProductionUnit, String>((ref, uuid) async {
  final repository = ref.watch(productionUnitRepositoryProvider);
  return repository.getUnitByUuid(uuid);
});

/// Provider for a single unit by ID
final unitByIdProvider = FutureProvider.family<ProductionUnit, String>((ref, id) async {
  final repository = ref.watch(productionUnitRepositoryProvider);
  return repository.getUnitById(id);
});

/// Provider for production steps for a unit
final unitStepsProvider = FutureProvider.family<List<ProductionStep>, String>((ref, unitId) async {
  final repository = ref.watch(productionUnitRepositoryProvider);
  return repository.getUnitSteps(unitId);
});

/// Provider for completed steps for a unit
final unitStepCompletionsProvider = FutureProvider.family<List<UnitStepCompletion>, String>((ref, unitId) async {
  final repository = ref.watch(productionUnitRepositoryProvider);
  return repository.getUnitStepCompletions(unitId);
});

/// Provider for production unit management actions
final productionUnitManagementProvider = Provider<ProductionUnitManagement>((ref) {
  return ProductionUnitManagement(ref);
});

/// Class for managing production unit actions
class ProductionUnitManagement {
  final Ref ref;

  ProductionUnitManagement(this.ref);

  /// Create a new production unit
  Future<ProductionUnit> createUnit({
    required String productId,
    required String variantId,
    required String userId,
    String? shopifyOrderId,
    String? shopifyOrderNumber,
    String? customerName,
    String? orderId,
  }) async {
    final repository = ref.read(productionUnitRepositoryProvider);
    final unit = await repository.createProductionUnit(
      productId: productId,
      variantId: variantId,
      userId: userId,
      shopifyOrderId: shopifyOrderId,
      shopifyOrderNumber: shopifyOrderNumber,
      customerName: customerName,
      orderId: orderId,
    );

    // Invalidate providers to refresh data
    ref.invalidate(unitsInProductionProvider);

    return unit;
  }

  /// Complete a production step
  Future<ProductionUnit> completeStep({
    required String unitId,
    required String stepId,
    required String userId,
    String? notes,
  }) async {
    final repository = ref.read(productionUnitRepositoryProvider);
    final unit = await repository.completeStep(
      unitId: unitId,
      stepId: stepId,
      userId: userId,
      notes: notes,
    );

    // Invalidate providers to refresh data
    ref.invalidate(unitByIdProvider(unitId));
    ref.invalidate(unitStepCompletionsProvider(unitId));
    ref.invalidate(unitsInProductionProvider);

    // If unit is now complete, invalidate completed units too
    if (unit.isCompleted) {
      ref.invalidate(completedUnitsProvider);
    }

    return unit;
  }

  /// Mark unit as complete
  Future<void> markUnitComplete(String unitId) async {
    final repository = ref.read(productionUnitRepositoryProvider);
    await repository.markUnitComplete(unitId);

    // Invalidate providers to refresh data
    ref.invalidate(unitByIdProvider(unitId));
    ref.invalidate(unitsInProductionProvider);
    ref.invalidate(completedUnitsProvider);
  }

  /// Update unit owner
  Future<void> updateUnitOwner(String unitId, String? ownerId) async {
    final repository = ref.read(productionUnitRepositoryProvider);
    await repository.updateUnitOwner(unitId, ownerId);

    // Invalidate unit provider
    ref.invalidate(unitByIdProvider(unitId));
  }

  /// Delete a unit
  Future<void> deleteUnit(String unitId) async {
    final repository = ref.read(productionUnitRepositoryProvider);
    await repository.deleteUnit(unitId);

    // Invalidate providers to refresh data
    ref.invalidate(unitsInProductionProvider);
    ref.invalidate(completedUnitsProvider);
  }

  /// Search units
  Future<List<ProductionUnit>> searchUnits(String query) async {
    final repository = ref.read(productionUnitRepositoryProvider);
    return repository.searchUnits(query);
  }
}
