import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/playback_queue_item.dart';
import 'package:saturday_consumer_app/providers/playback_queue_provider.dart';
import 'package:saturday_consumer_app/widgets/common/empty_state.dart';
import 'package:saturday_consumer_app/widgets/now_playing/up_next_carousel.dart'
    show QueueLocationPill;

/// Full view of the user's persisted playback queue. Editable: reorder,
/// remove, add. Drives auto-advance via the head of the list matching
/// detected RFID albums.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// Local mirror of queue items so drag-to-reorder feels instant. The
  /// provider is the source of truth and overwrites this whenever it
  /// emits new state.
  List<PlaybackQueueItem>? _items;

  @override
  Widget build(BuildContext context) {
    ref.listen<PlaybackQueueState>(playbackQueueProvider, (prev, next) {
      if (mounted) setState(() => _items = next.items);
    });

    final state = ref.watch(playbackQueueProvider);
    final items = _items ?? state.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Queue'),
        actions: [
          if (items.isNotEmpty)
            PopupMenuButton<_QueueAction>(
              onSelected: _onAction,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _QueueAction.clear,
                  child: ListTile(
                    leading: Icon(Icons.delete_sweep_outlined),
                    title: Text('Clear queue'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: state.error != null
          ? Center(child: Text('Could not load queue: ${state.error}'))
          : items.isEmpty
              ? EmptyState(
                  icon: Icons.playlist_play,
                  title: 'Queue is empty',
                  message: 'Add albums from your library or a cratelist to '
                      'plan what to listen to next.',
                  actionLabel: 'Add albums',
                  onAction: () => context.push('/now-playing/queue/add'),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: items.length,
                  buildDefaultDragHandles: false,
                  onReorder: _onReorder,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _QueueRow(
                      key: ValueKey(item.id),
                      index: index,
                      item: item,
                      onRemove: () => _remove(item),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/now-playing/queue/add'),
        tooltip: 'Add to queue',
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _onAction(_QueueAction action) async {
    switch (action) {
      case _QueueAction.clear:
        await _clearWithConfirm();
        break;
    }
  }

  Future<void> _clearWithConfirm() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear queue?'),
        content: const Text('This removes everything currently queued.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: SaturdayColors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(playbackQueueProvider.notifier).clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear queue: $e')),
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
      await ref
          .read(playbackQueueProvider.notifier)
          .reorder(newItems.map((i) => i.id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reorder: $e')),
      );
      // Revert by trusting the next provider emission.
      setState(() => _items = ref.read(playbackQueueProvider).items);
    }
  }

  Future<void> _remove(PlaybackQueueItem item) async {
    if (_items == null) return;
    final previous = _items!;
    setState(() {
      _items = _items!.where((i) => i.id != item.id).toList();
    });
    try {
      await ref.read(playbackQueueProvider.notifier).removeItem(item.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove: $e')),
      );
    }
  }
}

enum _QueueAction { clear }

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.index,
    required this.item,
    required this.onRemove,
  });

  final int index;
  final PlaybackQueueItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final album = item.libraryAlbum?.album;
    final coverUrl = album?.coverImageUrl;
    final title = album?.title ?? 'Unknown Album';
    final artist = album?.artist ?? 'Unknown Artist';
    final runtime = album?.formattedTotalDuration;

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
              width: 56,
              height: 56,
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
                    [
                      artist,
                      if (runtime != null && runtime.isNotEmpty) runtime,
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.secondary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Spacing.xs),
                  QueueLocationPill(libraryAlbumId: item.libraryAlbumId),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Remove from queue',
              onPressed: onRemove,
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
