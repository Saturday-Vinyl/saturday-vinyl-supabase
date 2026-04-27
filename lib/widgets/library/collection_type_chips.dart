import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/providers/collection_provider.dart';

/// Three-segment type narrowing for the unified library grid:
/// All / Albums / Cratelists. Selection resets each session.
class CollectionTypeChips extends ConsumerWidget {
  const CollectionTypeChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(collectionTypeFilterProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      child: Wrap(
        spacing: Spacing.sm,
        children: [
          for (final value in CollectionTypeFilter.values)
            ChoiceChip(
              label: Text(_label(value)),
              selected: selected == value,
              onSelected: (yes) {
                if (yes) {
                  ref.read(collectionTypeFilterProvider.notifier).state = value;
                }
              },
            ),
        ],
      ),
    );
  }

  String _label(CollectionTypeFilter value) {
    return switch (value) {
      CollectionTypeFilter.all => 'All',
      CollectionTypeFilter.albums => 'Albums',
      CollectionTypeFilter.cratelists => 'Cratelists',
    };
  }
}
