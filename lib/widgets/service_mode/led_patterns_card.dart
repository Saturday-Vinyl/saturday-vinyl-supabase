import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/service_mode_manifest.dart';

/// Card displaying LED status patterns from the device manifest
/// Helps technicians understand what LED colors/patterns mean
class LedPatternsCard extends StatelessWidget {
  final Map<String, LedPattern> ledPatterns;

  const LedPatternsCard({
    super.key,
    required this.ledPatterns,
  });

  @override
  Widget build(BuildContext context) {
    if (ledPatterns.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  'LED Status Indicators',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Reference guide for LED patterns',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SaturdayColors.secondaryGrey,
                  ),
            ),
            const Divider(height: 24),
            ...ledPatterns.entries.map((entry) => _buildPatternRow(
                  context,
                  entry.key,
                  entry.value,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildPatternRow(
    BuildContext context,
    String statusName,
    LedPattern pattern,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // LED color indicator
          _LedIndicator(
            color: _parseColor(pattern.color),
            pattern: pattern.pattern,
          ),
          const SizedBox(width: 12),
          // Status name and description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatStatusName(statusName),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_formatColor(pattern.color)} · ${_formatPattern(pattern.pattern)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SaturdayColors.secondaryGrey,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      case 'yellow':
        return Colors.yellow;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'cyan':
        return Colors.cyan;
      case 'magenta':
        return Colors.pink;
      case 'white':
        return Colors.white;
      case 'off':
        return Colors.grey[800]!;
      default:
        // Try to parse hex color
        if (colorName.startsWith('#') && colorName.length == 7) {
          try {
            return Color(int.parse('FF${colorName.substring(1)}', radix: 16));
          } catch (_) {}
        }
        return Colors.grey;
    }
  }

  String _formatStatusName(String name) {
    // Convert snake_case to Title Case
    return name.split('_').map((word) {
      if (word.isEmpty) return word;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  String _formatColor(String color) {
    return color[0].toUpperCase() + color.substring(1).toLowerCase();
  }

  String _formatPattern(String pattern) {
    switch (pattern.toLowerCase()) {
      case 'solid':
        return 'Solid';
      case 'blink':
        return 'Blinking';
      case 'blink_fast':
        return 'Fast Blink';
      case 'blink_slow':
        return 'Slow Blink';
      case 'pulse':
        return 'Pulsing';
      case 'breathe':
        return 'Breathing';
      case 'flash':
        return 'Flash';
      case 'off':
        return 'Off';
      default:
        return pattern[0].toUpperCase() + pattern.substring(1);
    }
  }
}

/// Animated LED indicator widget
class _LedIndicator extends StatefulWidget {
  final Color color;
  final String pattern;

  const _LedIndicator({
    required this.color,
    required this.pattern,
  });

  @override
  State<_LedIndicator> createState() => _LedIndicatorState();
}

class _LedIndicatorState extends State<_LedIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  @override
  void didUpdateWidget(_LedIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pattern != widget.pattern) {
      _controller.dispose();
      _setupAnimation();
    }
  }

  void _setupAnimation() {
    final duration = _getDurationForPattern(widget.pattern);
    _controller = AnimationController(
      vsync: this,
      duration: duration,
    );

    switch (widget.pattern.toLowerCase()) {
      case 'blink':
      case 'blink_fast':
      case 'blink_slow':
      case 'flash':
        _animation = TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.2), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 0.2, end: 1.0), weight: 1),
        ]).animate(_controller);
        _controller.repeat();
        break;
      case 'pulse':
      case 'breathe':
        _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        );
        _controller.repeat(reverse: true);
        break;
      case 'solid':
      case 'off':
      default:
        _animation = const AlwaysStoppedAnimation(1.0);
        break;
    }
  }

  Duration _getDurationForPattern(String pattern) {
    switch (pattern.toLowerCase()) {
      case 'blink_fast':
        return const Duration(milliseconds: 300);
      case 'blink':
      case 'flash':
        return const Duration(milliseconds: 600);
      case 'blink_slow':
        return const Duration(milliseconds: 1200);
      case 'pulse':
      case 'breathe':
        return const Duration(milliseconds: 2000);
      default:
        return const Duration(milliseconds: 1000);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOff = widget.pattern.toLowerCase() == 'off' ||
        widget.color == Colors.grey[800];

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOff
                ? Colors.grey[800]
                : widget.color.withValues(alpha: _animation.value),
            border: Border.all(
              color: Colors.grey[600]!,
              width: 1,
            ),
            boxShadow: isOff
                ? null
                : [
                    BoxShadow(
                      color: widget.color.withValues(alpha: _animation.value * 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
          ),
        );
      },
    );
  }
}
