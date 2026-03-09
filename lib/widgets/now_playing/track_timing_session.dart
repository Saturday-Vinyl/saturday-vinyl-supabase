import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/providers/track_timing_provider.dart';
import 'package:saturday_consumer_app/repositories/track_duration_repository.dart';

/// The interactive track timing session UI.
///
/// Shows a stopwatch and a list of tracks. The user taps to advance through
/// tracks, recording the duration of each one. After the last track, the user
/// reviews the results and can save or redo.
class TrackTimingSession extends ConsumerWidget {
  const TrackTimingSession({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackTimingProvider);

    if (state.isTiming) {
      return _TimingView(state: state);
    } else if (state.isReviewing || state.isSaving) {
      return _ReviewView(state: state);
    }

    return const SizedBox.shrink();
  }
}

/// Active timing view with stopwatch and track list.
class _TimingView extends ConsumerWidget {
  const _TimingView({required this.state});

  final TrackTimingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.card,
        border: Border.all(
          color: SaturdayColors.primaryDark,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.lg,
              vertical: Spacing.md,
            ),
            decoration: BoxDecoration(
              color: SaturdayColors.primaryDark,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg - 2),
                topRight: Radius.circular(AppRadius.lg - 2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recording Side ${state.side}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: SaturdayColors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                GestureDetector(
                  onTap: () =>
                      ref.read(trackTimingProvider.notifier).cancel(),
                  child: Text(
                    'Cancel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.white.withValues(alpha: 0.8),
                        ),
                  ),
                ),
              ],
            ),
          ),

          // Stopwatch display
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            child: Center(
              child: Text(
                state.formattedElapsedPrecise,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w300,
                      letterSpacing: 2,
                    ),
              ),
            ),
          ),

          // Track list
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Column(
              children: [
                for (var i = 0; i < state.tracks.length; i++)
                  _TimingTrackRow(
                    track: state.tracks[i],
                    index: i,
                    currentIndex: state.currentTrackIndex,
                    recordedDuration: i < state.recordedDurations.length
                        ? state.recordedDurations[i]
                        : null,
                  ),
              ],
            ),
          ),

          const SizedBox(height: Spacing.md),

          // Next / Done button
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(trackTimingProvider.notifier).nextTrack();
                },
                icon: Icon(
                  state.isLastTrack ? Icons.check : Icons.skip_next,
                ),
                label: Text(
                  state.isLastTrack ? 'Finish' : 'Next Track',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SaturdayColors.primaryDark,
                  foregroundColor: SaturdayColors.white,
                  padding: const EdgeInsets.symmetric(vertical: Spacing.md),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.mediumRadius,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single track row in the timing view.
class _TimingTrackRow extends StatelessWidget {
  const _TimingTrackRow({
    required this.track,
    required this.index,
    required this.currentIndex,
    this.recordedDuration,
  });

  final dynamic track;
  final int index;
  final int currentIndex;
  final TrackDuration? recordedDuration;

  bool get isCompleted => recordedDuration != null;
  bool get isCurrent => index == currentIndex;
  bool get isPending => index > currentIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        children: [
          // Status indicator
          SizedBox(
            width: 24,
            child: isCompleted
                ? Icon(Icons.check_circle,
                    size: 18, color: SaturdayColors.success)
                : isCurrent
                    ? _PulsingDot()
                    : Icon(Icons.circle_outlined,
                        size: 18,
                        color: SaturdayColors.secondary.withValues(alpha: 0.3)),
          ),
          const SizedBox(width: Spacing.sm),

          // Position
          SizedBox(
            width: 28,
            child: Text(
              track.position,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isCurrent
                        ? SaturdayColors.primaryDark
                        : SaturdayColors.secondary,
                    fontWeight: isCurrent ? FontWeight.w600 : null,
                  ),
            ),
          ),
          const SizedBox(width: Spacing.sm),

          // Title
          Expanded(
            child: Text(
              track.title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isCurrent
                        ? SaturdayColors.primaryDark
                        : isPending
                            ? SaturdayColors.secondary
                            : SaturdayColors.primaryDark,
                    fontWeight: isCurrent ? FontWeight.w600 : null,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: Spacing.sm),

          // Duration (recorded or pending)
          Text(
            isCompleted
                ? _formatDuration(recordedDuration!.durationSeconds)
                : '--:--',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: isCompleted
                      ? SaturdayColors.success
                      : SaturdayColors.secondary.withValues(alpha: 0.4),
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

/// A pulsing dot indicator for the currently timing track.
class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SaturdayColors.error
                .withValues(alpha: 0.5 + (_controller.value * 0.5)),
          ),
        );
      },
    );
  }
}

/// Review view showing recorded durations with save/redo actions.
class _ReviewView extends ConsumerWidget {
  const _ReviewView({required this.state});

  final TrackTimingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(Spacing.lg),
            decoration: BoxDecoration(
              color: SaturdayColors.success.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: SaturdayColors.success),
                const SizedBox(width: Spacing.sm),
                Text(
                  'Side ${state.side} Recorded',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),

          // Recorded durations list
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              children: [
                for (var i = 0; i < state.tracks.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text(
                            state.tracks[i].position,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: SaturdayColors.secondary),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            state.tracks[i].title,
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        Text(
                          i < state.recordedDurations.length
                              ? _formatDuration(
                                  state.recordedDurations[i].durationSeconds)
                              : '--:--',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Text(
                state.error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: SaturdayColors.error,
                    ),
              ),
            ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              children: [
                // Redo button
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.isSaving
                        ? null
                        : () =>
                            ref.read(trackTimingProvider.notifier).redo(),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Redo'),
                    style: OutlinedButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(vertical: Spacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.mediumRadius,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                // Save button
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: state.isSaving
                        ? null
                        : () =>
                            ref.read(trackTimingProvider.notifier).save(),
                    icon: state.isSaving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: SaturdayColors.white,
                            ),
                          )
                        : const Icon(Icons.save),
                    label: Text(state.isSaving ? 'Saving...' : 'Save'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SaturdayColors.primaryDark,
                      foregroundColor: SaturdayColors.white,
                      padding:
                          const EdgeInsets.symmetric(vertical: Spacing.md),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.mediumRadius,
                      ),
                    ),
                  ),
                ),
              ],
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
