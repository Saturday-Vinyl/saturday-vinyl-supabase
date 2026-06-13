import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:saturday_consumer_app/config/routes.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/album.dart';
import 'package:saturday_consumer_app/models/album_colors.dart';
import 'package:saturday_consumer_app/models/library_album.dart';
import 'package:saturday_consumer_app/models/playback_queue_item.dart';
import 'package:saturday_consumer_app/models/track.dart';
import 'package:saturday_consumer_app/providers/app_lifecycle_provider.dart';
import 'package:saturday_consumer_app/providers/current_track_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/playback_queue_provider.dart';
import 'package:saturday_consumer_app/providers/playback_sync_provider.dart';
import 'package:saturday_consumer_app/providers/realtime_now_playing_provider.dart';
import 'package:saturday_consumer_app/providers/track_timing_provider.dart';
import 'package:saturday_consumer_app/utils/track_position_calculator.dart';
import 'package:saturday_consumer_app/widgets/common/saturday_app_bar.dart';

/// The listening room — the app's home tab.
///
/// Per the constitution this is the one surface where album-derived
/// atmospheric color belongs (on the page background only, never on
/// chrome). The room is anchored on the stand: what record is on it,
/// what's after, and one optional invitation slot. No recommendation
/// feeds, no history scrolls, no queue UI.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep background plumbing alive while the room is foreground.
    ref.watch(realtimeNowPlayingProvider);
    ref.watch(playbackSyncProvider);
    ref.watch(appLifecycleProvider);
    ref.watch(queueAutoAdvanceProvider);

    final nowPlaying = ref.watch(nowPlayingProvider);
    final colors = SaturdayColorTokens.of(context);
    final atmosphere = _atmosphericColor(nowPlaying.currentAlbum?.album);

    return Scaffold(
      backgroundColor: colors.paper,
      appBar: const SaturdayAppBar(
        title: 'Listening room',
        showSearch: true,
      ),
      body: SafeArea(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 1200),
          curve: const Cubic(0.45, 0, 0.55, 1), // ease-blend
          decoration: BoxDecoration(
            gradient: atmosphere != null
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.5, 1.0],
                    colors: [
                      atmosphere.withValues(alpha: 0.10),
                      atmosphere.withValues(alpha: 0.04),
                      colors.paper,
                    ],
                  )
                : null,
          ),
          child: nowPlaying.currentAlbum == null
              ? _EmptyStand(colors: colors)
              : _OnTheStand(state: nowPlaying, colors: colors),
        ),
      ),
    );
  }

  /// Picks the album-derived color that drives the room's atmospheric wash.
  ///
  /// Per the foundations, atmospheric color is light, not assertive. We
  /// reach first for the muted/dominant tones; vibrant is a fallback. Text
  /// and chrome never sit on top of this color — only the page background.
  Color? _atmosphericColor(Album? album) {
    final palette = album?.colors;
    if (palette == null) return null;
    return AlbumColors.parseHex(palette.muted) ??
        AlbumColors.parseHex(palette.dominant) ??
        AlbumColors.parseHex(palette.vibrant);
  }
}

// =============================================================================
// On the stand
// =============================================================================

class _OnTheStand extends ConsumerWidget {
  const _OnTheStand({required this.state, required this.colors});

  final NowPlayingState state;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryAlbum = state.currentAlbum!;
    final album = libraryAlbum.album;
    final queue = ref.watch(playbackQueueProvider).items;
    final timing = ref.watch(trackTimingProvider);
    final timingIsActive = timing.isActive;

    final showStartTiming = !timingIsActive &&
        state.isPlaying &&
        state.currentSideHasMissingDurations &&
        state.currentSideTracks.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        SaturdaySpace.space4,
        SaturdaySpace.space4,
        SaturdaySpace.space4,
        SaturdaySpace.space16,
      ),
      children: [
        _SectionEyebrow(label: 'The stand', colors: colors),
        const SizedBox(height: SaturdaySpace.space6),
        _StandCover(album: album, colors: colors),
        const SizedBox(height: SaturdaySpace.space8),
        _StandHeader(album: album, colors: colors),
        const SizedBox(height: SaturdaySpace.space3),
        _SideSection(state: state, colors: colors),
        if (showStartTiming) ...[
          const SizedBox(height: SaturdaySpace.space4),
          _StartTimingAffordance(state: state, colors: colors),
        ],
        const SizedBox(height: SaturdaySpace.space8),
        if (timingIsActive)
          _TimingSurface(state: timing, colors: colors)
        else ...[
          _PrimaryAction(state: state, colors: colors),
          const SizedBox(height: SaturdaySpace.space8),
          _WitnessLine(libraryAlbum: libraryAlbum, colors: colors),
          if (queue.isNotEmpty) ...[
            const SizedBox(height: SaturdaySpace.space12),
            _SectionEyebrow(label: 'After this', colors: colors),
            const SizedBox(height: SaturdaySpace.space4),
            _AfterThis(items: queue, colors: colors),
          ],
          const SizedBox(height: SaturdaySpace.space8),
          _DismissAction(colors: colors),
        ],
      ],
    );
  }
}

class _StandCover extends StatelessWidget {
  const _StandCover({required this.album, required this.colors});

  final Album? album;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final coverUrl = album?.coverImageUrl;
    final size = MediaQuery.of(context).size.width * 0.78;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: size),
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.paperElevated,
              border: Border.all(color: colors.borderQuiet),
              borderRadius: BorderRadius.circular(2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: coverUrl != null
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _CoverFallback(colors: colors),
                      errorWidget: (_, __, ___) =>
                          _CoverFallback(colors: colors),
                    )
                  : _CoverFallback(colors: colors),
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.colors});

  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.paperElevated,
      alignment: Alignment.center,
      child: Icon(Icons.album_outlined, size: 64, color: colors.inkTertiary),
    );
  }
}

class _StandHeader extends StatelessWidget {
  const _StandHeader({required this.album, required this.colors});

  final Album? album;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          album?.title ?? 'Untitled record',
          style: SaturdayType.titleListening.copyWith(
            color: colors.ink,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: SaturdaySpace.space1),
        Text(
          album?.artist ?? 'Artist unknown',
          style: SaturdayType.body.copyWith(
            color: colors.inkSecondary,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

/// State-aware section under the album header:
/// - queued: side selector (one row per side; active in ink, inactive
///   underlined and tappable to switch)
/// - playing with known durations: side line with live countdown, plus a
///   tracklist that highlights the current track
/// - playing without durations: plain side line (the _StartTimingAffordance
///   above it carries the prompt to record times)
class _SideSection extends ConsumerWidget {
  const _SideSection({required this.state, required this.colors});

  final NowPlayingState state;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sides = state.availableSides;
    final hasSides = sides.isNotEmpty;

    if (!hasSides && state.currentSideDurationSeconds <= 0) {
      return const SizedBox.shrink();
    }

    if (state.isPlaying) {
      // currentTrackProvider ticks each second while playing; watching it
      // here is what drives the countdown's per-second rebuild.
      final position = ref.watch(currentTrackProvider);
      return _PlayingSection(
        state: state,
        position: position,
        colors: colors,
      );
    }

    // Queued (or idle-with-album)
    if (sides.length > 1) {
      return _QueuedSideSelector(state: state, colors: colors);
    }
    return _QueuedSingleSide(state: state, colors: colors);
  }
}

class _QueuedSingleSide extends StatelessWidget {
  const _QueuedSingleSide({required this.state, required this.colors});

  final NowPlayingState state;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (state.currentSide.isNotEmpty) parts.add('Side ${state.currentSide}');
    if (state.currentSideDurationSeconds > 0) {
      parts.add(_formatMmSs(state.currentSideDurationSeconds));
    }
    return Text(
      parts.join('  ·  '),
      style: SaturdayType.mono.copyWith(color: colors.inkTertiary),
    );
  }
}

class _QueuedSideSelector extends ConsumerWidget {
  const _QueuedSideSelector({required this.state, required this.colors});

  final NowPlayingState state;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final side in state.availableSides)
          _SideRow(
            side: side,
            durationSeconds: state.durationForSide(side),
            isActive: side == state.currentSide,
            colors: colors,
            onTap: side == state.currentSide
                ? null
                : () => ref.read(nowPlayingProvider.notifier).setSide(side),
          ),
      ],
    );
  }
}

class _SideRow extends StatelessWidget {
  const _SideRow({
    required this.side,
    required this.durationSeconds,
    required this.isActive,
    required this.colors,
    required this.onTap,
  });

  final String side;
  final int durationSeconds;
  final bool isActive;
  final SaturdayColorTokens colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final parts = <String>['Side $side'];
    if (durationSeconds > 0) parts.add(_formatMmSs(durationSeconds));
    final text = Text(
      parts.join('  ·  '),
      style: SaturdayType.mono.copyWith(
        color: isActive ? colors.ink : colors.inkTertiary,
        decoration: isActive ? null : TextDecoration.underline,
        decorationColor: colors.borderStrong,
      ),
    );

    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SaturdaySpace.space1),
        child: text,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SaturdaySpace.space1),
        child: text,
      ),
    );
  }
}

class _PlayingSection extends StatelessWidget {
  const _PlayingSection({
    required this.state,
    required this.position,
    required this.colors,
  });

  final NowPlayingState state;
  final TrackPosition? position;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final sideDuration = state.currentSideDurationSeconds;
    final startedAt = state.startedAt;
    final hasDurations = sideDuration > 0 && startedAt != null;

    if (!hasDurations) {
      // Plain factual line; the _StartTimingAffordance above prompts to
      // record times.
      return Text(
        'Side ${state.currentSide}',
        style: SaturdayType.mono.copyWith(color: colors.inkTertiary),
      );
    }

    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    final remaining = (sideDuration - elapsed).clamp(0, sideDuration);
    final estimated = position?.isEstimated ?? false;
    final tildePrefix = estimated ? '~' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Side ${state.currentSide}  ·  $tildePrefix${_formatMmSs(remaining)}',
          style: SaturdayType.mono.copyWith(color: colors.ink),
        ),
        const SizedBox(height: SaturdaySpace.space4),
        _PlayingTrackList(
          tracks: state.currentSideTracks,
          currentIndex: position?.trackIndex,
          colors: colors,
        ),
      ],
    );
  }
}

class _PlayingTrackList extends StatelessWidget {
  const _PlayingTrackList({
    required this.tracks,
    required this.currentIndex,
    required this.colors,
  });

  final List<Track> tracks;
  final int? currentIndex;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tracks.length; i++)
          _PlayingTrackRow(
            position: tracks[i].position,
            title: tracks[i].title,
            durationSeconds: tracks[i].durationSeconds,
            isCurrent: i == currentIndex,
            colors: colors,
          ),
      ],
    );
  }
}

class _PlayingTrackRow extends StatelessWidget {
  const _PlayingTrackRow({
    required this.position,
    required this.title,
    required this.durationSeconds,
    required this.isCurrent,
    required this.colors,
  });

  final String position;
  final String title;
  final int? durationSeconds;
  final bool isCurrent;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SaturdaySpace.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              position,
              style: SaturdayType.mono.copyWith(color: colors.inkTertiary),
            ),
          ),
          const SizedBox(width: SaturdaySpace.space3),
          Expanded(
            child: Text(
              title,
              style: SaturdayType.body.copyWith(
                color: isCurrent ? colors.ink : colors.inkSecondary,
                fontWeight:
                    isCurrent ? SaturdayType.medium : SaturdayType.regular,
              ),
            ),
          ),
          const SizedBox(width: SaturdaySpace.space3),
          Text(
            durationSeconds == null ? '—' : _formatMmSs(durationSeconds!),
            style: SaturdayType.mono.copyWith(color: colors.inkTertiary),
          ),
        ],
      ),
    );
  }
}

String _formatMmSs(int seconds) {
  final mins = seconds ~/ 60;
  final secs = seconds % 60;
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

class _PrimaryAction extends ConsumerWidget {
  const _PrimaryAction({required this.state, required this.colors});

  final NowPlayingState state;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = state.isPlaying;

    return _RoomButton(
      label: isPlaying ? 'Stop the record' : 'Drop the needle',
      isPrimary: !isPlaying,
      colors: colors,
      onTap: () async {
        if (isPlaying) {
          // Stop, but keep the record on the stand — the listener can
          // drop the needle again or clear the stand explicitly.
          await ref.read(nowPlayingProvider.notifier).stopPlaying();
        } else {
          await ref.read(nowPlayingProvider.notifier).startPlaying();
        }
      },
    );
  }
}

class _DismissAction extends ConsumerWidget {
  const _DismissAction({required this.colors});

  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(nowPlayingProvider);
    // The primary CTA is the stop control during playback; the quiet
    // "Clear the stand" affordance is only offered when the record is
    // sitting queued (whether freshly placed, paused, or between sides).
    if (state.isPlaying) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () =>
            ref.read(nowPlayingProvider.notifier).clearNowPlaying(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SaturdaySpace.space2),
          child: Text(
            'Clear the stand',
            style: SaturdayType.bodySmall.copyWith(
              color: colors.inkSecondary,
              decoration: TextDecoration.underline,
              decorationColor: colors.borderStrong,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomButton extends StatelessWidget {
  const _RoomButton({
    required this.label,
    required this.isPrimary,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool isPrimary;
  final SaturdayColorTokens colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: isPrimary ? colors.ink : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: BorderSide(
            color: isPrimary ? colors.ink : colors.borderStrong,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(2),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SaturdaySpace.space4,
              vertical: SaturdaySpace.space3,
            ),
            child: Center(
              child: Text(
                label,
                style: SaturdayType.body.copyWith(
                  color: isPrimary ? colors.paper : colors.ink,
                  fontWeight: SaturdayType.medium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Witness (stubbed until the witness data model lands)
// =============================================================================

class _WitnessLine extends StatelessWidget {
  const _WitnessLine({required this.libraryAlbum, required this.colors});

  final LibraryAlbum libraryAlbum;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    // Stub. Real witness entries will come from system observations
    // (placements, plays, acquisitions) interleaved with listener notes,
    // in the witness register described in the constitution.
    final stub = _stubWitness(libraryAlbum);

    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: SaturdaySpace.space2),
      child: Text(
        stub,
        style: SaturdayType.bodySerif.copyWith(
          color: colors.inkSecondary,
          fontStyle: FontStyle.italic,
          fontSize: 16,
        ),
      ),
    );
  }

  String _stubWitness(LibraryAlbum libraryAlbum) {
    final acquired = libraryAlbum.addedAt;
    final years = DateTime.now().year - acquired.year;
    if (years >= 1) {
      return 'On the shelf since ${acquired.year}.';
    }
    return 'A recent arrival.';
  }
}

// =============================================================================
// After this — the session
// =============================================================================

class _AfterThis extends StatelessWidget {
  const _AfterThis({required this.items, required this.colors});

  final List<PlaybackQueueItem> items;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          _SessionRow(
            item: items[i],
            isLast: i == items.length - 1,
            colors: colors,
          ),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.item,
    required this.isLast,
    required this.colors,
  });

  final PlaybackQueueItem item;
  final bool isLast;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final album = item.libraryAlbum?.album;
    final coverUrl = album?.coverImageUrl;
    final title = album?.title ?? 'Untitled record';
    final artist = album?.artist ?? 'Artist unknown';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          context.push('/library/album/${item.libraryAlbumId}'),
      child: Padding(
        padding: EdgeInsets.only(
          top: SaturdaySpace.space3,
          bottom: isLast ? 0 : SaturdaySpace.space3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.paperElevated,
                  border: Border.all(color: colors.borderQuiet),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: colors.paperElevated,
                          ),
                          errorWidget: (_, __, ___) => Icon(
                            Icons.album_outlined,
                            size: 24,
                            color: colors.inkTertiary,
                          ),
                        )
                      : Icon(
                          Icons.album_outlined,
                          size: 24,
                          color: colors.inkTertiary,
                        ),
                ),
              ),
            ),
            const SizedBox(width: SaturdaySpace.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: SaturdayType.body.copyWith(
                      color: colors.ink,
                      fontStyle: FontStyle.italic,
                      fontFamily: SaturdayType.fontSerif,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    style: SaturdayType.meta.copyWith(
                      color: colors.inkTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Empty stand
// =============================================================================

class _EmptyStand extends ConsumerWidget {
  const _EmptyStand({required this.colors});

  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentlyPlayedProvider);
    final lastOnStand = recent.maybeWhen(
      data: (albums) => albums.isNotEmpty ? albums.first : null,
      orElse: () => null,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SaturdaySpace.space4,
        SaturdaySpace.space4,
        SaturdaySpace.space4,
        SaturdaySpace.space16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionEyebrow(label: 'The stand', colors: colors),
          const SizedBox(height: SaturdaySpace.space16),
          Text(
            'The stand is empty.',
            style: SaturdayType.titleListening.copyWith(
              color: colors.ink,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: SaturdaySpace.space6),
          GestureDetector(
            onTap: () => context.go(RoutePaths.library),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: SaturdaySpace.space2),
              child: Text(
                'Choose a record',
                style: SaturdayType.body.copyWith(
                  color: colors.ink,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.borderStrong,
                ),
              ),
            ),
          ),
          if (lastOnStand != null) ...[
            const SizedBox(height: SaturdaySpace.space12),
            _LastOnStand(libraryAlbum: lastOnStand, colors: colors),
          ],
        ],
      ),
    );
  }
}

class _LastOnStand extends StatelessWidget {
  const _LastOnStand({required this.libraryAlbum, required this.colors});

  final LibraryAlbum libraryAlbum;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final album = libraryAlbum.album;
    final title = album?.title ?? 'Untitled record';

    return GestureDetector(
      onTap: () =>
          context.push('/library/album/${libraryAlbum.id}'),
      child: RichText(
        text: TextSpan(
          style: SaturdayType.bodySerif.copyWith(
            color: colors.inkSecondary,
            fontSize: 16,
          ),
          children: [
            const TextSpan(text: 'Last on the stand: '),
            TextSpan(
              text: title,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: colors.ink,
              ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Track timing — inline affordance + surface
// =============================================================================

class _StartTimingAffordance extends ConsumerWidget {
  const _StartTimingAffordance({required this.state, required this.colors});

  final NowPlayingState state;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SaturdaySpace.space1),
      child: RichText(
        text: TextSpan(
          style: SaturdayType.bodySerif.copyWith(
            color: colors.inkSecondary,
            fontStyle: FontStyle.italic,
            fontSize: 16,
          ),
          children: [
            const TextSpan(text: "Track times haven't been recorded. "),
            TextSpan(
              text: 'Time them',
              style: TextStyle(
                color: colors.ink,
                decoration: TextDecoration.underline,
                decorationColor: colors.borderStrong,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => ref.read(trackTimingProvider.notifier).start(
                      side: state.currentSide,
                      tracks: state.currentSideTracks,
                    ),
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}

class _TimingSurface extends ConsumerWidget {
  const _TimingSurface({required this.state, required this.colors});

  final TrackTimingState state;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isReviewing || state.isSaving) {
      return _TimingReview(state: state, colors: colors);
    }
    return _TimingActive(state: state, colors: colors);
  }
}

class _TimingActive extends ConsumerWidget {
  const _TimingActive({required this.state, required this.colors});

  final TrackTimingState state;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionEyebrow(
          label: 'Timing side ${state.side}',
          colors: colors,
        ),
        const SizedBox(height: SaturdaySpace.space3),
        Text(
          state.formattedElapsed,
          style: SaturdayType.mono.copyWith(
            color: colors.ink,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: SaturdaySpace.space6),
        Column(
          children: [
            for (var i = 0; i < state.tracks.length; i++)
              _TimingRow(
                index: i,
                position: state.tracks[i].position,
                title: state.tracks[i].title,
                currentIndex: state.currentTrackIndex,
                recordedSeconds: i < state.recordedDurations.length
                    ? state.recordedDurations[i].durationSeconds
                    : null,
                colors: colors,
              ),
          ],
        ),
        const SizedBox(height: SaturdaySpace.space6),
        _RoomButton(
          label: state.isLastTrack ? 'Last track ends now' : 'This track ends now',
          isPrimary: true,
          colors: colors,
          onTap: () {
            HapticFeedback.mediumImpact();
            ref.read(trackTimingProvider.notifier).nextTrack();
          },
        ),
        const SizedBox(height: SaturdaySpace.space2),
        Align(
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => ref.read(trackTimingProvider.notifier).cancel(),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: SaturdaySpace.space2),
              child: Text(
                'Stop timing',
                style: SaturdayType.bodySmall.copyWith(
                  color: colors.inkSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.borderStrong,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({
    required this.index,
    required this.position,
    required this.title,
    required this.currentIndex,
    required this.recordedSeconds,
    required this.colors,
  });

  final int index;
  final String position;
  final String title;
  final int currentIndex;
  final int? recordedSeconds;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final isCompleted = recordedSeconds != null;
    final isCurrent = index == currentIndex;

    final Color titleColor;
    if (isCurrent) {
      titleColor = colors.ink;
    } else if (isCompleted) {
      titleColor = colors.inkSecondary;
    } else {
      titleColor = colors.inkTertiary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SaturdaySpace.space2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              position,
              style: SaturdayType.mono.copyWith(color: colors.inkTertiary),
            ),
          ),
          const SizedBox(width: SaturdaySpace.space3),
          Expanded(
            child: Text(
              title,
              style: SaturdayType.body.copyWith(
                color: titleColor,
                fontWeight: isCurrent ? SaturdayType.medium : SaturdayType.regular,
              ),
            ),
          ),
          const SizedBox(width: SaturdaySpace.space3),
          Text(
            isCompleted ? _formatDuration(recordedSeconds!) : '—',
            style: SaturdayType.mono.copyWith(
              color: isCompleted ? colors.inkSecondary : colors.inkTertiary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

class _TimingReview extends ConsumerWidget {
  const _TimingReview({required this.state, required this.colors});

  final TrackTimingState state;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionEyebrow(
          label: 'Side ${state.side} recorded',
          colors: colors,
        ),
        const SizedBox(height: SaturdaySpace.space4),
        for (var i = 0; i < state.tracks.length; i++)
          _ReviewRow(
            position: state.tracks[i].position,
            title: state.tracks[i].title,
            seconds: i < state.recordedDurations.length
                ? state.recordedDurations[i].durationSeconds
                : null,
            colors: colors,
          ),
        if (state.error != null) ...[
          const SizedBox(height: SaturdaySpace.space3),
          Text(
            state.error!,
            style: SaturdayType.bodySmall.copyWith(color: colors.inkSecondary),
          ),
        ],
        const SizedBox(height: SaturdaySpace.space6),
        _RoomButton(
          label: state.isSaving ? 'Saving' : 'Save',
          isPrimary: true,
          colors: colors,
          onTap: state.isSaving
              ? () {}
              : () => ref.read(trackTimingProvider.notifier).save(),
        ),
        const SizedBox(height: SaturdaySpace.space2),
        Align(
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: state.isSaving
                ? null
                : () => ref.read(trackTimingProvider.notifier).redo(),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: SaturdaySpace.space2),
              child: Text(
                'Time again',
                style: SaturdayType.bodySmall.copyWith(
                  color: colors.inkSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: colors.borderStrong,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.position,
    required this.title,
    required this.seconds,
    required this.colors,
  });

  final String position;
  final String title;
  final int? seconds;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SaturdaySpace.space2),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              position,
              style: SaturdayType.mono.copyWith(color: colors.inkTertiary),
            ),
          ),
          const SizedBox(width: SaturdaySpace.space3),
          Expanded(
            child: Text(
              title,
              style: SaturdayType.body.copyWith(color: colors.ink),
            ),
          ),
          const SizedBox(width: SaturdaySpace.space3),
          Text(
            seconds == null ? '—' : _format(seconds!),
            style: SaturdayType.mono.copyWith(color: colors.ink),
          ),
        ],
      ),
    );
  }

  String _format(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }
}

// =============================================================================
// Section eyebrow
// =============================================================================

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.label, required this.colors});

  final String label;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: SaturdayType.eyebrow.copyWith(color: colors.inkSecondary),
    );
  }
}
