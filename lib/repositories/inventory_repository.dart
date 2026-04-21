import 'package:saturday_app/models/inventory_transaction.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing inventory transactions and levels
class InventoryRepository {
  final _supabase = SupabaseService.instance.client;
  final _uuid = const Uuid();

  /// Create a single inventory transaction
  Future<InventoryTransaction> createTransaction({
    required String partId,
    required TransactionType transactionType,
    required double quantity,
    String? unitId,
    String? stepCompletionId,
    String? supplierId,
    String? buildBatchId,
    String? reference,
    required String performedBy,
  }) async {
    try {
      final id = _uuid.v4();
      final now = DateTime.now();

      await _supabase.from('inventory_transactions').insert({
        'id': id,
        'part_id': partId,
        'transaction_type': transactionType.value,
        'quantity': quantity,
        'unit_id': unitId,
        'step_completion_id': stepCompletionId,
        'supplier_id': supplierId,
        'build_batch_id': buildBatchId,
        'reference': reference,
        'performed_by': performedBy,
        'performed_at': now.toIso8601String(),
      });

      AppLogger.info(
          'Created ${transactionType.value} transaction for part $partId: $quantity');

      return InventoryTransaction(
        id: id,
        partId: partId,
        transactionType: transactionType,
        quantity: quantity,
        unitId: unitId,
        stepCompletionId: stepCompletionId,
        supplierId: supplierId,
        buildBatchId: buildBatchId,
        reference: reference,
        performedBy: performedBy,
        performedAt: now,
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create inventory transaction', error, stackTrace);
      rethrow;
    }
  }

  /// Create multiple transactions in a batch (for sub-assembly builds)
  Future<void> createTransactions(
      List<Map<String, dynamic>> transactions) async {
    try {
      // Add IDs and timestamps to each transaction
      final rows = transactions.map((t) {
        return {
          'id': _uuid.v4(),
          'performed_at': DateTime.now().toIso8601String(),
          ...t,
        };
      }).toList();

      await _supabase.from('inventory_transactions').insert(rows);

      AppLogger.info('Created ${rows.length} inventory transactions in batch');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create batch transactions', error, stackTrace);
      rethrow;
    }
  }

  /// Check if a receive transaction with this reference already exists
  Future<bool> hasReceiveWithReference(String reference) async {
    try {
      final response = await _supabase
          .from('inventory_transactions')
          .select('id')
          .eq('transaction_type', 'receive')
          .eq('reference', reference)
          .limit(1);

      return (response as List).isNotEmpty;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to check duplicate reference', error, stackTrace);
      return false;
    }
  }

  /// Get recent transactions for a part
  Future<List<InventoryTransaction>> getTransactionsForPart(
    String partId, {
    int limit = 50,
  }) async {
    try {
      final response = await _supabase
          .from('inventory_transactions')
          .select()
          .eq('part_id', partId)
          .order('performed_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((json) =>
              InventoryTransaction.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to fetch transactions for part $partId', error, stackTrace);
      rethrow;
    }
  }

  /// Reassign all inventory transactions from one part to another
  Future<void> reassignTransactions(String fromPartId, String toPartId) async {
    try {
      await _supabase
          .from('inventory_transactions')
          .update({'part_id': toPartId})
          .eq('part_id', fromPartId);
      AppLogger.info(
          'Reassigned inventory transactions from $fromPartId to $toPartId');
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to reassign inventory transactions', error, stackTrace);
      rethrow;
    }
  }

  /// Get current inventory level for a single part
  Future<double> getInventoryLevel(String partId) async {
    try {
      final response = await _supabase
          .from('inventory_levels')
          .select('quantity_on_hand')
          .eq('part_id', partId)
          .maybeSingle();

      if (response == null) return 0.0;
      return (response['quantity_on_hand'] as num).toDouble();
    } catch (error, stackTrace) {
      AppLogger.error(
          'Failed to get inventory level for $partId', error, stackTrace);
      rethrow;
    }
  }

  /// Get inventory levels for all parts
  Future<Map<String, double>> getAllInventoryLevels() async {
    try {
      final response = await _supabase.from('inventory_levels').select();

      final levels = <String, double>{};
      for (final row in response as List) {
        final map = row as Map<String, dynamic>;
        levels[map['part_id'] as String] =
            (map['quantity_on_hand'] as num).toDouble();
      }
      return levels;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to get all inventory levels', error, stackTrace);
      rethrow;
    }
  }
}
