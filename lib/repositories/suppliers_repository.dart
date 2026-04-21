import 'package:saturday_app/models/supplier.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';
import 'package:uuid/uuid.dart';

/// Repository for managing suppliers
class SuppliersRepository {
  final _supabase = SupabaseService.instance.client;
  final _uuid = const Uuid();

  /// Get all active suppliers
  Future<List<Supplier>> getSuppliers() async {
    try {
      final response = await _supabase
          .from('suppliers')
          .select()
          .eq('is_active', true)
          .order('name');

      return (response as List)
          .map((json) => Supplier.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch suppliers', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single supplier by ID
  Future<Supplier?> getSupplier(String id) async {
    try {
      final response = await _supabase
          .from('suppliers')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return Supplier.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Failed to fetch supplier $id', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new supplier
  Future<Supplier> createSupplier({
    required String name,
    String? website,
    String? notes,
  }) async {
    try {
      final id = _uuid.v4();
      final now = DateTime.now();

      await _supabase.from('suppliers').insert({
        'id': id,
        'name': name,
        'website': website,
        'notes': notes,
        'is_active': true,
        'created_at': now.toIso8601String(),
      });

      AppLogger.info('Created supplier: $name');

      return Supplier(
        id: id,
        name: name,
        website: website,
        notes: notes,
        isActive: true,
        createdAt: now,
      );
    } catch (error, stackTrace) {
      AppLogger.error('Failed to create supplier', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing supplier
  Future<Supplier> updateSupplier(
    String id, {
    String? name,
    String? website,
    String? notes,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (website != null) updates['website'] = website;
      if (notes != null) updates['notes'] = notes;

      await _supabase.from('suppliers').update(updates).eq('id', id);

      AppLogger.info('Updated supplier: $id');

      final supplier = await getSupplier(id);
      if (supplier == null) throw Exception('Supplier not found after update');
      return supplier;
    } catch (error, stackTrace) {
      AppLogger.error('Failed to update supplier $id', error, stackTrace);
      rethrow;
    }
  }

  /// Soft delete a supplier
  Future<void> deleteSupplier(String id) async {
    try {
      await _supabase
          .from('suppliers')
          .update({'is_active': false})
          .eq('id', id);

      AppLogger.info('Deleted supplier: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Failed to delete supplier $id', error, stackTrace);
      rethrow;
    }
  }
}
