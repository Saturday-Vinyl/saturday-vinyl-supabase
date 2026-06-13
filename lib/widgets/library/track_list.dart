import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/track.dart';

/// Track listing rendered in archive posture.
///
/// Positions and durations are mono (factual tabular data, per the
/// constitution); titles are sans body in `ink`. When tracks carry a
/// letter-prefixed position (`A1`, `B2`, …), the list groups them under a
/// small "Side A" / "Side B" eyebrow.
class TrackList extends StatelessWidget {
  const TrackList({
    super.key,
    required this.tracks,
    this.showSideDurations = true,
  });

  final List<Track> tracks;

  /// Whether to show total duration for each side when the list is grouped.
  final bool showSideDurations;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);

    if (tracks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SaturdaySpace.space3),
        child: Text(
          "Track listing isn't recorded.",
          style: SaturdayType.body.copyWith(color: colors.inkSecondary),
        ),
      );
    }

    final sides = _groupTracksBySide(tracks);
    final sideKeys = sides.keys.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sideKeys.length; i++) ...[
          if (sideKeys[i].isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                bottom: SaturdaySpace.space2,
                top: i == 0 ? 0 : SaturdaySpace.space4,
              ),
              child: Text(
                sideKeys[i],
                style: SaturdayType.eyebrow.copyWith(
                  color: colors.inkSecondary,
                ),
              ),
            ),
          for (final track in sides[sideKeys[i]]!)
            _TrackRow(track: track, colors: colors),
          if (showSideDurations && sideKeys[i].isNotEmpty)
            _SideTotal(tracks: sides[sideKeys[i]]!, colors: colors),
        ],
      ],
    );
  }

  Map<String, List<Track>> _groupTracksBySide(List<Track> tracks) {
    final sides = <String, List<Track>>{};
    for (final track in tracks) {
      final side = _extractSide(track.position);
      sides.putIfAbsent(side, () => []).add(track);
    }

    // Single side with no letter prefix → render flat, no eyebrow.
    if (sides.length == 1 && sides.keys.first == '') {
      return {'': tracks};
    }
    return sides;
  }

  String _extractSide(String position) {
    final trimmed = position.trim().toUpperCase();
    if (trimmed.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(trimmed)) {
      return 'Side ${trimmed[0]}';
    }
    if (trimmed.contains('-')) {
      final parts = trimmed.split('-');
      if (parts.length >= 2) return 'Side ${parts[0]}';
    }
    return '';
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.colors});

  final Track track;
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
              track.position,
              style: SaturdayType.mono.copyWith(color: colors.inkTertiary),
            ),
          ),
          const SizedBox(width: SaturdaySpace.space3),
          Expanded(
            child: Text(
              track.title,
              style: SaturdayType.body.copyWith(color: colors.ink),
            ),
          ),
          const SizedBox(width: SaturdaySpace.space3),
          Text(
            track.formattedDuration,
            style: SaturdayType.mono.copyWith(color: colors.inkTertiary),
          ),
        ],
      ),
    );
  }
}

class _SideTotal extends StatelessWidget {
  const _SideTotal({required this.tracks, required this.colors});

  final List<Track> tracks;
  final SaturdayColorTokens colors;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = tracks.fold<int>(
      0,
      (sum, track) => sum + (track.durationSeconds ?? 0),
    );
    if (totalSeconds == 0) return const SizedBox.shrink();

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final formatted =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(top: SaturdaySpace.space2),
      child: Row(
        children: [
          const SizedBox(width: 36),
          const SizedBox(width: SaturdaySpace.space3),
          Expanded(
            child: Text(
              'Total',
              style: SaturdayType.meta.copyWith(color: colors.inkTertiary),
            ),
          ),
          Text(
            formatted,
            style: SaturdayType.mono.copyWith(color: colors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// Compact track preview used in card-style surfaces (e.g. detail panels).
class CompactTrackList extends StatelessWidget {
  const CompactTrackList({
    super.key,
    required this.tracks,
    this.maxTracks = 5,
  });

  final List<Track> tracks;
  final int maxTracks;

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);

    if (tracks.isEmpty) {
      return Text(
        'No tracks recorded.',
        style: SaturdayType.bodySmall.copyWith(color: colors.inkSecondary),
      );
    }

    final displayTracks = tracks.take(maxTracks).toList();
    final remaining = tracks.length - maxTracks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...displayTracks.map(
          (track) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${track.position}  ${track.title}',
              style: SaturdayType.bodySmall.copyWith(color: colors.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$remaining more',
              style: SaturdayType.meta.copyWith(color: colors.inkTertiary),
            ),
          ),
      ],
    );
  }
}
