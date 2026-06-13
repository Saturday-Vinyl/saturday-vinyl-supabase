import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';

/// Resolve battery tone from a level.
///
/// Per the Saturday constitution, criticality is communicated by text and
/// position — not by red/amber/green. Unknown and critical levels render in
/// `inkTertiary` (muted, drawing the listener's eye to the label); healthy
/// levels render in `ink`.
Color _batteryTone(SaturdayColorTokens colors, int? level) {
  if (level == null) return colors.inkTertiary;
  if (level <= 20) return colors.inkTertiary;
  return colors.ink;
}

IconData _batteryIconFor(int? level, {required bool isCharging}) {
  if (isCharging) return Icons.battery_charging_full;
  if (level == null) return Icons.battery_unknown;
  if (level <= 10) return Icons.battery_alert;
  if (level <= 20) return Icons.battery_1_bar;
  if (level <= 40) return Icons.battery_2_bar;
  if (level <= 60) return Icons.battery_4_bar;
  if (level <= 80) return Icons.battery_5_bar;
  return Icons.battery_full;
}

/// A widget displaying a battery level indicator.
///
/// Shows the battery icon with fill level and optional percentage text.
/// When [isCharging] is true, shows a charging icon variant.
class BatteryIndicator extends StatelessWidget {
  /// Battery level from 0 to 100.
  final int? level;

  /// Whether the device is currently charging.
  final bool isCharging;

  /// Whether to show the percentage text.
  final bool showPercentage;

  /// Size of the battery icon.
  final double size;

  const BatteryIndicator({
    super.key,
    this.level,
    this.isCharging = false,
    this.showPercentage = true,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final tone = _batteryTone(colors, level);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _batteryIconFor(level, isCharging: isCharging),
          color: tone,
          size: size,
        ),
        if (showPercentage && level != null) ...[
          const SizedBox(width: 4),
          Text(
            '$level%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tone,
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
  final bool isCharging;
  final double size;

  const BatteryIconOnly({
    super.key,
    this.level,
    this.isCharging = false,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final tooltip = isCharging
        ? 'Charging${level != null ? ' ($level%)' : ''}'
        : level != null
            ? '$level% battery'
            : 'Unknown battery level';
    return Tooltip(
      message: tooltip,
      child: Icon(
        _batteryIconFor(level, isCharging: isCharging),
        color: _batteryTone(colors, level),
        size: size,
      ),
    );
  }
}

/// A detailed battery display with progress bar.
class BatteryProgress extends StatelessWidget {
  final int? level;
  final bool isCharging;

  const BatteryProgress({
    super.key,
    this.level,
    this.isCharging = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final tone = _batteryTone(colors, level);
    final displayLevel = level ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Battery',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (isCharging) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.bolt,
                    size: 14,
                    color: colors.ink,
                  ),
                  Text(
                    'Charging',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.ink,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ],
            ),
            Text(
              level != null ? '$level%' : 'Unknown',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tone,
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
            backgroundColor: colors.borderQuiet,
            valueColor: AlwaysStoppedAnimation<Color>(colors.ink),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
