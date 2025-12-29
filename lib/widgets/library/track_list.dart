import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/track.dart';

/// A widget that displays a list of tracks with side separation.
///
/// Automatically detects Side A/B patterns in track positions and groups them.
class TrackList extends StatelessWidget {
  const TrackList({
    super.key,
    required this.tracks,
    this.showSideDurations = true,
  });

  /// The tracks to display.
  final List<Track> tracks;

  /// Whether to show total duration for each side.
  final bool showSideDurations;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return _buildEmptyState(context);
    }

    final sides = _groupTracksBySide(tracks);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in sides.entries) ...[
          if (sides.length > 1) _buildSideHeader(context, entry.key, entry.value),
          ...entry.value.map((track) => _TrackTile(track: track)),
          if (showSideDurations && sides.length > 1)
            _buildSideDuration(context, entry.value),
          if (entry.key != sides.keys.last) const SizedBox(height: Spacing.lg),
        ],
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
      child: Center(
        child: Text(
          'No track information available',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: SaturdayColors.secondary,
              ),
        ),
      ),
    );
  }

  Widget _buildSideHeader(
    BuildContext context,
    String side,
    List<Track> sideTracks,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(
        side,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildSideDuration(BuildContext context, List<Track> sideTracks) {
    final totalSeconds = sideTracks.fold<int>(
      0,
      (sum, track) => sum + (track.durationSeconds ?? 0),
    );

    if (totalSeconds == 0) return const SizedBox.shrink();

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final formatted =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.xs),
      child: Text(
        'Total: $formatted',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: SaturdayColors.secondary,
            ),
      ),
    );
  }

  /// Groups tracks by side based on their position.
  ///
  /// Detects patterns like "A1", "A2", "B1", "B2" or "1", "2", "3", "4".
  Map<String, List<Track>> _groupTracksBySide(List<Track> tracks) {
    final sides = <String, List<Track>>{};

    for (final track in tracks) {
      final side = _extractSide(track.position);
      sides.putIfAbsent(side, () => []).add(track);
    }

    // If only one side detected, don't show side headers
    if (sides.length == 1 && sides.keys.first == 'Tracks') {
      return {'': tracks};
    }

    return sides;
  }

  /// Extracts the side identifier from a track position.
  String _extractSide(String position) {
    final trimmed = position.trim().toUpperCase();

    // Check for letter prefix (A1, B2, C1, etc.)
    if (trimmed.isNotEmpty && RegExp(r'^[A-Z]').hasMatch(trimmed)) {
      final letter = trimmed[0];
      return 'Side $letter';
    }

    // Check for numeric position with explicit side markers
    if (trimmed.contains('-')) {
      final parts = trimmed.split('-');
      if (parts.length >= 2) {
        return 'Side ${parts[0]}';
      }
    }

    // Default to "Tracks" if no side pattern detected
    return 'Tracks';
  }
}

/// A single track row.
class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          // Track position
          SizedBox(
            width: 32,
            child: Text(
              track.position,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SaturdayColors.secondary,
                  ),
            ),
          ),
          const SizedBox(width: Spacing.sm),

          // Track title
          Expanded(
            child: Text(
              track.title,
              style: Theme.of(context).textTheme.bodyMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Spacing.sm),

          // Duration
          Text(
            track.formattedDuration,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
        ],
      ),
    );
  }
}

/// A compact track list for use in smaller spaces.
class CompactTrackList extends StatelessWidget {
  const CompactTrackList({
    super.key,
    required this.tracks,
    this.maxTracks = 5,
  });

  /// The tracks to display.
  final List<Track> tracks;

  /// Maximum number of tracks to show before truncating.
  final int maxTracks;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return Text(
        'No tracks',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: SaturdayColors.secondary,
            ),
      );
    }

    final displayTracks = tracks.take(maxTracks).toList();
    final remaining = tracks.length - maxTracks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...displayTracks.map((track) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${track.position}. ${track.title}',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )),
        if (remaining > 0)
          Text(
            '+$remaining more tracks',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondary,
                ),
          ),
      ],
    );
  }
}
