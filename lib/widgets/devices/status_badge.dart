import 'package:flutter/material.dart';
import 'package:saturday_consumer_app/config/tokens/tokens.dart';
import 'package:saturday_consumer_app/models/device.dart';

/// Resolve a connectivity status to a Saturday token tone.
///
/// Per the Saturday constitution, state is communicated by text, position,
/// and tonal weight — not by saturated semantic color. Online uses `ink`
/// (present); offline uses `inkTertiary` (muted); setup-required uses `ink`
/// because the label itself is the call to action.
Color _toneForStatus(SaturdayColorTokens c, ConnectivityStatus status) {
  switch (status) {
    case ConnectivityStatus.online:
    case ConnectivityStatus.setupRequired:
      return c.ink;
    case ConnectivityStatus.offline:
      return c.inkTertiary;
  }
}

Color _toneForLegacyStatus(SaturdayColorTokens c, DeviceStatus status) {
  switch (status) {
    case DeviceStatus.online:
    case DeviceStatus.setupRequired:
      return c.ink;
    case DeviceStatus.offline:
      return c.inkTertiary;
  }
}

/// A badge displaying the device's connectivity status.
///
/// Shows a tonal dot indicator with optional label text.
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

  String get _statusLabel {
    switch (status) {
      case DeviceStatus.online:
        return 'Online';
      case DeviceStatus.offline:
        return 'Offline';
      case DeviceStatus.setupRequired:
        return 'Setup required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final tone = _toneForLegacyStatus(colors, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: tone,
            shape: BoxShape.circle,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            _statusLabel,
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

  String get _statusLabel {
    switch (connectivityStatus) {
      case ConnectivityStatus.online:
        return 'Online';
      case ConnectivityStatus.offline:
        return 'Offline';
      case ConnectivityStatus.setupRequired:
        return 'Setup required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final tone = _toneForStatus(colors, connectivityStatus);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: tone,
            shape: BoxShape.circle,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            _statusLabel,
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

/// A larger status badge with background for more prominent display.
class StatusChip extends StatelessWidget {
  final DeviceStatus status;

  const StatusChip({
    super.key,
    required this.status,
  });

  String get _statusLabel {
    switch (status) {
      case DeviceStatus.online:
        return 'Online';
      case DeviceStatus.offline:
        return 'Offline';
      case DeviceStatus.setupRequired:
        return 'Setup required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final tone = _toneForLegacyStatus(colors, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.paperElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderQuiet),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: tone,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _statusLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tone,
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

  String get _statusLabel {
    switch (connectivityStatus) {
      case ConnectivityStatus.online:
        return 'Online';
      case ConnectivityStatus.offline:
        return 'Offline';
      case ConnectivityStatus.setupRequired:
        return 'Setup required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = SaturdayColorTokens.of(context);
    final tone = _toneForStatus(colors, connectivityStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.paperElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderQuiet),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: tone,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _statusLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tone,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
