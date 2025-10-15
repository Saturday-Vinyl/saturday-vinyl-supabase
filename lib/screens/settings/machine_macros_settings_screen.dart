import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/machine_macro.dart';
import '../../providers/machine_macro_provider.dart';
import '../../utils/app_logger.dart';
import 'machine_macro_form_screen.dart';

/// Settings screen for managing machine macros (CNC and Laser)
class MachineMacrosSettingsScreen extends ConsumerStatefulWidget {
  const MachineMacrosSettingsScreen({super.key});

  @override
  ConsumerState<MachineMacrosSettingsScreen> createState() =>
      _MachineMacrosSettingsScreenState();
}

class _MachineMacrosSettingsScreenState
    extends ConsumerState<MachineMacrosSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _currentMachineType = 'cnc';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentMachineType = _tabController.index == 0 ? 'cnc' : 'laser';
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _deleteMacro(String macroId, String macroName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Macro'),
        content: Text('Are you sure you want to delete "$macroName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: SaturdayColors.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final macroManagement = ref.read(macroManagementProvider);
        await macroManagement.deleteMacro(macroId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Deleted "$macroName"'),
              backgroundColor: SaturdayColors.success,
            ),
          );
        }
      } catch (e, stackTrace) {
        AppLogger.error('Error deleting macro', e, stackTrace);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting macro: $e'),
              backgroundColor: SaturdayColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _reorderMacros(
      List<MachineMacro> macros, int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }

    // Create new list with reordered items
    final reorderedMacros = List<MachineMacro>.from(macros);
    final item = reorderedMacros.removeAt(oldIndex);
    reorderedMacros.insert(newIndex, item);

    // Extract IDs in new order
    final macroIds = reorderedMacros.map((m) => m.id).toList();

    try {
      final macroManagement = ref.read(macroManagementProvider);
      await macroManagement.reorderMacros(_currentMachineType, macroIds);

      AppLogger.info('Reordered macros successfully');
    } catch (e, stackTrace) {
      AppLogger.error('Error reordering macros', e, stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reordering macros: $e'),
            backgroundColor: SaturdayColors.error,
          ),
        );
      }
    }
  }

  void _navigateToCreateMacro() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MachineMacroFormScreen(
          machineType: _currentMachineType,
        ),
      ),
    );
  }

  void _navigateToEditMacro(MachineMacro macro) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MachineMacroFormScreen(
          macro: macro,
          machineType: macro.machineType,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Machine Macros'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'CNC Macros'),
            Tab(text: 'Laser Macros'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMacroList('cnc'),
          _buildMacroList('laser'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToCreateMacro,
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Macro'),
      ),
    );
  }

  Widget _buildMacroList(String machineType) {
    final macrosAsync = ref.watch(macrosByMachineTypeProvider(machineType));

    return macrosAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: SaturdayColors.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading macros',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: const TextStyle(color: SaturdayColors.secondaryGrey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      data: (macros) {
        if (macros.isEmpty) {
          return _buildEmptyState(machineType);
        }

        return ReorderableListView.builder(
          padding: const EdgeInsets.all(16),
          onReorder: (oldIndex, newIndex) =>
              _reorderMacros(macros, oldIndex, newIndex),
          itemCount: macros.length,
          itemBuilder: (context, index) {
            final macro = macros[index];
            return _buildMacroCard(macro, index);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String machineType) {
    final machineName = machineType == 'cnc' ? 'CNC' : 'Laser';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              machineType == 'cnc' ? Icons.precision_manufacturing : Icons.flash_on,
              size: 80,
              color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No $machineName Macros',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your first macro by tapping the button below',
              style: TextStyle(color: SaturdayColors.secondaryGrey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _navigateToCreateMacro,
              icon: const Icon(Icons.add),
              label: const Text('Create Macro'),
              style: ElevatedButton.styleFrom(
                backgroundColor: SaturdayColors.primaryDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMacroCard(MachineMacro macro, int index) {
    return Card(
      key: ValueKey(macro.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        // Drag handle on the left
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_handle,
              color: SaturdayColors.secondaryGrey,
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              backgroundColor: SaturdayColors.primaryDark.withValues(alpha: 0.1),
              child: Icon(
                macro.getIconData(),
                color: SaturdayColors.primaryDark,
                size: 24,
              ),
            ),
          ],
        ),
        // Macro name and description
        title: Text(
          macro.name,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: macro.description != null && macro.description!.isNotEmpty
            ? Text(
                macro.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SaturdayColors.secondaryGrey,
                  fontSize: 14,
                ),
              )
            : null,
        // Edit and Delete buttons on the right
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Active/Inactive indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: macro.isActive
                    ? SaturdayColors.success.withValues(alpha: 0.2)
                    : SaturdayColors.secondaryGrey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                macro.isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: macro.isActive
                      ? SaturdayColors.success
                      : SaturdayColors.secondaryGrey,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit),
              color: SaturdayColors.primaryDark,
              onPressed: () => _navigateToEditMacro(macro),
              tooltip: 'Edit macro',
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              color: SaturdayColors.error,
              onPressed: () => _deleteMacro(macro.id, macro.name),
              tooltip: 'Delete macro',
            ),
          ],
        ),
      ),
    );
  }
}
