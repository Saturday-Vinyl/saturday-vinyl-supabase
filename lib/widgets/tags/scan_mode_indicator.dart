import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/providers/scan_mode_provider.dart';

/// Visual indicator showing scan mode is active
class ScanModeIndicator extends ConsumerWidget {
  const ScanModeIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(scanModeProvider);

    if (!scanState.isScanning) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SaturdayColors.info.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: SaturdayColors.info.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Pulsing dot animation
          const _PulsingDot(),
          const SizedBox(width: 12),

          // Scanning text
          Text(
            'Scanning...',
            style: TextStyle(
              color: SaturdayColors.info,
              fontWeight: FontWeight.w600,
            ),
          ),

          const Spacer(),

          // Found count
          _buildCountBadge(
            'Found',
            scanState.foundEpcs.length,
            SaturdayColors.success,
          ),

          const SizedBox(width: 8),

          // Unknown count (if any)
          if (scanState.unknownEpcs.isNotEmpty)
            _buildCountBadge(
              'Unknown',
              scanState.unknownEpcs.length,
              Colors.orange,
            ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated pulsing dot to indicate active scanning
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: SaturdayColors.info.withValues(alpha: _animation.value),
            boxShadow: [
              BoxShadow(
                color: SaturdayColors.info.withValues(alpha: _animation.value * 0.5),
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

/// Compact scan status for use in buttons or headers
class ScanStatusChip extends ConsumerWidget {
  final VoidCallback? onTap;

  const ScanStatusChip({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanState = ref.watch(scanModeProvider);

    if (!scanState.isScanning && scanState.foundEpcs.isEmpty) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: scanState.isScanning
              ? SaturdayColors.info.withValues(alpha: 0.1)
              : SaturdayColors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scanState.isScanning
                ? SaturdayColors.info.withValues(alpha: 0.3)
                : SaturdayColors.success.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (scanState.isScanning) ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: SaturdayColors.info,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              scanState.isScanning
                  ? 'Scanning (${scanState.foundEpcs.length})'
                  : '${scanState.foundEpcs.length} found',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: scanState.isScanning
                    ? SaturdayColors.info
                    : SaturdayColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
