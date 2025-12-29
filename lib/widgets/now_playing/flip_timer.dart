import 'dart:async';

import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A timer widget that shows elapsed and remaining time for the current side.
///
/// Updates every second and shows visual urgency when approaching flip time.
class FlipTimer extends StatefulWidget {
  const FlipTimer({
    super.key,
    required this.startedAt,
    required this.totalDurationSeconds,
    this.flipWarningThreshold = 120, // 2 minutes before end
  });

  /// When the current side started playing.
  final DateTime startedAt;

  /// Total duration of the current side in seconds.
  final int totalDurationSeconds;

  /// Seconds before end to show warning (default 2 minutes).
  final int flipWarningThreshold;

  @override
  State<FlipTimer> createState() => _FlipTimerState();
}

class _FlipTimerState extends State<FlipTimer> {
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _calculateElapsed();
    _startTimer();
  }

  @override
  void didUpdateWidget(FlipTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _calculateElapsed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _calculateElapsed() {
    final now = DateTime.now();
    _elapsedSeconds = now.difference(widget.startedAt).inSeconds;
    if (_elapsedSeconds < 0) _elapsedSeconds = 0;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.totalDurationSeconds - _elapsedSeconds;
    final isNearFlip =
        remaining > 0 && remaining <= widget.flipWarningThreshold;
    final isOvertime = remaining < 0;

    // Calculate progress (0.0 to 1.0)
    final progress = widget.totalDurationSeconds > 0
        ? (_elapsedSeconds / widget.totalDurationSeconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: SaturdayColors.white,
        borderRadius: AppRadius.largeRadius,
        boxShadow: AppShadows.card,
        border: isNearFlip || isOvertime
            ? Border.all(
                color: isOvertime
                    ? SaturdayColors.error
                    : SaturdayColors.warning,
                width: 2,
              )
            : null,
      ),
      child: Column(
        children: [
          // Progress bar
          ClipRRect(
            borderRadius: AppRadius.smallRadius,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: SaturdayColors.secondary.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(
                isOvertime
                    ? SaturdayColors.error
                    : isNearFlip
                        ? SaturdayColors.warning
                        : SaturdayColors.primaryDark,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: Spacing.md),

          // Time display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Elapsed time
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Elapsed',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: SaturdayColors.secondary,
                        ),
                  ),
                  Text(
                    _formatDuration(_elapsedSeconds),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                  ),
                ],
              ),

              // Flip indicator
              if (isNearFlip || isOvertime)
                _FlipIndicator(isOvertime: isOvertime),

              // Remaining time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isOvertime ? 'Overtime' : 'Remaining',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isOvertime || isNearFlip
                              ? (isOvertime
                                  ? SaturdayColors.error
                                  : SaturdayColors.warning)
                              : SaturdayColors.secondary,
                        ),
                  ),
                  Text(
                    isOvertime
                        ? '+${_formatDuration(-remaining)}'
                        : _formatDuration(remaining.abs()),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: isOvertime || isNearFlip
                              ? (isOvertime
                                  ? SaturdayColors.error
                                  : SaturdayColors.warning)
                              : null,
                        ),
                  ),
                ],
              ),
            ],
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

/// An animated flip reminder indicator.
class _FlipIndicator extends StatefulWidget {
  const _FlipIndicator({required this.isOvertime});

  final bool isOvertime;

  @override
  State<_FlipIndicator> createState() => _FlipIndicatorState();
}

class _FlipIndicatorState extends State<_FlipIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
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
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: (widget.isOvertime
                    ? SaturdayColors.error
                    : SaturdayColors.warning)
                .withValues(alpha: 0.1 + (_controller.value * 0.2)),
            borderRadius: AppRadius.smallRadius,
            border: Border.all(
              color: widget.isOvertime
                  ? SaturdayColors.error
                  : SaturdayColors.warning,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.flip,
                size: 18,
                color: widget.isOvertime
                    ? SaturdayColors.error
                    : SaturdayColors.warning,
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                widget.isOvertime ? 'Flip Now!' : 'Flip Soon',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: widget.isOvertime
                          ? SaturdayColors.error
                          : SaturdayColors.warning,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A compact version of the flip timer for smaller spaces.
class CompactFlipTimer extends StatefulWidget {
  const CompactFlipTimer({
    super.key,
    required this.startedAt,
    required this.totalDurationSeconds,
  });

  final DateTime startedAt;
  final int totalDurationSeconds;

  @override
  State<CompactFlipTimer> createState() => _CompactFlipTimerState();
}

class _CompactFlipTimerState extends State<CompactFlipTimer> {
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _calculateElapsed();
    _startTimer();
  }

  @override
  void didUpdateWidget(CompactFlipTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _calculateElapsed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _calculateElapsed() {
    final now = DateTime.now();
    _elapsedSeconds = now.difference(widget.startedAt).inSeconds;
    if (_elapsedSeconds < 0) _elapsedSeconds = 0;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.totalDurationSeconds - _elapsedSeconds;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.timer_outlined,
          size: 16,
          color: SaturdayColors.secondary,
        ),
        const SizedBox(width: Spacing.xs),
        Text(
          remaining >= 0
              ? '${_formatDuration(_elapsedSeconds)} / ${_formatDuration(widget.totalDurationSeconds)}'
              : _formatDuration(_elapsedSeconds),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: SaturdayColors.secondary,
              ),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
