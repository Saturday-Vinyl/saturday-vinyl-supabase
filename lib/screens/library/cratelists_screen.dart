import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/providers/cratelist_provider.dart';
import 'package:saturday_consumer_app/screens/library/create_cratelist_sheet.dart';
import 'package:saturday_consumer_app/widgets/common/empty_state.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
import 'package:saturday_consumer_app/widgets/library/cratelist_tile.dart';

/// Full grid view of all cratelists the current user is a member of.
///
/// Reached from the "See all" button in the cratelists section on the
/// library screen.
class CratelistsScreen extends ConsumerWidget {
  const CratelistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewsAsync = ref.watch(cratelistPreviewsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cratelists'),
      ),
      body: previewsAsync.when(
        data: (previews) {
          if (previews.isEmpty) {
            return _EmptyState(onCreate: () => _onCreate(context));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(cratelistPreviewsProvider);
              await ref.read(cratelistPreviewsProvider.future);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = _crossAxisCount(constraints.maxWidth);
                return GridView.builder(
                  padding: Spacing.pagePadding,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: Spacing.lg,
                    crossAxisSpacing: Spacing.lg,
                    childAspectRatio: _childAspectRatio(
                      constraints.maxWidth,
                      crossAxisCount,
                    ),
                  ),
                  itemCount: previews.length,
                  itemBuilder: (context, index) {
                    final preview = previews[index];
                    return CratelistTile(
                      preview: preview,
                      onTap: () => context
                          .push('/library/cratelists/${preview.cratelist.id}'),
                    );
                  },
                );
              },
            ),
          );
        },
        loading: () => const LoadingIndicator.medium(
          message: 'Loading cratelists...',
        ),
        error: (error, _) => ErrorDisplay.fullScreen(
          message: error.toString(),
          onRetry: () => ref.invalidate(cratelistPreviewsProvider),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onCreate(context),
        tooltip: 'New cratelist',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _onCreate(BuildContext context) async {
    final created = await CreateCratelistSheet.show(context);
    if (created == null || !context.mounted) return;
    context.push('/library/cratelists/${created.id}');
  }

  int _crossAxisCount(double width) {
    if (width < 400) return 2;
    if (width < 600) return 3;
    if (width < 900) return 4;
    return 5;
  }

  double _childAspectRatio(double width, int crossAxisCount) {
    final spacing = Spacing.lg * (crossAxisCount + 1);
    final availableWidth = width - spacing;
    final itemWidth = availableWidth / crossAxisCount;
    const textHeight = 60.0;
    final itemHeight = itemWidth + textHeight;
    return itemWidth / itemHeight;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.queue_music,
      title: 'No cratelists yet',
      message: 'Group records from your archive into ordered crates you can '
          'queue up to play.',
      actionLabel: 'Create cratelist',
      onAction: onCreate,
    );
  }
}
