import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/track.dart';

/// A track list widget for the Now Playing screen.
///
/// Shows all tracks with the current side highlighted.
/// Supports expansion/collapse for space efficiency.
class NowPlayingTrackList extends StatefulWidget {
  const NowPlayingTrackList({
    super.key,
    required this.sideATracks,
    required this.sideBTracks,
    required this.currentSide,
    this.initiallyExpanded = false,
  });

  /// Tracks for Side A.
  final List<Track> sideATracks;

  /// Tracks for Side B.
  final List<Track> sideBTracks;

  /// The currently playing side ('A' or 'B').
  final String currentSide;

  /// Whether the track list is initially expanded.
  final bool initiallyExpanded;

  @override
  State<NowPlayingTrackList> createState() => _NowPlayingTrackListState();
}

class _NowPlayingTrackListState extends State<NowPlayingTrackList> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final hasTracks =
        widget.sideATracks.isNotEmpty || widget.sideBTracks.isNotEmpty;

    if (!hasTracks) {
      return _buildEmptyState(context);
    }

    return Container(
      decoration: AppDecorations.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with expand/collapse
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: AppRadius.largeRadius,
            child: Padding(
              padding: Spacing.cardPadding,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tracks',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Row(
                    children: [
                      Text(
                        '${widget.sideATracks.length + widget.sideBTracks.length} tracks',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: SaturdayColors.secondary,
                            ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      AnimatedRotation(
                        duration: AppDurations.fast,
                        turns: _isExpanded ? 0.5 : 0,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: SaturdayColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Track list content
          AnimatedCrossFade(
            duration: AppDurations.normal,
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: _buildTrackListContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: Spacing.cardPadding,
      decoration: AppDecorations.card,
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

  Widget _buildTrackListContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: Spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Side A
          if (widget.sideATracks.isNotEmpty) ...[
            _SideSection(
              side: 'A',
              tracks: widget.sideATracks,
              isCurrentSide: widget.currentSide == 'A',
            ),
          ],

          // Side B
          if (widget.sideBTracks.isNotEmpty) ...[
            if (widget.sideATracks.isNotEmpty)
              const SizedBox(height: Spacing.lg),
            _SideSection(
              side: 'B',
              tracks: widget.sideBTracks,
              isCurrentSide: widget.currentSide == 'B',
            ),
          ],
        ],
      ),
    );
  }
}

/// A section showing tracks for one side.
class _SideSection extends StatelessWidget {
  const _SideSection({
    required this.side,
    required this.tracks,
    required this.isCurrentSide,
  });

  final String side;
  final List<Track> tracks;
  final bool isCurrentSide;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = tracks.fold<int>(
      0,
      (sum, track) => sum + (track.durationSeconds ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Side header
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          decoration: BoxDecoration(
            color: isCurrentSide
                ? SaturdayColors.primaryDark
                : SaturdayColors.secondary.withValues(alpha: 0.1),
            borderRadius: AppRadius.smallRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCurrentSide) ...[
                Icon(
                  Icons.play_arrow,
                  size: 14,
                  color: SaturdayColors.white,
                ),
                const SizedBox(width: Spacing.xs),
              ],
              Text(
                'Side $side',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: isCurrentSide
                          ? SaturdayColors.white
                          : SaturdayColors.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                _formatDuration(totalSeconds),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isCurrentSide
                          ? SaturdayColors.white.withValues(alpha: 0.7)
                          : SaturdayColors.secondary,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.sm),

        // Tracks
        ...tracks.map((track) => _TrackRow(
              track: track,
              isCurrentSide: isCurrentSide,
            )),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

/// A single track row.
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.isCurrentSide,
  });

  final Track track;
  final bool isCurrentSide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          // Position
          SizedBox(
            width: 28,
            child: Text(
              track.position,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isCurrentSide
                        ? SaturdayColors.primaryDark
                        : SaturdayColors.secondary,
                    fontWeight: isCurrentSide ? FontWeight.w500 : null,
                  ),
            ),
          ),
          const SizedBox(width: Spacing.sm),

          // Title
          Expanded(
            child: Text(
              track.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isCurrentSide
                        ? SaturdayColors.primaryDark
                        : SaturdayColors.secondary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Spacing.sm),

          // Duration
          Text(
            track.formattedDuration,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SaturdayColors.secondary,
                  fontFamily: 'monospace',
                ),
          ),
        ],
      ),
    );
  }
}
