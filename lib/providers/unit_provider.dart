import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/repositories/unit_repository.dart';

/// Provider for UnitRepository singleton
final unitRepositoryProvider = Provider<UnitRepository>((ref) {
  return UnitRepository();
});

/// Provider for units in production (started but not completed)
final unitsInProductionProvider = FutureProvider<List<Unit>>((ref) async {
  final repository = ref.watch(unitRepositoryProvider);
  return repository.getUnitsInProduction();
});

/// Provider for completed units
final completedUnitsProvider = FutureProvider<List<Unit>>((ref) async {
  final repository = ref.watch(unitRepositoryProvider);
  return repository.getCompletedUnits();
});

/// Provider for units by status
final unitsByStatusProvider =
    FutureProvider.family<List<Unit>, UnitStatus>((ref, status) async {
  final repository = ref.watch(unitRepositoryProvider);
  return repository.getUnitsByStatus(status);
});

/// Provider for units by product
final unitsByProductProvider =
    FutureProvider.family<List<Unit>, String>((ref, productId) async {
  final repository = ref.watch(unitRepositoryProvider);
  return repository.getUnitsByProduct(productId);
});

/// Provider for a single unit by ID
final unitByIdProvider =
    FutureProvider.family<Unit, String>((ref, id) async {
  final repository = ref.watch(unitRepositoryProvider);
  return repository.getUnitById(id);
});

/// Provider for a single unit by serial number
final unitBySerialNumberProvider =
    FutureProvider.family<Unit?, String>((ref, serialNumber) async {
  final repository = ref.watch(unitRepositoryProvider);
  return repository.getUnitBySerialNumber(serialNumber);
});

/// Provider for units owned by a user
final unitsByUserProvider =
    FutureProvider.family<List<Unit>, String>((ref, userId) async {
  final repository = ref.watch(unitRepositoryProvider);
  return repository.getUnitsByUser(userId);
});

/// Provider for unit by order
final unitByOrderProvider =
    FutureProvider.family<Unit?, String>((ref, orderId) async {
  final repository = ref.watch(unitRepositoryProvider);
  return repository.getUnitByOrder(orderId);
});

/// Provider for unit management actions
final unitManagementProvider = Provider<UnitManagement>((ref) {
  return UnitManagement(ref);
});

/// Class for managing unit actions
class UnitManagement {
  final Ref ref;

  UnitManagement(this.ref);

  /// Create a new unit
  Future<Unit> createUnit({
    required String productId,
    required String variantId,
    required String userId,
    String? orderId,
  }) async {
    final repository = ref.read(unitRepositoryProvider);
    final unit = await repository.createUnit(
      productId: productId,
      variantId: variantId,
      userId: userId,
      orderId: orderId,
    );

    // Invalidate providers to refresh data
    ref.invalidate(unitsInProductionProvider);
    ref.invalidate(unitsByProductProvider(productId));

    return unit;
  }

  /// Mark unit as factory provisioned
  Future<Unit> markFactoryProvisioned({
    required String unitId,
    required String userId,
  }) async {
    final repository = ref.read(unitRepositoryProvider);
    final unit = await repository.markFactoryProvisioned(
      unitId: unitId,
      userId: userId,
    );

    // Invalidate providers
    ref.invalidate(unitByIdProvider(unitId));
    ref.invalidate(unitsByStatusProvider(UnitStatus.unprovisioned));
    ref.invalidate(unitsByStatusProvider(UnitStatus.factoryProvisioned));

    return unit;
  }

  /// Mark unit as user provisioned
  Future<Unit> markUserProvisioned({
    required String unitId,
    required String userId,
    String? deviceName,
    Map<String, dynamic>? consumerAttributes,
  }) async {
    final repository = ref.read(unitRepositoryProvider);
    final unit = await repository.markUserProvisioned(
      unitId: unitId,
      userId: userId,
      deviceName: deviceName,
      consumerAttributes: consumerAttributes,
    );

    // Invalidate providers
    ref.invalidate(unitByIdProvider(unitId));
    ref.invalidate(unitsByStatusProvider(UnitStatus.factoryProvisioned));
    ref.invalidate(unitsByStatusProvider(UnitStatus.userProvisioned));
    ref.invalidate(unitsByUserProvider(userId));

    return unit;
  }

  /// Update consumer attributes
  Future<Unit> updateConsumerAttributes({
    required String unitId,
    required Map<String, dynamic> attributes,
  }) async {
    final repository = ref.read(unitRepositoryProvider);
    final unit = await repository.updateConsumerAttributes(
      unitId: unitId,
      attributes: attributes,
    );

    ref.invalidate(unitByIdProvider(unitId));
    return unit;
  }

  /// Update device name
  Future<Unit> updateDeviceName({
    required String unitId,
    required String deviceName,
  }) async {
    final repository = ref.read(unitRepositoryProvider);
    final unit = await repository.updateDeviceName(
      unitId: unitId,
      deviceName: deviceName,
    );

    ref.invalidate(unitByIdProvider(unitId));
    return unit;
  }

  /// Mark production complete
  Future<Unit> markProductionComplete(String unitId) async {
    final repository = ref.read(unitRepositoryProvider);
    final unit = await repository.markProductionComplete(unitId);

    ref.invalidate(unitByIdProvider(unitId));
    ref.invalidate(unitsInProductionProvider);
    ref.invalidate(completedUnitsProvider);

    return unit;
  }

  /// Start production
  Future<Unit> startProduction(String unitId) async {
    final repository = ref.read(unitRepositoryProvider);
    final unit = await repository.startProduction(unitId);

    ref.invalidate(unitByIdProvider(unitId));
    ref.invalidate(unitsInProductionProvider);

    return unit;
  }

  /// Delete a unit
  Future<void> deleteUnit(String unitId) async {
    final repository = ref.read(unitRepositoryProvider);
    await repository.deleteUnit(unitId);

    ref.invalidate(unitsInProductionProvider);
    ref.invalidate(completedUnitsProvider);
  }

  /// Transfer ownership
  Future<Unit> transferOwnership({
    required String unitId,
    required String newUserId,
  }) async {
    final repository = ref.read(unitRepositoryProvider);
    final unit = await repository.transferOwnership(
      unitId: unitId,
      newUserId: newUserId,
    );

    ref.invalidate(unitByIdProvider(unitId));
    ref.invalidate(unitsByUserProvider(newUserId));

    return unit;
  }

  /// Link order to unit
  Future<Unit> linkOrder({
    required String unitId,
    required String orderId,
  }) async {
    final repository = ref.read(unitRepositoryProvider);
    final unit = await repository.linkOrder(
      unitId: unitId,
      orderId: orderId,
    );

    ref.invalidate(unitByIdProvider(unitId));
    ref.invalidate(unitByOrderProvider(orderId));

    return unit;
  }

  /// Search units
  Future<List<Unit>> searchUnits(String query) async {
    final repository = ref.read(unitRepositoryProvider);
    return repository.searchUnits(query);
  }
}
