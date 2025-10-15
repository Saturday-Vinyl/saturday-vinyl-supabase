import 'package:saturday_app/models/machine_macro.dart';
import 'package:saturday_app/services/supabase_service.dart';
import 'package:saturday_app/utils/app_logger.dart';

/// Repository for managing machine macros
class MachineMacroRepository {
  final _supabase = SupabaseService.instance.client;

  /// Get active macros for a specific machine type, ordered by execution_order
  Future<List<MachineMacro>> getMacrosByMachineType(String machineType) async {
    try {
      AppLogger.info('Fetching macros for machine type: $machineType');

      final response = await _supabase
          .from('machine_macros')
          .select()
          .eq('machine_type', machineType)
          .eq('is_active', true)
          .order('execution_order');

      final macros = (response as List)
          .map((json) => MachineMacro.fromJson(json))
          .toList();

      AppLogger.info('Found ${macros.length} active macros for $machineType');
      return macros;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching macros by machine type', error, stackTrace);
      rethrow;
    }
  }

  /// Get all macros (including inactive ones), for settings screen
  Future<List<MachineMacro>> getAllMacros() async {
    try {
      AppLogger.info('Fetching all macros');

      final response = await _supabase
          .from('machine_macros')
          .select()
          .order('machine_type')
          .order('execution_order');

      final macros = (response as List)
          .map((json) => MachineMacro.fromJson(json))
          .toList();

      AppLogger.info('Found ${macros.length} total macros');
      return macros;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching all macros', error, stackTrace);
      rethrow;
    }
  }

  /// Get a single macro by ID
  Future<MachineMacro?> getMacroById(String id) async {
    try {
      AppLogger.info('Fetching macro: $id');

      final response = await _supabase
          .from('machine_macros')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (response == null) {
        AppLogger.info('Macro not found: $id');
        return null;
      }

      return MachineMacro.fromJson(response);
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching macro by ID', error, stackTrace);
      rethrow;
    }
  }

  /// Create a new macro
  Future<MachineMacro> createMacro(MachineMacro macro) async {
    try {
      AppLogger.info('Creating macro: ${macro.name}');

      // Convert to JSON and remove id field (let database generate it)
      final json = macro.toJson();
      json.remove('id');

      final response = await _supabase
          .from('machine_macros')
          .insert(json)
          .select()
          .single();

      final createdMacro = MachineMacro.fromJson(response);
      AppLogger.info('Created macro: ${createdMacro.id}');
      return createdMacro;
    } catch (error, stackTrace) {
      AppLogger.error('Error creating macro', error, stackTrace);
      rethrow;
    }
  }

  /// Update an existing macro
  Future<MachineMacro> updateMacro(MachineMacro macro) async {
    try {
      AppLogger.info('Updating macro: ${macro.id}');

      final response = await _supabase
          .from('machine_macros')
          .update(macro.toJson())
          .eq('id', macro.id)
          .select()
          .single();

      final updatedMacro = MachineMacro.fromJson(response);
      AppLogger.info('Updated macro: ${updatedMacro.id}');
      return updatedMacro;
    } catch (error, stackTrace) {
      AppLogger.error('Error updating macro', error, stackTrace);
      rethrow;
    }
  }

  /// Delete a macro
  Future<void> deleteMacro(String id) async {
    try {
      AppLogger.info('Deleting macro: $id');

      await _supabase
          .from('machine_macros')
          .delete()
          .eq('id', id);

      AppLogger.info('Deleted macro: $id');
    } catch (error, stackTrace) {
      AppLogger.error('Error deleting macro', error, stackTrace);
      rethrow;
    }
  }

  /// Reorder macros for a specific machine type
  /// Takes a list of macro IDs in the desired order and updates execution_order
  Future<void> reorderMacros(String machineType, List<String> macroIds) async {
    try {
      AppLogger.info('Reordering ${macroIds.length} macros for $machineType');

      // Update each macro's execution_order based on its position in the list
      for (var i = 0; i < macroIds.length; i++) {
        final macroId = macroIds[i];
        final newOrder = i + 1; // execution_order starts at 1

        await _supabase
            .from('machine_macros')
            .update({'execution_order': newOrder})
            .eq('id', macroId)
            .eq('machine_type', machineType);
      }

      AppLogger.info('Reordered macros for $machineType');
    } catch (error, stackTrace) {
      AppLogger.error('Error reordering macros', error, stackTrace);
      rethrow;
    }
  }

  /// Get macros by machine type (including inactive), for settings screen filtering
  Future<List<MachineMacro>> getMacrosByMachineTypeAll(String machineType) async {
    try {
      AppLogger.info('Fetching all macros (including inactive) for: $machineType');

      final response = await _supabase
          .from('machine_macros')
          .select()
          .eq('machine_type', machineType)
          .order('execution_order');

      final macros = (response as List)
          .map((json) => MachineMacro.fromJson(json))
          .toList();

      AppLogger.info('Found ${macros.length} total macros for $machineType');
      return macros;
    } catch (error, stackTrace) {
      AppLogger.error('Error fetching all macros by machine type', error, stackTrace);
      rethrow;
    }
  }
}
