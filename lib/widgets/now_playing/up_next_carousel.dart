import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/album_recommendation.dart';
import 'package:saturday_consumer_app/models/playback_queue_item.dart';
import 'package:saturday_consumer_app/providers/device_provider.dart';
import 'package:saturday_consumer_app/providers/playback_queue_provider.dart';
import 'package:saturday_consumer_app/providers/realtime_album_location_provider.dart';
import 'package:saturday_consumer_app/providers/recommendations_provider.dart';
import 'package:saturday_consumer_app/providers/repository_providers.dart';

/// "Up next" surface on the Now Playing screen.
///
/// When the user has a persisted playback queue, this shows the next 1–3
/// items with cover, title, artist, runtime and a crate-location pill
/// that doubles as a LED-locate trigger. Tapping a row opens the full
/// queue. When the queue is empty, this falls back to a horizontal
/// carousel of server-scored recommendations from the recommend-albums
/// edge function — tapping a recommendation appends it to the queue.
class UpNextCarousel extends ConsumerWidget {
  const UpNextCarousel({super.key});

  static const int _maxQueuePreview = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(playbackQueueProvider);

    if (queue.isLoading && queue.items.isEmpty) {
      return const _LoadingShell();
    }

    final upcoming = queue.items.take(_maxQueuePreview).toList();

    if (upcoming.isEmpty) {
      return const _EmptyQueueRecommendations();
    }

    return _QueueUpNext(
      upcoming: upcoming,
      totalCount: queue.items.length,
    );
  }
}

class _QueueUpNext extends StatelessWidget {
  const _QueueUpNext({required this.upcoming, required this.totalCount});

  final List<PlaybackQueueItem> upcoming;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.lg,
              Spacing.sm,
              Spacing.md,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Up next',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () => context.push('/now-playing/queue'),
                  child: Text(
                    totalCount > upcoming.length
                        ? 'View all ($totalCount)'
                        : 'View queue',
                  ),
                ),
              ],
            ),
          ),
          for (final item in upcoming)
            _QueueRow(
              key: ValueKey('queue-row-${item.id}'),
              item: item,
            ),
          const SizedBox(height: Spacing.sm),
        ],
      ),
    );
  }
}

class _QueueRow extends ConsumerWidget {
  const _QueueRow({super.key, required this.item});

  final PlaybackQueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = item.libraryAlbum?.album;
    final coverUrl = album?.coverImageUrl;
    final title = album?.title ?? 'Unknown Album';
    final artist = album?.artist ?? 'Unknown Artist';
    final runtime = album?.formattedTotalDuration;

    return InkWell(
      onTap: () => context.push('/now-playing/queue'),
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
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            QueueLocationPill(libraryAlbumId: item.libraryAlbumId),
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

class _EmptyQueueRecommendations extends ConsumerWidget {
  const _EmptyQueueRecommendations();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recsAsync = ref.watch(serverRecommendationsProvider(5));

    return recsAsync.when(
      loading: () => const _LoadingShell(),
      error: (_, __) => const SizedBox.shrink(),
      data: (recs) {
        if (recs.isEmpty) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          decoration: AppDecorations.card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.lg,
                  Spacing.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Suggestions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      'Tap to add',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: SaturdayColors.secondary,
                          ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 180,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  itemCount: recs.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: Spacing.md),
                  itemBuilder: (context, index) =>
                      _RecommendationCard(rec: recs[index]),
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],
          ),
        );
      },
    );
  }
}

class _RecommendationCard extends ConsumerWidget {
  const _RecommendationCard({required this.rec});

  final AlbumRecommendation rec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _add(context, ref),
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.mediumRadius,
                  boxShadow: AppShadows.card,
                ),
                child: ClipRRect(
                  borderRadius: AppRadius.mediumRadius,
                  child: rec.coverImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: rec.coverImageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              rec.title,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              rec.artist,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (rec.reason.isNotEmpty)
              Text(
                rec.reason,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: SaturdayColors.secondary,
                      fontStyle: FontStyle.italic,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(playbackQueueProvider.notifier)
          .addAlbum(rec.libraryAlbumId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('Added "${rec.title}" to queue'),
          ),
        );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add: $e')),
      );
    }
  }

  Widget _placeholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Icon(
        Icons.album_outlined,
        size: AppIconSizes.lg,
        color: SaturdayColors.secondary,
      ),
    );
  }
}

class _LoadingShell extends StatelessWidget {
  const _LoadingShell();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 80,
      decoration: AppDecorations.card(context),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

/// Pill that shows the album's last-known crate location and, on tap, sends
/// the LED "pulse" pattern command to that crate so the user can find it.
///
/// Returns SizedBox.shrink() when location/crate metadata is unavailable.
class QueueLocationPill extends ConsumerStatefulWidget {
  const QueueLocationPill({super.key, required this.libraryAlbumId});

  final String libraryAlbumId;

  @override
  ConsumerState<QueueLocationPill> createState() =>
      _QueueLocationPillState();
}

class _QueueLocationPillState extends ConsumerState<QueueLocationPill> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final location = ref.watch(albumLocationProvider(widget.libraryAlbumId));
    if (location == null) return const SizedBox.shrink();

    final deviceAsync = ref.watch(deviceByIdProvider(location.deviceId));
    final device = deviceAsync.valueOrNull;
    if (device == null) return const SizedBox.shrink();

    final crateName = device.name;
    final macAddress = device.macAddress;
    final canIdentify = !_sending && macAddress != null;

    return TextButton.icon(
      onPressed: canIdentify ? () => _identify(macAddress) : null,
      icon: _sending
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.lightbulb_outline, size: 16),
      label: Text(
        crateName,
        style: Theme.of(context).textTheme.labelMedium,
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.xs,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Future<void> _identify(String macAddress) async {
    setState(() => _sending = true);
    try {
      await ref.read(unitRepositoryProvider).sendDeviceCommand(
            macAddress: macAddress,
            command: 'pattern',
            parameters: const {'pattern': 'pulse', 'loop': 5},
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Lighting up the crate…')),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not flash crate: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}
