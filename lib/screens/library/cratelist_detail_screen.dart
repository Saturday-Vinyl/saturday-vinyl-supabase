import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/cratelist.dart';
import 'package:saturday_consumer_app/models/cratelist_item.dart';
import 'package:saturday_consumer_app/providers/cratelist_provider.dart';
import 'package:saturday_consumer_app/providers/playback_queue_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';
import 'package:saturday_consumer_app/screens/library/rename_cratelist_sheet.dart';
import 'package:saturday_consumer_app/widgets/common/error_display.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
import 'package:saturday_consumer_app/widgets/library/cratelist_cover.dart';

/// Detail view for a single cratelist: header with composite cover, ordered
/// list of albums with drag-to-reorder, plus add / remove / rename / delete
/// actions. Play and queue actions are placeholders until phase 6.
class CratelistDetailScreen extends ConsumerStatefulWidget {
  const CratelistDetailScreen({super.key, required this.cratelistId});

  final String cratelistId;

  @override
  ConsumerState<CratelistDetailScreen> createState() =>
      _CratelistDetailScreenState();
}

class _CratelistDetailScreenState
    extends ConsumerState<CratelistDetailScreen> {
  /// Locally-mirrored ordered items so drag-to-reorder feels instant. The
  /// provider is the source of truth; this list is overwritten whenever the
  /// provider emits new data.
  List<CratelistItem>? _items;

  @override
  Widget build(BuildContext context) {
    // Sync local items from provider whenever it emits.
    ref.listen<AsyncValue<List<CratelistItem>>>(
      cratelistItemsProvider(widget.cratelistId),
      (prev, next) {
        next.whenData((items) {
          if (mounted) setState(() => _items = items);
        });
      },
    );

    final cratelistAsync =
        ref.watch(cratelistByIdProvider(widget.cratelistId));
    final itemsAsync = ref.watch(cratelistItemsProvider(widget.cratelistId));

    return cratelistAsync.when(
      loading: () => const Scaffold(
        body: LoadingIndicator.medium(),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorDisplay.fullScreen(
          message: e.toString(),
          onRetry: () =>
              ref.invalidate(cratelistByIdProvider(widget.cratelistId)),
        ),
      ),
      data: (cratelist) {
        if (cratelist == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Cratelist not found')),
          );
        }
        // Prefer locally-staged items when available so reorders look instant.
        final items = _items ?? itemsAsync.valueOrNull ?? const [];
        return _buildContent(context, cratelist, items, itemsAsync.isLoading);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    Cratelist cratelist,
    List<CratelistItem> items,
    bool itemsLoading,
  ) {
    final coverUrls = items
        .take(4)
        .map((it) => it.libraryAlbum?.album?.coverImageUrl)
        .whereType<String>()
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(cratelist.name),
        actions: [
          PopupMenuButton<_DetailAction>(
            onSelected: (action) => _onAction(context, cratelist, items, action),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _DetailAction.addToQueue,
                child: ListTile(
                  leading: Icon(Icons.playlist_add),
                  title: Text('Add to queue'),
                ),
              ),
              const PopupMenuItem(
                value: _DetailAction.shuffleAddToQueue,
                child: ListTile(
                  leading: Icon(Icons.shuffle),
                  title: Text('Shuffle and add to queue'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _DetailAction.rename,
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Rename'),
                ),
              ),
              const PopupMenuItem(
                value: _DetailAction.delete,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(cratelistByIdProvider(widget.cratelistId));
          ref.invalidate(cratelistItemsProvider(widget.cratelistId));
          await ref.read(cratelistItemsProvider(widget.cratelistId).future);
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(
                cratelist: cratelist,
                coverUrls: coverUrls,
                itemCount: items.length,
                onPlay: () => _play(context, items, shuffle: false),
                onShuffle: () => _play(context, items, shuffle: true),
              ),
            ),
            if (items.isEmpty && !itemsLoading)
              const SliverToBoxAdapter(
                child: _EmptyItemsState(),
              )
            else
              SliverReorderableList(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _ReorderableItemTile(
                    key: ValueKey(item.id),
                    index: index,
                    item: item,
                    onRemove: () => _remove(item),
                  );
                },
                onReorder: _onReorder,
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            context.push('/library/cratelists/${widget.cratelistId}/add'),
        tooltip: 'Add albums',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    Cratelist cratelist,
    List<CratelistItem> items,
    _DetailAction action,
  ) async {
    switch (action) {
      case _DetailAction.addToQueue:
        await _addToQueue(context, items, shuffle: false);
        break;
      case _DetailAction.shuffleAddToQueue:
        await _addToQueue(context, items, shuffle: true);
        break;
      case _DetailAction.rename:
        await RenameCratelistSheet.show(context, cratelist);
        break;
      case _DetailAction.delete:
        await _delete(context, cratelist);
        break;
    }
  }

  Future<void> _play(
    BuildContext context,
    List<CratelistItem> items, {
    required bool shuffle,
  }) async {
    if (items.isEmpty) return;
    final ids = items.map((i) => i.libraryAlbumId).toList();
    if (shuffle) ids.shuffle();
    try {
      await ref.read(playbackQueueProvider.notifier).replaceWith(ids);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(shuffle
              ? 'Shuffled into your queue'
              : 'Queued ${ids.length} albums to play'),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start queue: $e')),
      );
    }
  }

  Future<void> _addToQueue(
    BuildContext context,
    List<CratelistItem> items, {
    required bool shuffle,
  }) async {
    if (items.isEmpty) return;
    final ids = items.map((i) => i.libraryAlbumId).toList();
    if (shuffle) ids.shuffle();
    try {
      await ref.read(playbackQueueProvider.notifier).addAlbums(ids);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${ids.length} albums to queue')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add to queue: $e')),
      );
    }
  }

  Future<void> _delete(BuildContext context, Cratelist cratelist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete cratelist?'),
        content: Text(
          'This removes "${cratelist.name}" for everyone with access. The '
          'records themselves stay in your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SaturdayColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(cratelistRepositoryProvider)
          .deleteCratelist(cratelist.id);
      ref.invalidate(userCratelistsProvider);
      ref.invalidate(cratelistPreviewsProvider);
      if (!context.mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/library');
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (_items == null) return;
    if (newIndex > oldIndex) newIndex -= 1;

    final newItems = [..._items!];
    final moved = newItems.removeAt(oldIndex);
    newItems.insert(newIndex, moved);

    setState(() => _items = newItems);

    try {
      await ref.read(cratelistRepositoryProvider).reorderItems(
            cratelistId: widget.cratelistId,
            orderedItemIds: newItems.map((i) => i.id).toList(),
          );
      ref.invalidate(cratelistPreviewsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reorder: $e')),
      );
      // Revert optimistic update by re-reading from server.
      ref.invalidate(cratelistItemsProvider(widget.cratelistId));
    }
  }

  Future<void> _remove(CratelistItem item) async {
    if (_items == null) return;

    final previous = _items!;
    setState(() {
      _items = _items!.where((i) => i.id != item.id).toList();
    });

    try {
      await ref.read(cratelistRepositoryProvider).removeItem(item.id);
      ref.invalidate(cratelistPreviewsProvider);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove: $e')),
      );
    }
  }

}

enum _DetailAction { addToQueue, shuffleAddToQueue, rename, delete }

class _Header extends StatelessWidget {
  const _Header({
    required this.cratelist,
    required this.coverUrls,
    required this.itemCount,
    required this.onPlay,
    required this.onShuffle,
  });

  final Cratelist cratelist;
  final List<String> coverUrls;
  final int itemCount;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              width: 220,
              child: CratelistCover(coverUrls: coverUrls),
            ),
          ),
          const SizedBox(height: Spacing.lg),
          Text(
            cratelist.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (cratelist.description != null &&
              cratelist.description!.trim().isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              cratelist.description!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
            ),
          ],
          const SizedBox(height: Spacing.xs),
          Text(
            _countLabel(itemCount),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
          const SizedBox(height: Spacing.lg),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: itemCount == 0 ? null : onPlay,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
              const SizedBox(width: Spacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: itemCount == 0 ? null : onShuffle,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Shuffle'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _countLabel(int count) {
    if (count == 0) return 'Empty cratelist';
    if (count == 1) return '1 album';
    return '$count albums';
  }
}

class _EmptyItemsState extends StatelessWidget {
  const _EmptyItemsState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.xl,
      ),
      child: Column(
        children: [
          Icon(
            Icons.queue_music,
            size: AppIconSizes.feature,
            color: SaturdayColors.secondary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'No albums yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.xs),
          Text(
            'Use "Add albums" to fill this cratelist.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ReorderableItemTile extends StatelessWidget {
  const _ReorderableItemTile({
    super.key,
    required this.index,
    required this.item,
    required this.onRemove,
  });

  final int index;
  final CratelistItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final album = item.libraryAlbum?.album;
    final coverUrl = album?.coverImageUrl;
    final title = album?.title ?? 'Unknown Album';
    final artist = album?.artist ?? 'Unknown Artist';

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.lg,
          vertical: Spacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: ClipRRect(
                borderRadius: AppRadius.smallRadius,
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(width: Spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    artist,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.secondary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onRemove,
              tooltip: 'Remove from cratelist',
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: Spacing.xs),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Icon(
        Icons.album_outlined,
        size: AppIconSizes.md,
        color: SaturdayColors.secondary,
      ),
    );
  }
}
