import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/unit_provider.dart';
import 'package:saturday_app/screens/production/create_unit_screen.dart';
import 'package:saturday_app/screens/production/unit_detail_screen.dart';
import 'package:saturday_app/widgets/production/unit_card.dart';

/// Screen showing all production units
class ProductionUnitsScreen extends ConsumerWidget {
  const ProductionUnitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unitsAsync = ref.watch(unitsInProductionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Production Units'),
        backgroundColor: SaturdayColors.primaryDark,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToCreateUnit(context),
        backgroundColor: SaturdayColors.success,
        icon: const Icon(Icons.add),
        label: const Text('Create Unit'),
      ),
      body: unitsAsync.when(
        data: (units) {
          if (units.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.qr_code_2,
                    size: 64,
                    color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No units in production',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first production unit',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: SaturdayColors.secondaryGrey,
                        ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: units.length,
            itemBuilder: (context, index) {
              final unit = units[index];

              // Get step counts for this unit
              final stepsAsync = ref.watch(unitStepsProvider(unit.id));
              final completionsAsync = ref.watch(unitStepCompletionsProvider(unit.id));

              return stepsAsync.when(
                data: (steps) {
                  return completionsAsync.when(
                    data: (completions) {
                      return UnitCard(
                        unit: unit,
                        totalSteps: steps.length,
                        completedSteps: completions.length,
                        onTap: () => _navigateToUnitDetail(context, unit.id),
                      );
                    },
                    loading: () => UnitCard(
                      unit: unit,
                      totalSteps: 0,
                      completedSteps: 0,
                      onTap: () => _navigateToUnitDetail(context, unit.id),
                    ),
                    error: (_, __) => UnitCard(
                      unit: unit,
                      totalSteps: 0,
                      completedSteps: 0,
                      onTap: () => _navigateToUnitDetail(context, unit.id),
                    ),
                  );
                },
                loading: () => UnitCard(
                  unit: unit,
                  totalSteps: 0,
                  completedSteps: 0,
                  onTap: () => _navigateToUnitDetail(context, unit.id),
                ),
                error: (_, __) => UnitCard(
                  unit: unit,
                  totalSteps: 0,
                  completedSteps: 0,
                  onTap: () => _navigateToUnitDetail(context, unit.id),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('Error: $error'),
        ),
      ),
    );
  }

  void _navigateToCreateUnit(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateUnitScreen(),
      ),
    );
  }

  void _navigateToUnitDetail(BuildContext context, String unitId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UnitDetailScreen(unitId: unitId),
      ),
    );
  }
}
