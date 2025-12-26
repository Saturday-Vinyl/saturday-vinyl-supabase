import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/serial_connection_state.dart';
import 'package:saturday_app/providers/uhf_rfid_provider.dart';
import 'package:saturday_app/widgets/tags/rfid_connection_modal.dart';

/// Compact status indicator widget for RFID module connection
///
/// Shows a colored dot and status text. Clickable to open the connection modal.
class RfidModuleStatus extends ConsumerWidget {
  /// Whether to show the text label
  final bool showLabel;

  /// Whether to use compact mode (just the dot)
  final bool compact;

  const RfidModuleStatus({
    super.key,
    this.showLabel = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only show on desktop platforms
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return const SizedBox.shrink();
    }

    final connectionState = ref.watch(uhfCurrentConnectionStateProvider);

    return InkWell(
      onTap: () => RfidConnectionModal.show(context),
      borderRadius: BorderRadius.circular(compact ? 12 : 20),
      child: Tooltip(
        message: _getTooltipMessage(connectionState),
        child: compact
            ? _buildCompactIndicator(connectionState)
            : _buildFullIndicator(context, connectionState),
      ),
    );
  }

  Widget _buildCompactIndicator(SerialConnectionState connectionState) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: _buildStatusDot(connectionState, size: 12),
    );
  }

  Widget _buildFullIndicator(
      BuildContext context, SerialConnectionState connectionState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(connectionState).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _getStatusColor(connectionState).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusDot(connectionState, size: 10),
          if (showLabel) ...[
            const SizedBox(width: 8),
            Text(
              'RFID: ${_getStatusText(connectionState)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _getStatusColor(connectionState),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Icon(
            Icons.settings,
            size: 14,
            color: _getStatusColor(connectionState),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDot(SerialConnectionState connectionState,
      {double size = 10}) {
    final color = _getStatusColor(connectionState);
    final isConnecting =
        connectionState.status == SerialConnectionStatus.connecting;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: isConnecting
          ? SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  color.withValues(alpha: 0.5),
                ),
              ),
            )
          : null,
    );
  }

  Color _getStatusColor(SerialConnectionState connectionState) {
    switch (connectionState.status) {
      case SerialConnectionStatus.connected:
        return SaturdayColors.success;
      case SerialConnectionStatus.connecting:
        return Colors.orange;
      case SerialConnectionStatus.error:
        return SaturdayColors.error;
      case SerialConnectionStatus.disconnected:
        return SaturdayColors.secondaryGrey;
    }
  }

  String _getStatusText(SerialConnectionState connectionState) {
    switch (connectionState.status) {
      case SerialConnectionStatus.connected:
        return 'Ready';
      case SerialConnectionStatus.connecting:
        return 'Connecting';
      case SerialConnectionStatus.error:
        return 'Error';
      case SerialConnectionStatus.disconnected:
        return 'Off';
    }
  }

  String _getTooltipMessage(SerialConnectionState connectionState) {
    final status = connectionState.status;
    final port = connectionState.portName;

    switch (status) {
      case SerialConnectionStatus.connected:
        return 'RFID Module Connected${port != null ? ' ($port)' : ''}\nClick to configure';
      case SerialConnectionStatus.connecting:
        return 'Connecting to RFID Module...\nClick to configure';
      case SerialConnectionStatus.error:
        final error = connectionState.errorMessage ?? 'Unknown error';
        return 'RFID Module Error: $error\nClick to configure';
      case SerialConnectionStatus.disconnected:
        return 'RFID Module Disconnected\nClick to configure';
    }
  }
}

/// Status indicator specifically for the app bar
class RfidAppBarStatus extends ConsumerWidget {
  const RfidAppBarStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only show on desktop platforms
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return const SizedBox.shrink();
    }

    final connectionState = ref.watch(uhfCurrentConnectionStateProvider);

    return IconButton(
      icon: Stack(
        children: [
          const Icon(Icons.settings_input_antenna),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _getStatusColor(connectionState),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      ),
      tooltip: _getTooltipMessage(connectionState),
      onPressed: () => RfidConnectionModal.show(context),
    );
  }

  Color _getStatusColor(SerialConnectionState connectionState) {
    switch (connectionState.status) {
      case SerialConnectionStatus.connected:
        return SaturdayColors.success;
      case SerialConnectionStatus.connecting:
        return Colors.orange;
      case SerialConnectionStatus.error:
        return SaturdayColors.error;
      case SerialConnectionStatus.disconnected:
        return SaturdayColors.secondaryGrey;
    }
  }

  String _getTooltipMessage(SerialConnectionState connectionState) {
    switch (connectionState.status) {
      case SerialConnectionStatus.connected:
        return 'RFID Module: Connected';
      case SerialConnectionStatus.connecting:
        return 'RFID Module: Connecting...';
      case SerialConnectionStatus.error:
        return 'RFID Module: Error';
      case SerialConnectionStatus.disconnected:
        return 'RFID Module: Disconnected';
    }
  }
}
