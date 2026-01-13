import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/realtime_now_playing_provider.dart';
import 'package:saturday_consumer_app/widgets/common/loading_indicator.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';
import 'package:saturday_consumer_app/widgets/now_playing/album_art_hero.dart';
import 'package:saturday_consumer_app/widgets/now_playing/auto_detected_badge.dart';
import 'package:saturday_consumer_app/widgets/now_playing/flip_timer.dart';
import 'package:saturday_consumer_app/widgets/now_playing/now_playing_empty_state.dart';
import 'package:saturday_consumer_app/widgets/now_playing/now_playing_info.dart';
import 'package:saturday_consumer_app/widgets/now_playing/now_playing_track_list.dart';
import 'package:saturday_consumer_app/widgets/now_playing/side_selector.dart';
import 'package:saturday_consumer_app/widgets/now_playing/up_next_carousel.dart';

/// Now Playing screen - shows the currently playing record.
///
/// This is the primary entry point for the app, displaying:
/// - Album art with hero display
/// - Album metadata (title, artist, year)
/// - Side selector (A/B) with flip timer
/// - Track listing with current side highlighted
/// - What's next queue with recently played albums
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nowPlayingState = ref.watch(nowPlayingProvider);
    final recentlyPlayed = ref.watch(recentlyPlayedProvider);

    // Initialize the realtime now playing subscription
    // This ensures we listen for hub detections when the screen is visible
    ref.watch(realtimeNowPlayingProvider);

    return Scaffold(
      appBar: const SaturdayAppBar(
        showLibrarySwitcher: true,
        showSearch: true,
      ),
      body: SafeArea(
        child: nowPlayingState.isPlaying
            ? _buildNowPlayingContent(context, ref, nowPlayingState)
            : _buildEmptyState(context, recentlyPlayed),
      ),
    );
  }

  Widget _buildNowPlayingContent(
    BuildContext context,
    WidgetRef ref,
    NowPlayingState state,
  ) {
    final album = state.currentAlbum!.album;
    final hasSides = state.hasSides;

    return SingleChildScrollView(
      padding: Spacing.pagePadding,
      child: Column(
        children: [
          // Album art hero
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            child: AlbumArtHero(
              album: album,
              onTap: () {
                // TODO: Open full-screen album art view
              },
            ),
          ),

          Spacing.sectionGap,

          // Auto-detected badge (if detected by hub)
          if (state.isAutoDetected && state.detectedByDevice != null) ...[
            AutoDetectedBadge(deviceName: state.detectedByDevice!),
            const SizedBox(height: Spacing.md),
          ],

          // Album info
          if (album != null) NowPlayingInfo(album: album),

          const SizedBox(height: Spacing.lg),

          // Side selector (only if album has sides)
          if (hasSides) ...[
            SideSelector(
              currentSide: state.currentSide,
              sideADuration: state.sideADurationSeconds,
              sideBDuration: state.sideBDurationSeconds,
              onSideChanged: (side) {
                ref.read(nowPlayingProvider.notifier).setSide(side);
              },
            ),
            const SizedBox(height: Spacing.lg),
          ],

          // Flip timer (only if we have duration info and a start time)
          if (state.startedAt != null && state.currentSideDurationSeconds > 0)
            FlipTimer(
              startedAt: state.startedAt!,
              totalDurationSeconds: state.currentSideDurationSeconds,
            ),

          Spacing.sectionGap,

          // Track list
          if (album != null && album.tracks.isNotEmpty)
            NowPlayingTrackList(
              sideATracks: state.sideATracks,
              sideBTracks: state.sideBTracks,
              currentSide: state.currentSide,
              initiallyExpanded: false,
            ),

          Spacing.sectionGap,

          // Stop button
          TextButton.icon(
            onPressed: () {
              ref.read(nowPlayingProvider.notifier).clearNowPlaying();
            },
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop Playing'),
          ),

          Spacing.sectionGap,

          // Up Next carousel (recommendations + recently played)
          const UpNextCarousel(),

          const SizedBox(height: Spacing.xxl),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    AsyncValue<List<LibraryAlbum>> recentlyPlayed,
  ) {
    return Padding(
      padding: Spacing.pagePadding,
      child: Column(
        children: [
          // Empty state with CTAs
          Expanded(
            flex: 3,
            child: NowPlayingEmptyState(
              onChooseAlbum: () {
                context.go(RoutePaths.library);
              },
              onScanBarcode: () {
                context.push('/library/add/scan');
              },
              onPhotoOfCover: () {
                // Photo recognition coming soon - show snackbar
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Photo recognition coming soon!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ),

          Spacing.sectionGap,

          // Recently played section
          Expanded(
            flex: 2,
            child: _buildRecentlyPlayedCard(context, recentlyPlayed),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentlyPlayedCard(
    BuildContext context,
    AsyncValue<List<LibraryAlbum>> recentlyPlayed,
  ) {
    return Container(
      decoration: AppDecorations.card,
      padding: Spacing.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recently Played',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Spacing.md),
          Expanded(
            child: recentlyPlayed.when(
              data: (albums) {
                if (albums.isEmpty) {
                  return Center(
                    child: Text(
                      'No listening history yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: SaturdayColors.secondary,
                          ),
                    ),
                  );
                }
                return _buildRecentlyPlayedList(context, albums);
              },
              loading: () => const LoadingIndicator.small(),
              error: (error, _) => Center(
                child: Text(
                  'Failed to load history',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: SaturdayColors.error,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentlyPlayedList(
    BuildContext context,
    List<LibraryAlbum> albums,
  ) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final libraryAlbum = albums[index];
        return _RecentAlbumTile(libraryAlbum: libraryAlbum);
      },
    );
  }

}

/// A small tile showing a recently played album.
class _RecentAlbumTile extends ConsumerWidget {
  const _RecentAlbumTile({
    required this.libraryAlbum,
  });

  final LibraryAlbum libraryAlbum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = libraryAlbum.album;
    final title = album?.title ?? 'Unknown';
    final coverUrl = album?.coverImageUrl;

    return GestureDetector(
      onTap: () {
        ref.read(nowPlayingProvider.notifier).setNowPlaying(libraryAlbum);
      },
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: Spacing.md),
        child: Column(
          children: [
            // Album art
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: AppRadius.mediumRadius,
                boxShadow: AppShadows.card,
                color: SaturdayColors.secondary.withValues(alpha: 0.2),
              ),
              child: ClipRRect(
                borderRadius: AppRadius.mediumRadius,
                child: coverUrl != null && coverUrl.isNotEmpty
                    ? Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
            ),
            const SizedBox(height: Spacing.xs),
            // Title
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: SaturdayColors.secondary.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.album_outlined,
          size: 32,
          color: SaturdayColors.secondary,
        ),
      ),
    );
  }
}
