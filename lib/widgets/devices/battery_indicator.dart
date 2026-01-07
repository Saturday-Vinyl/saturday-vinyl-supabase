import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';

/// A widget displaying a battery level indicator.
///
/// Shows the battery icon with fill level and optional percentage text.
class BatteryIndicator extends StatelessWidget {
  /// Battery level from 0 to 100.
  final int? level;

  /// Whether to show the percentage text.
  final bool showPercentage;

  /// Size of the battery icon.
  final double size;

  const BatteryIndicator({
    super.key,
    this.level,
    this.showPercentage = true,
    this.size = 24,
  });

  Color get _batteryColor {
    if (level == null) return SaturdayColors.secondary;
    if (level! <= 10) return SaturdayColors.error;
    if (level! <= 20) return SaturdayColors.warning;
    return SaturdayColors.success;
  }

  IconData get _batteryIcon {
    if (level == null) return Icons.battery_unknown;
    if (level! <= 10) return Icons.battery_alert;
    if (level! <= 20) return Icons.battery_1_bar;
    if (level! <= 40) return Icons.battery_2_bar;
    if (level! <= 60) return Icons.battery_4_bar;
    if (level! <= 80) return Icons.battery_5_bar;
    return Icons.battery_full;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _batteryIcon,
          color: _batteryColor,
          size: size,
        ),
        if (showPercentage && level != null) ...[
          const SizedBox(width: 4),
          Text(
            '$level%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _batteryColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ],
    );
  }
}

/// A compact battery indicator that only shows icon with tooltip.
class BatteryIconOnly extends StatelessWidget {
  final int? level;
  final double size;

  const BatteryIconOnly({
    super.key,
    this.level,
    this.size = 20,
  });

  Color get _batteryColor {
    if (level == null) return SaturdayColors.secondary;
    if (level! <= 10) return SaturdayColors.error;
    if (level! <= 20) return SaturdayColors.warning;
    return SaturdayColors.success;
  }

  IconData get _batteryIcon {
    if (level == null) return Icons.battery_unknown;
    if (level! <= 10) return Icons.battery_alert;
    if (level! <= 20) return Icons.battery_1_bar;
    if (level! <= 40) return Icons.battery_2_bar;
    if (level! <= 60) return Icons.battery_4_bar;
    if (level! <= 80) return Icons.battery_5_bar;
    return Icons.battery_full;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: level != null ? '$level% battery' : 'Unknown battery level',
      child: Icon(
        _batteryIcon,
        color: _batteryColor,
        size: size,
      ),
    );
  }
}

/// A detailed battery display with progress bar.
class BatteryProgress extends StatelessWidget {
  final int? level;

  const BatteryProgress({
    super.key,
    this.level,
  });

  Color get _batteryColor {
    if (level == null) return SaturdayColors.secondary;
    if (level! <= 10) return SaturdayColors.error;
    if (level! <= 20) return SaturdayColors.warning;
    return SaturdayColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final displayLevel = level ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Battery',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              level != null ? '$level%' : 'Unknown',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _batteryColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: displayLevel / 100,
            backgroundColor: SaturdayColors.secondary.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(_batteryColor),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
