import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/providers/playback_queue_provider.dart';

/// Queue access icon for the Now Playing app bar. Always visible so users
/// can reach the queue from any state (playing, queued, idle). Shows a
/// badge with the upcoming item count when the queue is non-empty.
class QueueAppBarButton extends ConsumerWidget {
  const QueueAppBarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(playbackQueueProvider).items.length;

    return IconButton(
      tooltip: count > 0 ? 'View queue ($count)' : 'View queue',
      onPressed: () => context.push('/now-playing/queue'),
      icon: count == 0
          ? const Icon(Icons.playlist_play)
          : Badge.count(
              count: count,
              child: const Icon(Icons.playlist_play),
            ),
    );
  }
}
