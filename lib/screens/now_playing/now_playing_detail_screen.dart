import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/album_colors.dart';
import 'package:saturday_consumer_app/providers/album_provider.dart';
import 'package:saturday_consumer_app/providers/current_track_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/track_timing_provider.dart';
import 'package:saturday_consumer_app/widgets/now_playing/album_art_hero.dart';
import 'package:saturday_consumer_app/widgets/now_playing/auto_detected_badge.dart';
import 'package:saturday_consumer_app/widgets/now_playing/current_track_card.dart';
import 'package:saturday_consumer_app/widgets/now_playing/flip_timer.dart';
import 'package:saturday_consumer_app/widgets/now_playing/now_playing_info.dart';
import 'package:saturday_consumer_app/widgets/now_playing/now_playing_track_list.dart';
import 'package:saturday_consumer_app/widgets/now_playing/side_selector.dart';
import 'package:saturday_consumer_app/widgets/now_playing/track_timing_banner.dart';
import 'package:saturday_consumer_app/widgets/now_playing/track_timing_session.dart';

/// Fullscreen Now Playing detail screen.
///
/// Reached from the home screen's mini bar. Renders the currently
/// playing or queued album over a gradient derived from the album
/// cover's color palette.
class NowPlayingDetailScreen extends ConsumerStatefulWidget {
  const NowPlayingDetailScreen({super.key});

  @override
  ConsumerState<NowPlayingDetailScreen> createState() =>
      _NowPlayingDetailScreenState();
}

class _NowPlayingDetailScreenState
    extends ConsumerState<NowPlayingDetailScreen> {
  // 0..1 opacity of the AppBar tint, derived from scroll position. Stays at 0
  // while the gradient is fully visible at the top, ramps up as the user
  // scrolls so the close button + title remain readable over the artwork.
  double _appBarOpacity = 0;

  static const double _scrollFadeDistance = 80;
  static const double _maxAppBarOpacity = 0.92;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final next =
        (n.metrics.pixels / _scrollFadeDistance).clamp(0.0, _maxAppBarOpacity);
    if ((next - _appBarOpacity).abs() > 0.01) {
      setState(() => _appBarOpacity = next);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nowPlayingProvider);
    final album = state.currentAlbum?.album;

    if (album != null && album.colors == null) {
      ref.watch(albumColorsBackfillProvider(album.id));
    }

    final palette = album?.colors;
    final base = AlbumColors.parseHex(palette?.darkVibrant) ??
        AlbumColors.parseHex(palette?.darkMuted) ??
        AlbumColors.parseHex(palette?.dominant) ??
        SaturdayColors.primaryDark;
    final onBase = base.computeLuminance() > 0.45
        ? SaturdayColors.black
        : Colors.white;

    // showModalBottomSheet wraps its child in MediaQuery.removePadding(
    // removeTop: true), which zeroes out BOTH padding.top and viewPadding.top
    // for everything underneath. Read the inset straight from the FlutterView
    // so we always get the device's actual status-bar height regardless of
    // what ancestor MediaQuery widgets have done.
    final statusBarInset = MediaQueryData.fromView(View.of(context)).padding.top;
    const barHeight = kToolbarHeight;
    final bodyTopPadding = statusBarInset + barHeight + Spacing.md;

    return Scaffold(
      backgroundColor: base,
      body: Stack(
        children: [
          // Gradient + scrolling content fill the screen edge-to-edge.
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.55, 1.0],
                    colors: [
                      base,
                      Color.lerp(base, SaturdayColors.light, 0.55)!,
                      SaturdayColors.light,
                    ],
                  ),
                ),
                child: state.isPlaying
                    ? _PlayingBody(
                        state: state,
                        foreground: onBase,
                        topPadding: bodyTopPadding,
                      )
                    : state.isQueued
                        ? _QueuedBody(
                            state: state,
                            foreground: onBase,
                            topPadding: bodyTopPadding,
                          )
                        : _IdleBody(
                            foreground: onBase,
                            topPadding: bodyTopPadding,
                          ),
              ),
            ),
          ),

          // Floating top bar — manually offset by the status bar inset so
          // the chevron and labels always sit below the system status bar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: base.withValues(alpha: _appBarOpacity),
              padding: EdgeInsets.only(top: statusBarInset),
              child: SizedBox(
                height: barHeight,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 32,
                          color: onBase,
                        ),
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 64,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              state.isQueued ? 'QUEUED' : 'NOW PLAYING',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: onBase.withValues(alpha: 0.7),
                                    letterSpacing: 1.2,
                                  ),
                            ),
                            if (album?.title != null)
                              Text(
                                album!.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      color: onBase,
                                      fontWeight: FontWeight.w600,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playing
// ---------------------------------------------------------------------------

class _PlayingBody extends ConsumerWidget {
  const _PlayingBody({
    required this.state,
    required this.foreground,
    required this.topPadding,
  });

  final NowPlayingState state;
  final Color foreground;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = state.currentAlbum!.album;
    final hasSides = state.hasSides;
    final timingState = ref.watch(trackTimingProvider);
    final isTimingActive = timingState.isActive;
    final hasMissingDurations = state.currentSideHasMissingDurations;
    final currentTrack = ref.watch(currentTrackProvider);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        topPadding,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            child: AlbumArtHero(album: album, onTap: () {}),
          ),

          Spacing.sectionGap,

          if (state.isAutoDetected && state.detectedByDevice != null) ...[
            AutoDetectedBadge(deviceName: state.detectedByDevice!),
            const SizedBox(height: Spacing.md),
          ],

          if (album != null) NowPlayingInfo(album: album),

          const SizedBox(height: Spacing.lg),

          if (hasSides) ...[
            SideSelector(
              currentSide: state.currentSide,
              availableSides: state.availableSides,
              sideDurations: state.sideDurations,
              onSideChanged: (side) {
                ref.read(nowPlayingProvider.notifier).setSide(side);
              },
            ),
            const SizedBox(height: Spacing.lg),
          ],

          if (isTimingActive)
            const TrackTimingSession()
          else if (state.startedAt != null &&
              state.currentSideDurationSeconds > 0)
            FlipTimer(
              startedAt: state.startedAt!,
              totalDurationSeconds: state.currentSideDurationSeconds,
            )
          else if (hasMissingDurations && state.currentSideTracks.isNotEmpty)
            TrackTimingBanner(
              onStart: () {
                ref.read(trackTimingProvider.notifier).start(
                      side: state.currentSide,
                      tracks: state.currentSideTracks,
                    );
              },
            ),

          if (!isTimingActive && currentTrack != null) ...[
            const SizedBox(height: Spacing.md),
            CurrentTrackCard(trackPosition: currentTrack),
          ],

          Spacing.sectionGap,

          if (!isTimingActive &&
              album != null &&
              album.tracks.isNotEmpty)
            NowPlayingTrackList(
              tracksBySide: {
                for (final side in state.availableSides)
                  side: state.tracksForSide(side),
              },
              currentSide: state.currentSide,
              currentTrackIndex: currentTrack?.trackIndex,
              initiallyExpanded: false,
            ),

          Spacing.sectionGap,

          TextButton.icon(
            onPressed: () {
              ref.read(nowPlayingProvider.notifier).clearNowPlaying();
              Navigator.of(context).maybePop();
            },
            style: TextButton.styleFrom(foregroundColor: foreground),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop Playing'),
          ),

          const SizedBox(height: Spacing.xxl),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Queued
// ---------------------------------------------------------------------------

class _QueuedBody extends ConsumerWidget {
  const _QueuedBody({
    required this.state,
    required this.foreground,
    required this.topPadding,
  });

  final NowPlayingState state;
  final Color foreground;
  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = state.currentAlbum!.album;
    final hasSides = state.hasSides;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        topPadding,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            child: AlbumArtHero(album: album, onTap: () {}),
          ),

          Spacing.sectionGap,

          if (state.isAutoDetected && state.detectedByDevice != null) ...[
            AutoDetectedBadge(deviceName: state.detectedByDevice!),
            const SizedBox(height: Spacing.md),
          ],

          if (album != null) NowPlayingInfo(album: album),

          const SizedBox(height: Spacing.lg),

          if (hasSides) ...[
            SideSelector(
              currentSide: state.currentSide,
              availableSides: state.availableSides,
              sideDurations: state.sideDurations,
              onSideChanged: (side) {
                ref.read(nowPlayingProvider.notifier).setSide(side);
              },
            ),
            const SizedBox(height: Spacing.lg),
          ],

          Spacing.sectionGap,

          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: () {
                ref.read(nowPlayingProvider.notifier).startPlaying();
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Playing'),
            ),
          ),

          const SizedBox(height: Spacing.md),

          TextButton(
            onPressed: () {
              ref.read(nowPlayingProvider.notifier).clearNowPlaying();
              Navigator.of(context).maybePop();
            },
            style: TextButton.styleFrom(foregroundColor: foreground),
            child: const Text('Dismiss'),
          ),

          const SizedBox(height: Spacing.xxl),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Idle (rare — opened with no active session)
// ---------------------------------------------------------------------------

class _IdleBody extends StatelessWidget {
  const _IdleBody({required this.foreground, required this.topPadding});

  final Color foreground;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        topPadding,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.album_outlined,
              size: 64,
              color: foreground.withValues(alpha: 0.6),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              'Nothing playing',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                  ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Pick an album to get started.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
