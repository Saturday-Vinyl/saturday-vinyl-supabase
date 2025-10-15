import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/production_step.dart';
import 'package:saturday_app/repositories/production_step_repository.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Provider for ProductionStepRepository
final productionStepRepositoryProvider = Provider<ProductionStepRepository>((ref) {
  return ProductionStepRepository();
});

/// Provider for production steps of a specific product (family provider)
final productionStepsProvider = FutureProvider.family<List<ProductionStep>, String>((ref, productId) async {
  final repository = ref.watch(productionStepRepositoryProvider);
  return await repository.getStepsForProduct(productId);
});

/// Local state provider for optimistic UI updates during reordering
/// This holds the locally modified order before the server confirms
final localProductionStepsProvider = StateProvider.family<List<ProductionStep>?, String>((ref, productId) {
  return null; // null means use the data from productionStepsProvider
});

/// Provider for production step management actions
final productionStepManagementProvider = Provider((ref) => ProductionStepManagement(ref));

/// Production step management actions
class ProductionStepManagement {
  final Ref ref;

  ProductionStepManagement(this.ref);

  /// Create a new production step
  Future<ProductionStep> createStep(ProductionStep step, {File? file}) async {
    try {
      final repository = ref.read(productionStepRepositoryProvider);
      final createdStep = await repository.createStep(step, file: file);

      // Invalidate the steps provider to refresh the list
      ref.invalidate(productionStepsProvider(step.productId));

      AppLogger.info('Production step created successfully');
      return createdStep;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create production step', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing production step
  Future<void> updateStep(
    ProductionStep step, {
    File? file,
    ProductionStep? oldStep,
  }) async {
    try {
      final repository = ref.read(productionStepRepositoryProvider);
      await repository.updateStep(step, file: file, oldStep: oldStep);

      // Invalidate the steps provider to refresh the list
      ref.invalidate(productionStepsProvider(step.productId));

      AppLogger.info('Production step updated successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update production step', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a production step
  Future<void> deleteStep(String stepId, String productId) async {
    try {
      final repository = ref.read(productionStepRepositoryProvider);
      await repository.deleteStep(stepId);

      // Invalidate the steps provider to refresh the list
      ref.invalidate(productionStepsProvider(productId));

      AppLogger.info('Production step deleted successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete production step', error, stackTrace);
      rethrow;
    }
  }

  /// Reorder production steps
  Future<void> reorderSteps(String productId, List<String> stepIds) async {
    try {
      final repository = ref.read(productionStepRepositoryProvider);
      await repository.reorderSteps(productId, stepIds);

      // Clear local state and refresh from server
      ref.read(localProductionStepsProvider(productId).notifier).state = null;
      ref.invalidate(productionStepsProvider(productId));

      AppLogger.info('Production steps reordered successfully');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to reorder production steps', error, stackTrace);
      rethrow;
    }
  }

  /// Get the next available step order for a product
  Future<int> getNextStepOrder(String productId) async {
    try {
      final repository = ref.read(productionStepRepositoryProvider);
      return await repository.getNextStepOrder(productId);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get next step order', error, stackTrace);
      rethrow;
    }
  }
}
