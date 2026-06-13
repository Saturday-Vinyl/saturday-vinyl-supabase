import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/styles.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/device.dart';
import 'package:saturday_consumer_app/widgets/common/product_image.dart';
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

  bool get _hasTelemetry =>
      device.temperatureC != null || device.humidityPct != null;

  String get _telemetrySummary {
    final parts = <String>[];
    if (device.temperatureC != null) {
      final tempF = (device.temperatureC! * 9 / 5 + 32).round();
      parts.add('$tempF°F');
    }
    if (device.humidityPct != null) {
      parts.add('${device.humidityPct!.round()}% humidity');
    }
    return parts.join(' • ');
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

  Color _iconBackgroundColor(SaturdayColorTokens colors) => colors.borderQuiet;

  Color _iconColor(SaturdayColorTokens colors) {
    switch (device.connectivityStatus) {
      case ConnectivityStatus.online:
      case ConnectivityStatus.setupRequired:
        return colors.ink;
      case ConnectivityStatus.offline:
        return colors.inkTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final iconColor = _iconColor(colors);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.largeRadius,
        child: Padding(
          padding: Spacing.cardPadding,
          child: Row(
            children: [
              // Device image or icon
              if (device.hasProductImageData)
                ProductImageWidget(
                  device: device,
                  size: 48,
                  fallback: Icon(
                    _deviceIcon,
                    color: iconColor,
                    size: 24,
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _iconBackgroundColor(colors),
                    borderRadius: AppRadius.mediumRadius,
                  ),
                  child: Icon(
                    _deviceIcon,
                    color: iconColor,
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
                    if (device.isCrate && _hasTelemetry) ...[
                      const SizedBox(height: 2),
                      Text(
                        _telemetrySummary,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.inkSecondary,
                            ),
                      ),
                    ],
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
                      isCharging: device.isCharging == true,
                      size: 18,
                    ),
                  ],
                ],
              ),
              Spacing.horizontalGapSm,
              Icon(
                Icons.chevron_right,
                color: colors.inkTertiary,
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

  Color _avatarBackgroundColor(SaturdayColorTokens colors) =>
      colors.borderQuiet;

  Color _avatarIconColor(SaturdayColorTokens colors) {
    switch (device.connectivityStatus) {
      case ConnectivityStatus.online:
      case ConnectivityStatus.setupRequired:
        return colors.ink;
      case ConnectivityStatus.offline:
        return colors.inkTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final iconColor = _avatarIconColor(colors);
    return ListTile(
      leading: device.hasProductImageData
          ? ProductImageWidget(
              device: device,
              size: 40,
              fallback: Icon(
                device.isHub ? Icons.router : Icons.inventory_2_outlined,
                color: iconColor,
                size: 20,
              ),
            )
          : CircleAvatar(
              backgroundColor: _avatarBackgroundColor(colors),
              child: Icon(
                device.isHub ? Icons.router : Icons.inventory_2_outlined,
                color: iconColor,
                size: 20,
              ),
            ),
      title: Text(device.name),
      subtitle: Text(device.isHub ? 'Hub' : 'Crate'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (device.isCrate && device.batteryLevel != null)
            BatteryIconOnly(
              level: device.batteryLevel,
              isCharging: device.isCharging == true,
            ),
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
    final colors = SaturdayColorTokens.of(context);
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
                  color: colors.borderQuiet,
                  borderRadius: AppRadius.mediumRadius,
                ),
                child: Icon(
                  Icons.devices,
                  color: colors.ink,
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
                color: colors.inkTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
