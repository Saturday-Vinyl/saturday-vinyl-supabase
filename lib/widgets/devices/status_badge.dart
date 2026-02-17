import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/theme.dart';
import 'package:saturday_consumer_app/models/device.dart';

/// A badge displaying the device's connectivity status.
///
/// Shows a colored dot indicator with optional label text.
/// Use [ConnectivityStatusBadge] for heartbeat-aware status display.
class StatusBadge extends StatelessWidget {
  final DeviceStatus status;
  final bool showLabel;
  final double size;

  const StatusBadge({
    super.key,
    required this.status,
    this.showLabel = true,
    this.size = 8,
  });

  Color get _statusColor {
    switch (status) {
      case DeviceStatus.online:
        return SaturdayColors.success;
      case DeviceStatus.offline:
        return SaturdayColors.secondary;
      case DeviceStatus.setupRequired:
        return SaturdayColors.warning;
    }
  }

  String get _statusLabel {
    switch (status) {
      case DeviceStatus.online:
        return 'Online';
      case DeviceStatus.offline:
        return 'Offline';
      case DeviceStatus.setupRequired:
        return 'Setup Required';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _statusColor,
            shape: BoxShape.circle,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            _statusLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _statusColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ],
    );
  }
}

/// A badge displaying the device's connectivity status based on heartbeat staleness.
///
/// This is the preferred widget for showing device status as it accounts for
/// devices that may have disconnected without sending an explicit offline signal.
class ConnectivityStatusBadge extends StatelessWidget {
  final ConnectivityStatus connectivityStatus;
  final bool showLabel;
  final double size;

  const ConnectivityStatusBadge({
    super.key,
    required this.connectivityStatus,
    this.showLabel = true,
    this.size = 8,
  });

  /// Create from a Device, using its derived connectivity status.
  factory ConnectivityStatusBadge.fromDevice({
    Key? key,
    required Device device,
    bool showLabel = true,
    double size = 8,
  }) {
    return ConnectivityStatusBadge(
      key: key,
      connectivityStatus: device.connectivityStatus,
      showLabel: showLabel,
      size: size,
    );
  }

  Color get _statusColor {
    switch (connectivityStatus) {
      case ConnectivityStatus.online:
        return SaturdayColors.success;
      case ConnectivityStatus.offline:
        return SaturdayColors.secondary;
      case ConnectivityStatus.setupRequired:
        return SaturdayColors.warning;
    }
  }

  String get _statusLabel {
    switch (connectivityStatus) {
      case ConnectivityStatus.online:
        return 'Online';
      case ConnectivityStatus.offline:
        return 'Offline';
      case ConnectivityStatus.setupRequired:
        return 'Setup Required';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _statusColor,
            shape: BoxShape.circle,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            _statusLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _statusColor,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ],
    );
  }
}

/// A larger status badge with background for more prominent display.
class StatusChip extends StatelessWidget {
  final DeviceStatus status;

  const StatusChip({
    super.key,
    required this.status,
  });

  Color get _statusColor {
    switch (status) {
      case DeviceStatus.online:
        return SaturdayColors.success;
      case DeviceStatus.offline:
        return SaturdayColors.secondary;
      case DeviceStatus.setupRequired:
        return SaturdayColors.warning;
    }
  }

  String get _statusLabel {
    switch (status) {
      case DeviceStatus.online:
        return 'Online';
      case DeviceStatus.offline:
        return 'Offline';
      case DeviceStatus.setupRequired:
        return 'Setup Required';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _statusLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _statusColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// A larger connectivity status chip with background for more prominent display.
///
/// This is the preferred widget for showing device status as it accounts for
/// devices that may have disconnected without sending an explicit offline signal.
class ConnectivityStatusChip extends StatelessWidget {
  final ConnectivityStatus connectivityStatus;

  const ConnectivityStatusChip({
    super.key,
    required this.connectivityStatus,
  });

  /// Create from a Device, using its derived connectivity status.
  factory ConnectivityStatusChip.fromDevice({
    Key? key,
    required Device device,
  }) {
    return ConnectivityStatusChip(
      key: key,
      connectivityStatus: device.connectivityStatus,
    );
  }

  Color get _statusColor {
    switch (connectivityStatus) {
      case ConnectivityStatus.online:
        return SaturdayColors.success;
      case ConnectivityStatus.offline:
        return SaturdayColors.secondary;
      case ConnectivityStatus.setupRequired:
        return SaturdayColors.warning;
    }
  }

  String get _statusLabel {
    switch (connectivityStatus) {
      case ConnectivityStatus.online:
        return 'Online';
      case ConnectivityStatus.offline:
        return 'Offline';
      case ConnectivityStatus.setupRequired:
        return 'Setup Required';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _statusLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _statusColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
