import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/album_recommendation.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/app_lifecycle_provider.dart';
import 'package:saturday_consumer_app/providers/cratelist_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/playback_queue_provider.dart';
import 'package:saturday_consumer_app/providers/playback_sync_provider.dart';
import 'package:saturday_consumer_app/providers/realtime_now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/recommendations_provider.dart';
import 'package:saturday_consumer_app/repositories/cratelist_repository.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/home/now_playing_mini_bar.dart';
import 'package:saturday_consumer_app/widgets/library/cratelist_cover.dart';
import 'package:saturday_consumer_app/widgets/now_playing/queue_app_bar_button.dart';

/// App home screen.
///
/// Cover-centric horizontal scrolls of recently played, the user's
/// cratelists, recommended albums, and recommended cratelists. When
/// something is playing, a compact mini-bar floats above the content
/// and opens the dedicated Now Playing detail screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const double _coverSize = 150;
  static const double _sectionTitleGap = Spacing.md;
  static const int _recommendationLimit = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the same background plumbing the old Now Playing screen wired up
    // so hub detections, lifecycle recovery, and queue auto-advance continue
    // to fire while Home is the foreground tab.
    ref.watch(realtimeNowPlayingProvider);
    ref.watch(playbackSyncProvider);
    ref.watch(appLifecycleProvider);
    ref.watch(queueAutoAdvanceProvider);

    return Scaffold(
      appBar: const SaturdayAppBar(
        title: 'Home',
        showSearch: true,
        actions: [QueueAppBarButton()],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(recentlyPlayedProvider);
                ref.invalidate(cratelistPreviewsProvider);
                ref.invalidate(serverRecommendationsProvider);
                await Future.wait([
                  ref.read(recentlyPlayedProvider.future),
                  ref.read(cratelistPreviewsProvider.future),
                  ref.read(serverRecommendationsProvider(_recommendationLimit)
                      .future),
                ]);
              },
              child: ListView(
                padding: const EdgeInsets.only(
                  top: Spacing.md,
                  // Reserve space so the floating mini bar never covers content.
                  bottom: 96 + Spacing.xl,
                ),
                children: [
                  _RecentlyPlayedSection(coverSize: _coverSize),
                  const SizedBox(height: Spacing.xl),
                  _MyCratelistsSection(coverSize: _coverSize),
                  const SizedBox(height: Spacing.xl),
                  _RecommendedAlbumsSection(
                    coverSize: _coverSize,
                    limit: _recommendationLimit,
                  ),
                  const SizedBox(height: Spacing.xl),
                  const _RecommendedCratelistsStub(coverSize: _coverSize),
                ],
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: NowPlayingMiniBar(),
            ),
          ],
        ),
      ),
    );
  }

  static Widget sectionGap() => const SizedBox(height: _sectionTitleGap);
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recently played
// ---------------------------------------------------------------------------

class _RecentlyPlayedSection extends ConsumerWidget {
  const _RecentlyPlayedSection({required this.coverSize});

  final double coverSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Recently Played'),
        HomeScreen.sectionGap(),
        SizedBox(
          height: coverSize + 56,
          child: recentlyPlayed.when(
            data: (albums) {
              if (albums.isEmpty) {
                return _EmptyHero(
                  coverSize: coverSize,
                  message: 'No listening history yet',
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.lg),
                itemCount: albums.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: Spacing.md),
                itemBuilder: (context, index) {
                  return _AlbumCoverTile(
                    libraryAlbum: albums[index],
                    coverSize: coverSize,
                  );
                },
              );
            },
            loading: () => _LoadingRow(coverSize: coverSize),
            error: (_, __) => _ErrorRow(
              coverSize: coverSize,
              message: 'Failed to load history',
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// My cratelists
// ---------------------------------------------------------------------------

class _MyCratelistsSection extends ConsumerWidget {
  const _MyCratelistsSection({required this.coverSize});

  final double coverSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewsAsync = ref.watch(cratelistPreviewsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'My Cratelists',
          onSeeAll: () => context.push('/library/cratelists'),
        ),
        HomeScreen.sectionGap(),
        SizedBox(
          height: coverSize + 56,
          child: previewsAsync.when(
            data: (previews) {
              if (previews.isEmpty) {
                return _EmptyHero(
                  coverSize: coverSize,
                  message: 'No cratelists yet',
                  actionLabel: 'Create one',
                  onAction: () => context.push('/library/cratelists'),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.lg),
                itemCount: previews.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: Spacing.md),
                itemBuilder: (context, index) {
                  return _CratelistTile(
                    preview: previews[index],
                    coverSize: coverSize,
                  );
                },
              );
            },
            loading: () => _LoadingRow(coverSize: coverSize),
            error: (_, __) => _ErrorRow(
              coverSize: coverSize,
              message: 'Failed to load cratelists',
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recommended albums (server-scored)
// ---------------------------------------------------------------------------

class _RecommendedAlbumsSection extends ConsumerWidget {
  const _RecommendedAlbumsSection({
    required this.coverSize,
    required this.limit,
  });

  final double coverSize;
  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recsAsync = ref.watch(serverRecommendationsProvider(limit));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Recommended Albums'),
        HomeScreen.sectionGap(),
        SizedBox(
          height: coverSize + 56,
          child: recsAsync.when(
            data: (recs) {
              if (recs.isEmpty) {
                return _EmptyHero(
                  coverSize: coverSize,
                  message: 'Play a few records and we\'ll start '
                      'recommending more.',
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: Spacing.lg),
                itemCount: recs.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: Spacing.md),
                itemBuilder: (context, index) {
                  return _RecommendationTile(
                    recommendation: recs[index],
                    coverSize: coverSize,
                  );
                },
              );
            },
            loading: () => _LoadingRow(coverSize: coverSize),
            error: (_, __) => _ErrorRow(
              coverSize: coverSize,
              message: 'Failed to load recommendations',
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Recommended cratelists (coming soon stub)
// ---------------------------------------------------------------------------

class _RecommendedCratelistsStub extends StatelessWidget {
  const _RecommendedCratelistsStub({required this.coverSize});

  final double coverSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(title: 'Recommended Cratelists'),
        HomeScreen.sectionGap(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Container(
            height: coverSize,
            decoration: BoxDecoration(
              borderRadius: AppRadius.largeRadius,
              color: SaturdayColors.secondary.withValues(alpha: 0.15),
              border: Border.all(
                color: SaturdayColors.secondary.withValues(alpha: 0.3),
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: SaturdayColors.secondary,
                  ),
                  const SizedBox(height: Spacing.sm),
                  Text(
                    'Coming soon',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: SaturdayColors.secondary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tiles
// ---------------------------------------------------------------------------

class _AlbumCoverTile extends ConsumerWidget {
  const _AlbumCoverTile({
    required this.libraryAlbum,
    required this.coverSize,
  });

  final LibraryAlbum libraryAlbum;
  final double coverSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = libraryAlbum.album;
    final title = album?.title ?? 'Unknown';
    final artist = album?.artist ?? '';
    final coverUrl = album?.coverImageUrl;

    return SizedBox(
      width: coverSize,
      child: GestureDetector(
        onTap: () => context.push('/library/album/${libraryAlbum.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverArt(coverUrl: coverUrl, size: coverSize),
            const SizedBox(height: Spacing.sm),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (artist.isNotEmpty)
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
    );
  }
}

class _RecommendationTile extends StatelessWidget {
  const _RecommendationTile({
    required this.recommendation,
    required this.coverSize,
  });

  final AlbumRecommendation recommendation;
  final double coverSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: coverSize,
      child: GestureDetector(
        onTap: () => context.push(
          '/library/album/${recommendation.libraryAlbumId}',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoverArt(
              coverUrl: recommendation.coverImageUrl,
              size: coverSize,
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              recommendation.title,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              recommendation.artist,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _CratelistTile extends StatelessWidget {
  const _CratelistTile({required this.preview, required this.coverSize});

  final CratelistPreview preview;
  final double coverSize;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: coverSize,
      child: GestureDetector(
        onTap: () =>
            context.push('/library/cratelists/${preview.cratelist.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: coverSize,
              height: coverSize,
              child: CratelistCover(coverUrls: preview.coverUrls),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              preview.cratelist.name,
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _countLabel(preview.itemCount),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _countLabel(int count) {
    if (count == 0) return 'Empty';
    if (count == 1) return '1 album';
    return '$count albums';
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.coverUrl, required this.size});

  final String? coverUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.card,
        color: SaturdayColors.secondary.withValues(alpha: 0.2),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.largeRadius,
        child: coverUrl != null && coverUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: coverUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => _placeholder(),
                errorWidget: (_, __, ___) => _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.album_outlined,
          size: 40,
          color: SaturdayColors.secondary,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / loading / error placeholders
// ---------------------------------------------------------------------------

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({
    required this.coverSize,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final double coverSize;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Container(
        height: coverSize,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: AppRadius.largeRadius,
          color: SaturdayColors.secondary.withValues(alpha: 0.12),
        ),
        padding: const EdgeInsets.all(Spacing.lg),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: SaturdayColors.secondary,
                    ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: Spacing.sm),
                TextButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  const _LoadingRow({required this.coverSize});

  final double coverSize;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(width: Spacing.md),
      itemBuilder: (_, __) {
        return Container(
          width: coverSize,
          height: coverSize,
          decoration: BoxDecoration(
            borderRadius: AppRadius.largeRadius,
            color: SaturdayColors.secondary.withValues(alpha: 0.12),
          ),
        );
      },
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.coverSize, required this.message});

  final double coverSize;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
      child: Container(
        height: coverSize,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: AppRadius.largeRadius,
          color: SaturdayColors.error.withValues(alpha: 0.08),
        ),
        child: Center(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.error,
                ),
          ),
        ),
      ),
    );
  }
}

