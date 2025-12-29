import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_member.dart';
import 'package:saturday_consumer_app/providers/library_provider.dart';

/// Library switcher dropdown in the app bar.
class LibrarySwitcherButton extends ConsumerWidget {
  const LibrarySwitcherButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLibrary = ref.watch(currentLibraryProvider);
    final librariesAsync = ref.watch(userLibrariesProvider);

    final libraryName = currentLibrary?.name ?? 'Library';
    final hasMultipleLibraries = (librariesAsync.valueOrNull?.length ?? 0) > 1;

    return GestureDetector(
      onTap: () => _showLibrarySwitcher(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              libraryName,
              style: Theme.of(context).appBarTheme.titleTextStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasMultipleLibraries) ...[
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down, size: 24),
          ],
        ],
      ),
    );
  }

  void _showLibrarySwitcher(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const LibrarySwitcherSheet(),
    );
  }
}

/// Bottom sheet for switching between libraries.
class LibrarySwitcherSheet extends ConsumerWidget {
  const LibrarySwitcherSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final librariesAsync = ref.watch(userLibrariesProvider);
    final currentLibraryId = ref.watch(currentLibraryIdProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Switch Library',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Libraries list
            Expanded(
              child: librariesAsync.when(
                data: (libraries) {
                  if (libraries.isEmpty) {
                    return _buildEmptyState(context, ref);
                  }

                  return ListView.builder(
                    controller: scrollController,
                    itemCount: libraries.length + 1, // +1 for create button
                    itemBuilder: (context, index) {
                      if (index == libraries.length) {
                        // Create new library button
                        return ListTile(
                          leading: const Icon(Icons.add_circle_outline),
                          title: const Text('Create New Library'),
                          onTap: () {
                            Navigator.pop(context);
                            context.push('/library/create');
                          },
                        );
                      }

                      final libraryWithRole = libraries[index];
                      final library = libraryWithRole.library;
                      final role = libraryWithRole.role;
                      final isSelected = library.id == currentLibraryId;

                      return ListTile(
                        leading: Icon(
                          role == LibraryRole.owner
                              ? Icons.library_music
                              : Icons.people_outline,
                          color: isSelected
                              ? SaturdayColors.primaryDark
                              : SaturdayColors.secondary,
                        ),
                        title: Text(
                          library.name,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(_getRoleLabel(role)),
                        trailing: isSelected
                            ? Icon(Icons.check, color: SaturdayColors.success)
                            : null,
                        onTap: () {
                          ref.read(currentLibraryIdProvider.notifier).state =
                              library.id;
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: Spacing.pagePadding,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: SaturdayColors.error),
                        const SizedBox(height: Spacing.md),
                        Text(
                          'Failed to load libraries',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: Spacing.sm),
                        TextButton(
                          onPressed: () {
                            ref.invalidate(userLibrariesProvider);
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: Spacing.pagePadding,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.library_music_outlined,
              size: 64,
              color: SaturdayColors.secondary,
            ),
            const SizedBox(height: Spacing.lg),
            Text(
              'No Libraries Yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Create your first library to start adding albums',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xl),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.push('/library/create');
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Library'),
            ),
          ],
        ),
      ),
    );
  }

  String _getRoleLabel(LibraryRole role) {
    switch (role) {
      case LibraryRole.owner:
        return 'Owner';
      case LibraryRole.editor:
        return 'Can edit';
      case LibraryRole.viewer:
        return 'View only';
    }
  }
}
