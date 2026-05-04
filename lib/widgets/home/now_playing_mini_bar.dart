import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/album_colors.dart';
import 'package:saturday_consumer_app/providers/current_track_provider.dart';
import 'package:saturday_consumer_app/providers/now_playing_provider.dart';
import 'package:saturday_consumer_app/screens/now_playing/now_playing_detail_screen.dart';

/// Compact "now playing" pill anchored above the home screen's bottom nav.
///
/// Renders only when an album is queued or playing. Tapping opens the
/// fullscreen Now Playing detail screen as an upward-sliding drawer.
class NowPlayingMiniBar extends ConsumerStatefulWidget {
  const NowPlayingMiniBar({super.key});

  @override
  ConsumerState<NowPlayingMiniBar> createState() => _NowPlayingMiniBarState();
}

class _NowPlayingMiniBarState extends ConsumerState<NowPlayingMiniBar>
    with WidgetsBindingObserver {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      // Override the global BottomSheetThemeData which adds rounded corners,
      // a drag handle, and elevation that don't fit a fullscreen player.
      shape: const RoundedRectangleBorder(),
      showDragHandle: false,
      elevation: 0,
      constraints: const BoxConstraints.expand(),
      builder: (_) => const NowPlayingDetailScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nowPlayingProvider);
    if (!state.isActive) return const SizedBox.shrink();

    final libraryAlbum = state.currentAlbum;
    final album = libraryAlbum?.album;
    if (album == null) return const SizedBox.shrink();

    final currentTrack = ref.watch(currentTrackProvider);
    final trackTitle = currentTrack?.track.title;
    final primaryLine = trackTitle ?? album.title;
    final secondaryParts = <String>[
      if (trackTitle != null) album.title else album.artist,
      ..._timingParts(state),
    ];
    final secondaryLine = secondaryParts.join(' · ');

    final palette = album.colors;
    final base = AlbumColors.parseHex(palette?.darkVibrant) ??
        AlbumColors.parseHex(palette?.darkMuted) ??
        AlbumColors.parseHex(palette?.dominant) ??
        SaturdayColors.primaryDark;
    final fg =
        base.computeLuminance() > 0.45 ? SaturdayColors.black : Colors.white;
    final fgMuted = fg.withValues(alpha: 0.75);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.lg,
        vertical: Spacing.sm,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.largeRadius,
          onTap: () => _open(context),
          child: Ink(
            decoration: BoxDecoration(
              color: base,
              borderRadius: AppRadius.largeRadius,
              boxShadow: AppShadows.elevated,
            ),
            child: Padding(
              padding: const EdgeInsets.all(Spacing.sm),
              child: Row(
                children: [
                  _Cover(coverUrl: album.coverImageUrl),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          primaryLine,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (secondaryLine.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            secondaryLine,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: fgMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Side label + remaining time on the side, e.g. "Side A · -12:34".
  /// Falls back gracefully when the duration is unknown or the session is
  /// queued (no startedAt yet).
  List<String> _timingParts(NowPlayingState state) {
    final parts = <String>[];
    if (state.hasSides) {
      parts.add('Side ${state.currentSide}');
    }
    final total = state.currentSideDurationSeconds;
    final startedAt = state.startedAt;
    if (state.isPlaying && startedAt != null && total > 0) {
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
      final remaining = total - elapsed;
      if (remaining >= 0) {
        parts.add('-${_format(remaining)} left');
      } else {
        parts.add('+${_format(-remaining)} over');
      }
    }
    return parts;
  }

  String _format(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.mediumRadius,
      child: SizedBox(
        width: 56,
        height: 56,
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
      color: SaturdayColors.secondary.withValues(alpha: 0.3),
      child: Icon(
        Icons.album_outlined,
        color: SaturdayColors.secondary,
      ),
    );
  }
}
