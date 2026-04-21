import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/sub_assembly_line.dart';
import 'package:saturday_app/repositories/sub_assembly_repository.dart';

/// Provider for SubAssemblyRepository
final subAssemblyRepositoryProvider = Provider<SubAssemblyRepository>((ref) {
  return SubAssemblyRepository();
});

/// Count how many sub-assemblies use a part as a child component
final subAssemblyUsageCountProvider =
    FutureProvider.family<int, String>((ref, childPartId) async {
  final repository = ref.watch(subAssemblyRepositoryProvider);
  return await repository.countUsagesAsChild(childPartId);
});

/// Part IDs that are exclusively used as board-assembled components
final boardAssembledOnlyPartIdsProvider =
    FutureProvider<Set<String>>((ref) async {
  final repository = ref.watch(subAssemblyRepositoryProvider);
  return await repository.getBoardAssembledOnlyPartIds();
});

/// Provider for sub-assembly component lines
final subAssemblyLinesProvider = FutureProvider.family<List<SubAssemblyLine>,
    String>((ref, parentPartId) async {
  final repository = ref.watch(subAssemblyRepositoryProvider);
  return await repository.getSubAssemblyLines(parentPartId);
});
