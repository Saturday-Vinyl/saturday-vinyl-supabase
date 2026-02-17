import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/widgets/devices/battery_indicator.dart';
import 'package:saturday_consumer_app/widgets/devices/status_badge.dart';

/// A card widget displaying device information.
///
/// Shows device type icon, name, status, and battery level (for crates).
/// Uses heartbeat-aware connectivity status for accurate online/offline display.
class DeviceCard extends StatelessWidget {
  final Device device;
  final VoidCallback? onTap;

  const DeviceCard({
    super.key,
    required this.device,
    this.onTap,
  });

  IconData get _deviceIcon {
    return device.isHub ? Icons.router : Icons.inventory_2_outlined;
  }

  String get _deviceTypeLabel {
    return device.isHub ? 'Hub' : 'Crate';
  }

  String? get _lastSeenText {
    if (device.lastSeenAt == null) return null;
    final diff = DateTime.now().difference(device.lastSeenAt!);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return null;
  }

  Color get _iconBackgroundColor {
    switch (device.connectivityStatus) {
      case ConnectivityStatus.online:
        return SaturdayColors.success.withValues(alpha: 0.1);
      case ConnectivityStatus.offline:
      case ConnectivityStatus.setupRequired:
        return SaturdayColors.secondary.withValues(alpha: 0.1);
    }
  }

  Color get _iconColor {
    switch (device.connectivityStatus) {
      case ConnectivityStatus.online:
        return SaturdayColors.success;
      case ConnectivityStatus.offline:
      case ConnectivityStatus.setupRequired:
        return SaturdayColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.largeRadius,
        child: Padding(
          padding: Spacing.cardPadding,
          child: Row(
            children: [
              // Device icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _iconBackgroundColor,
                  borderRadius: AppRadius.mediumRadius,
                ),
                child: Icon(
                  _deviceIcon,
                  color: _iconColor,
                  size: 24,
                ),
              ),
              Spacing.horizontalGapMd,
              // Device info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _deviceTypeLabel,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (_lastSeenText != null) ...[
                          Text(
                            ' • $_lastSeenText',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Status and battery
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ConnectivityStatusBadge.fromDevice(device: device),
                  if (device.isCrate && device.batteryLevel != null) ...[
                    const SizedBox(height: 4),
                    BatteryIndicator(
                      level: device.batteryLevel,
                      size: 18,
                    ),
                  ],
                ],
              ),
              Spacing.horizontalGapSm,
              Icon(
                Icons.chevron_right,
                color: SaturdayColors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact device card for list views.
/// Uses heartbeat-aware connectivity status for accurate online/offline display.
class DeviceListTile extends StatelessWidget {
  final Device device;
  final VoidCallback? onTap;

  const DeviceListTile({
    super.key,
    required this.device,
    this.onTap,
  });

  Color get _avatarBackgroundColor {
    switch (device.connectivityStatus) {
      case ConnectivityStatus.online:
        return SaturdayColors.success.withValues(alpha: 0.1);
      case ConnectivityStatus.offline:
      case ConnectivityStatus.setupRequired:
        return SaturdayColors.secondary.withValues(alpha: 0.1);
    }
  }

  Color get _avatarIconColor {
    switch (device.connectivityStatus) {
      case ConnectivityStatus.online:
        return SaturdayColors.success;
      case ConnectivityStatus.offline:
      case ConnectivityStatus.setupRequired:
        return SaturdayColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _avatarBackgroundColor,
        child: Icon(
          device.isHub ? Icons.router : Icons.inventory_2_outlined,
          color: _avatarIconColor,
          size: 20,
        ),
      ),
      title: Text(device.name),
      subtitle: Text(device.isHub ? 'Hub' : 'Crate'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (device.isCrate && device.batteryLevel != null)
            BatteryIconOnly(level: device.batteryLevel),
          const SizedBox(width: 8),
          ConnectivityStatusBadge.fromDevice(
            device: device,
            showLabel: false,
            size: 10,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// A mini device card for showing device count summaries.
class DeviceMiniCard extends StatelessWidget {
  final int hubCount;
  final int crateCount;
  final int onlineCount;
  final VoidCallback? onTap;

  const DeviceMiniCard({
    super.key,
    required this.hubCount,
    required this.crateCount,
    required this.onlineCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final totalCount = hubCount + crateCount;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.largeRadius,
        child: Padding(
          padding: Spacing.cardPadding,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: SaturdayColors.primaryDark.withValues(alpha: 0.1),
                  borderRadius: AppRadius.mediumRadius,
                ),
                child: const Icon(
                  Icons.devices,
                  color: SaturdayColors.primaryDark,
                  size: 24,
                ),
              ),
              Spacing.horizontalGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Devices',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalCount device${totalCount == 1 ? '' : 's'} • $onlineCount online',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: SaturdayColors.secondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
