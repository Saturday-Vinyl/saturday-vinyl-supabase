import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/repositories/parts_repository.dart';

/// Provider for PartsRepository
final partsRepositoryProvider = Provider<PartsRepository>((ref) {
  return PartsRepository();
});

/// Provider for all active parts
final partsListProvider = FutureProvider<List<Part>>((ref) async {
  final repository = ref.watch(partsRepositoryProvider);
  return await repository.getParts();
});

/// Provider for a single part by ID
final partDetailProvider =
    FutureProvider.family<Part?, String>((ref, partId) async {
  final repository = ref.watch(partsRepositoryProvider);
  return await repository.getPart(partId);
});

/// Provider for searching parts by query
final partSearchProvider =
    FutureProvider.family<List<Part>, String>((ref, query) async {
  final repository = ref.watch(partsRepositoryProvider);
  return await repository.searchParts(query);
});

/// Provider for parts filtered by type
final partsByTypeProvider =
    FutureProvider.family<List<Part>, PartType>((ref, type) async {
  final repository = ref.watch(partsRepositoryProvider);
  return await repository.getParts(type: type);
});

/// Management class for part CRUD operations
class PartsManagement {
  final Ref ref;

  PartsManagement(this.ref);

  Future<Part> createPart({
    required String name,
    required String partNumber,
    String? description,
    required PartType partType,
    required PartCategory category,
    required UnitOfMeasure unitOfMeasure,
    double? reorderThreshold,
  }) async {
    final repository = ref.read(partsRepositoryProvider);
    final part = await repository.createPart(
      name: name,
      partNumber: partNumber,
      description: description,
      partType: partType,
      category: category,
      unitOfMeasure: unitOfMeasure,
      reorderThreshold: reorderThreshold,
    );

    ref.invalidate(partsListProvider);
    return part;
  }

  Future<Part> updatePart(
    String id, {
    String? name,
    String? partNumber,
    String? description,
    PartType? partType,
    PartCategory? category,
    UnitOfMeasure? unitOfMeasure,
    double? reorderThreshold,
  }) async {
    final repository = ref.read(partsRepositoryProvider);
    final part = await repository.updatePart(
      id,
      name: name,
      partNumber: partNumber,
      description: description,
      partType: partType,
      category: category,
      unitOfMeasure: unitOfMeasure,
      reorderThreshold: reorderThreshold,
    );

    ref.invalidate(partDetailProvider(id));
    ref.invalidate(partsListProvider);
    return part;
  }

  Future<void> deletePart(String id) async {
    final repository = ref.read(partsRepositoryProvider);
    await repository.deletePart(id);

    ref.invalidate(partDetailProvider(id));
    ref.invalidate(partsListProvider);
  }
}

/// Provider for part management operations
final partsManagementProvider = Provider<PartsManagement>((ref) {
  return PartsManagement(ref);
});
