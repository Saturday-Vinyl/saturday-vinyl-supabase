import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/inventory_transaction.dart';
import 'package:saturday_app/models/part.dart';
import 'package:saturday_app/providers/parts_provider.dart';
import 'package:saturday_app/repositories/inventory_repository.dart';

/// Provider for InventoryRepository
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository();
});

/// Provider for inventory level of a single part
final inventoryLevelProvider =
    FutureProvider.family<double, String>((ref, partId) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return await repository.getInventoryLevel(partId);
});

/// Provider for all inventory levels
final allInventoryLevelsProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return await repository.getAllInventoryLevels();
});

/// Provider for transaction history of a part
final transactionHistoryProvider = FutureProvider.family<
    List<InventoryTransaction>, String>((ref, partId) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  return await repository.getTransactionsForPart(partId);
});

/// A part with its current stock level, flagged as low-stock
class LowStockPart {
  final Part part;
  final double quantityOnHand;

  const LowStockPart({required this.part, required this.quantityOnHand});
}

/// Provider for parts that are at or below their reorder threshold
final lowStockPartsProvider = FutureProvider<List<LowStockPart>>((ref) async {
  final parts = await ref.watch(partsListProvider.future);
  final levels = await ref.watch(allInventoryLevelsProvider.future);

  final lowStock = <LowStockPart>[];
  for (final part in parts) {
    if (!part.isActive) continue;
    final qty = levels[part.id] ?? 0.0;
    if (part.reorderThreshold != null && qty <= part.reorderThreshold!) {
      lowStock.add(LowStockPart(part: part, quantityOnHand: qty));
    } else if (qty <= 0) {
      lowStock.add(LowStockPart(part: part, quantityOnHand: qty));
    }
  }

  // Sort: zero stock first, then by how far below threshold
  lowStock.sort((a, b) {
    if (a.quantityOnHand <= 0 && b.quantityOnHand > 0) return -1;
    if (b.quantityOnHand <= 0 && a.quantityOnHand > 0) return 1;
    return a.quantityOnHand.compareTo(b.quantityOnHand);
  });

  return lowStock;
});

/// Provider for just the count of low-stock parts (lightweight for badges)
final lowStockCountProvider = FutureProvider<int>((ref) async {
  final lowStock = await ref.watch(lowStockPartsProvider.future);
  return lowStock.length;
});

/// Management class for inventory operations
class InventoryManagement {
  final Ref ref;

  InventoryManagement(this.ref);

  /// Record receiving inventory
  Future<InventoryTransaction> receive({
    required String partId,
    required double quantity,
    String? supplierId,
    String? reference,
    required String performedBy,
  }) async {
    final repository = ref.read(inventoryRepositoryProvider);
    final transaction = await repository.createTransaction(
      partId: partId,
      transactionType: TransactionType.receive,
      quantity: quantity,
      supplierId: supplierId,
      reference: reference,
      performedBy: performedBy,
    );

    _invalidateForPart(partId);
    return transaction;
  }

  /// Record inventory adjustment
  Future<InventoryTransaction> adjust({
    required String partId,
    required double quantity,
    String? reference,
    required String performedBy,
  }) async {
    final repository = ref.read(inventoryRepositoryProvider);
    final transaction = await repository.createTransaction(
      partId: partId,
      transactionType: TransactionType.adjust,
      quantity: quantity,
      reference: reference,
      performedBy: performedBy,
    );

    _invalidateForPart(partId);
    return transaction;
  }

  void _invalidateForPart(String partId) {
    ref.invalidate(inventoryLevelProvider(partId));
    ref.invalidate(allInventoryLevelsProvider);
    ref.invalidate(transactionHistoryProvider(partId));
  }
}

/// Provider for inventory management operations
final inventoryManagementProvider = Provider<InventoryManagement>((ref) {
  return InventoryManagement(ref);
});

/// StateProvider for forwarding USB barcode scans from the global keyboard
/// listener to the parts scan-receive screen. Set to a barcode string to
/// trigger processing; the consumer resets it to null after handling.
final usbBarcodeProvider = StateProvider<String?>((ref) => null);
