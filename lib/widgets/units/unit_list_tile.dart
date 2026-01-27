import 'package:flutter/material.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/unit.dart';
import 'package:saturday_app/models/unit_list_item.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Compact list tile for unit dashboard display
///
/// Displays unit information including:
/// - Connection status indicator
/// - Display name and serial number
/// - Status chip
/// - Last seen time
/// - Telemetry badges (battery, RSSI, temperature, humidity)
class UnitListTile extends StatelessWidget {
  final UnitListItem unit;
  final VoidCallback? onTap;

  const UnitListTile({
    super.key,
    required this.unit,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Connection indicator
              _buildConnectionIndicator(),
              const SizedBox(width: 12),

              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top row: Name and status
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            unit.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Bottom row: Serial number and last seen
                    Row(
                      children: [
                        if (unit.serialNumber != null)
                          Text(
                            unit.serialNumber!,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: SaturdayColors.secondaryGrey,
                            ),
                          ),
                        const Spacer(),
                        if (unit.lastSeenAt != null) _buildLastSeen(),
                      ],
                    ),
                  ],
                ),
              ),

              // Telemetry badges
              if (unit.hasTelemetry) ...[
                const SizedBox(width: 8),
                _buildTelemetryBadges(),
              ],

              // Chevron
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: SaturdayColors.secondaryGrey.withValues(alpha: 0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionIndicator() {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: unit.isConnected
            ? SaturdayColors.success
            : SaturdayColors.secondaryGrey.withValues(alpha: 0.4),
        boxShadow: unit.isConnected
            ? [
                BoxShadow(
                  color: SaturdayColors.success.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildStatusChip() {
    Color color;
    String label;

    switch (unit.status) {
      case UnitStatus.unprovisioned:
        color = SaturdayColors.secondaryGrey;
        label = 'Unprov';
        break;
      case UnitStatus.factoryProvisioned:
        color = SaturdayColors.info;
        label = 'Factory';
        break;
      case UnitStatus.userProvisioned:
        color = SaturdayColors.success;
        label = 'Claimed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildLastSeen() {
    final lastSeen = unit.lastSeenAt!;
    final ago = timeago.format(lastSeen, locale: 'en_short');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.access_time,
          size: 12,
          color: SaturdayColors.secondaryGrey.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 2),
        Text(
          ago,
          style: TextStyle(
            fontSize: 11,
            color: SaturdayColors.secondaryGrey.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryBadges() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unit.batteryLevel != null)
          _TelemetryBadge(
            icon: _getBatteryIcon(unit.batteryLevel!, unit.batteryCharging),
            value: '${unit.batteryLevel}%',
            color: _getBatteryColor(unit.batteryLevel!),
          ),
        if (unit.signalStrength != null)
          _TelemetryBadge(
            icon: unit.wifiRssi != null
                ? Icons.signal_wifi_4_bar
                : Icons.settings_input_antenna,
            value: '${unit.signalStrength}',
            color: _getRssiColor(unit.signalStrength!),
          ),
        if (unit.uptimeSec != null)
          _TelemetryBadge(
            icon: Icons.timer_outlined,
            value: _formatUptime(unit.uptimeSec!),
            color: SaturdayColors.info,
          ),
      ],
    );
  }

  String _formatUptime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${(seconds / 60).floor()}m';
    if (seconds < 86400) return '${(seconds / 3600).floor()}h';
    return '${(seconds / 86400).floor()}d';
  }

  IconData _getBatteryIcon(int level, bool? charging) {
    if (charging == true) return Icons.battery_charging_full;
    if (level >= 90) return Icons.battery_full;
    if (level >= 60) return Icons.battery_5_bar;
    if (level >= 40) return Icons.battery_4_bar;
    if (level >= 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color _getBatteryColor(int level) {
    if (level >= 40) return SaturdayColors.success;
    if (level >= 20) return SaturdayColors.warning;
    return SaturdayColors.error;
  }

  Color _getRssiColor(int rssi) {
    // RSSI typically ranges from -30 (excellent) to -90 (poor)
    if (rssi >= -50) return SaturdayColors.success;
    if (rssi >= -70) return SaturdayColors.info;
    if (rssi >= -80) return SaturdayColors.warning;
    return SaturdayColors.error;
  }
}

/// Small badge displaying a telemetry value with an icon
class _TelemetryBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _TelemetryBadge({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
