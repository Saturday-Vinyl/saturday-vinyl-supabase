import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/models/machine_macro.dart';
import 'package:saturday_app/repositories/machine_macro_repository.dart';

/// Provider for machine macro repository
final macroRepositoryProvider = Provider<MachineMacroRepository>((ref) {
  return MachineMacroRepository();
});

/// Provider for fetching active CNC macros
final cncMacrosProvider = FutureProvider<List<MachineMacro>>((ref) async {
  final repository = ref.read(macroRepositoryProvider);
  return repository.getMacrosByMachineType('cnc');
});

/// Provider for fetching active Laser macros
final laserMacrosProvider = FutureProvider<List<MachineMacro>>((ref) async {
  final repository = ref.read(macroRepositoryProvider);
  return repository.getMacrosByMachineType('laser');
});

/// Provider for fetching all macros (including inactive), for settings screen
final allMacrosProvider = FutureProvider<List<MachineMacro>>((ref) async {
  final repository = ref.read(macroRepositoryProvider);
  return repository.getAllMacros();
});

/// Provider for fetching all macros by machine type (including inactive), for settings screen filtering
final macrosByMachineTypeProvider = FutureProvider.family<List<MachineMacro>, String>(
  (ref, machineType) async {
    final repository = ref.read(macroRepositoryProvider);
    return repository.getMacrosByMachineTypeAll(machineType);
  },
);

/// Provider for machine macro management operations
final macroManagementProvider = Provider<MacroManagement>((ref) {
  final repository = ref.read(macroRepositoryProvider);
  return MacroManagement(repository, ref);
});

/// Class for managing machine macro operations
class MacroManagement {
  final MachineMacroRepository _repository;
  final Ref _ref;

  MacroManagement(this._repository, this._ref);

  /// Get active macros for a specific machine type
  Future<List<MachineMacro>> getMacrosByMachineType(String machineType) async {
    return await _repository.getMacrosByMachineType(machineType);
  }

  /// Get all macros (including inactive)
  Future<List<MachineMacro>> getAllMacros() async {
    return await _repository.getAllMacros();
  }

  /// Get all macros by machine type (including inactive)
  Future<List<MachineMacro>> getMacrosByMachineTypeAll(String machineType) async {
    return await _repository.getMacrosByMachineTypeAll(machineType);
  }

  /// Get a single macro by ID
  Future<MachineMacro?> getMacroById(String id) async {
    return await _repository.getMacroById(id);
  }

  /// Create a new macro
  Future<MachineMacro> createMacro(MachineMacro macro) async {
    final createdMacro = await _repository.createMacro(macro);

    // Invalidate relevant providers to refresh UI
    _ref.invalidate(allMacrosProvider);
    _ref.invalidate(cncMacrosProvider);
    _ref.invalidate(laserMacrosProvider);
    _ref.invalidate(macrosByMachineTypeProvider);

    return createdMacro;
  }

  /// Update an existing macro
  Future<MachineMacro> updateMacro(MachineMacro macro) async {
    final updatedMacro = await _repository.updateMacro(macro);

    // Invalidate relevant providers to refresh UI
    _ref.invalidate(allMacrosProvider);
    _ref.invalidate(cncMacrosProvider);
    _ref.invalidate(laserMacrosProvider);
    _ref.invalidate(macrosByMachineTypeProvider);

    return updatedMacro;
  }

  /// Delete a macro
  Future<void> deleteMacro(String id) async {
    await _repository.deleteMacro(id);

    // Invalidate relevant providers to refresh UI
    _ref.invalidate(allMacrosProvider);
    _ref.invalidate(cncMacrosProvider);
    _ref.invalidate(laserMacrosProvider);
    _ref.invalidate(macrosByMachineTypeProvider);
  }

  /// Reorder macros for a specific machine type
  Future<void> reorderMacros(String machineType, List<String> macroIds) async {
    await _repository.reorderMacros(machineType, macroIds);

    // Invalidate relevant providers to refresh UI
    _ref.invalidate(allMacrosProvider);
    if (machineType == 'cnc') {
      _ref.invalidate(cncMacrosProvider);
    } else if (machineType == 'laser') {
      _ref.invalidate(laserMacrosProvider);
    }
    _ref.invalidate(macrosByMachineTypeProvider);
  }
}
