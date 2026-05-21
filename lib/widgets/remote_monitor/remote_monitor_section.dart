import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:saturday_app/config/theme.dart';
import 'package:saturday_app/models/device.dart';
import 'package:saturday_app/models/heartbeat_chart_data.dart';
import 'package:saturday_app/models/remote_log_entry.dart';
import 'package:saturday_app/providers/remote_monitor_provider.dart';
import 'package:saturday_app/widgets/remote_monitor/remote_command_panel.dart';
import 'package:saturday_app/widgets/remote_monitor/remote_log_display.dart';

/// Main container widget for remote device monitoring
///
/// Provides log display, command panel, and monitoring controls.
/// All devices can view heartbeats (read-only).
/// Devices with websocket capability or hub relay can send commands.
class RemoteMonitorSection extends ConsumerStatefulWidget {
  final String unitId;

  /// All devices to monitor (for heartbeats)
  final List<Device> devices;

  /// Devices that can receive commands (websocket or hub relay)
  final List<Device> commandableDevices;

  const RemoteMonitorSection({
    super.key,
    required this.unitId,
    required this.devices,
    this.commandableDevices = const [],
  });

  @override
  ConsumerState<RemoteMonitorSection> createState() =>
      _RemoteMonitorSectionState();
}

class _RemoteMonitorSectionState extends ConsumerState<RemoteMonitorSection> {
  final _logScrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    // Initialize the monitor with devices
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(remoteMonitorProvider(widget.unitId).notifier)
          .initialize(widget.devices);
    });
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final monitorState = ref.watch(remoteMonitorProvider(widget.unitId));

    // Auto-scroll when new entries arrive
    ref.listen(remoteMonitorProvider(widget.unitId), (previous, next) {
      if (_autoScroll &&
          previous != null &&
          next.logEntries.length > previous.logEntries.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_logScrollController.hasClients) {
            _logScrollController.animateTo(
              _logScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(context, monitorState),
            const SizedBox(height: 16),

            // Latest reset reason per device (if reported)
            _buildResetReasonRow(context, monitorState),

            // Error message
            if (monitorState.error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SaturdayColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: SaturdayColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: SaturdayColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        monitorState.error!,
                        style: TextStyle(color: SaturdayColors.error),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Log display
            SizedBox(
              height: 300,
              child: RemoteLogDisplay(
                entries: monitorState.logEntries,
                scrollController: _logScrollController,
              ),
            ),
            const SizedBox(height: 16),

            // Command panel (only for devices with websocket capability)
            if (widget.commandableDevices.isNotEmpty)
              RemoteCommandPanel(
                unitId: widget.unitId,
                devices: widget.commandableDevices,
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.grey[500], size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Commands unavailable - no devices with remote command capability',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, RemoteMonitorState state) {
    return Row(
      children: [
        // Status indicator
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: state.isSubscribed ? SaturdayColors.success : Colors.grey,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Remote Monitor',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(width: 8),
        Text(
          state.isSubscribed
              ? '${state.devices.length} device${state.devices.length != 1 ? 's' : ''}'
              : 'Not connected',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: SaturdayColors.secondaryGrey,
              ),
        ),
        const Spacer(),

        // Auto-scroll toggle
        IconButton(
          onPressed: () => setState(() => _autoScroll = !_autoScroll),
          icon: Icon(
            _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
            size: 20,
          ),
          tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
          color: _autoScroll ? SaturdayColors.info : Colors.grey,
        ),

        // Copy logs button
        IconButton(
          onPressed: state.logEntries.isNotEmpty
              ? () => _copyLogs(context, state)
              : null,
          icon: const Icon(Icons.copy, size: 20),
          tooltip: 'Copy logs',
        ),

        // Clear logs button
        IconButton(
          onPressed: state.logEntries.isNotEmpty
              ? () => ref
                  .read(remoteMonitorProvider(widget.unitId).notifier)
                  .clearLogs()
              : null,
          icon: const Icon(Icons.clear_all, size: 20),
          tooltip: 'Clear logs',
        ),

        const SizedBox(width: 8),

        // Start/Stop button
        FilledButton.icon(
          onPressed: () => _toggleMonitoring(state),
          icon: Icon(
            state.isSubscribed ? Icons.stop : Icons.play_arrow,
            size: 18,
          ),
          label: Text(state.isSubscribed ? 'Stop' : 'Start'),
          style: FilledButton.styleFrom(
            backgroundColor:
                state.isSubscribed ? Colors.orange : SaturdayColors.success,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }

  /// Decode the most recent heartbeat per device and surface its reset_reason.
  /// Only renders devices whose latest heartbeat actually carries the field.
  Widget _buildResetReasonRow(BuildContext context, RemoteMonitorState state) {
    final latestByMac = <String, RemoteLogEntry>{};
    for (final entry in state.logEntries.reversed) {
      if (entry.type != RemoteLogEntryType.heartbeat) continue;
      if (latestByMac.containsKey(entry.macAddress)) continue;
      latestByMac[entry.macAddress] = entry;
      if (latestByMac.length == state.devices.length) break;
    }

    final chips = <Widget>[];
    for (final device in state.devices) {
      final entry = latestByMac[device.macAddress];
      final code = entry?.data['reset_reason'];
      if (code is! int) continue;
      final reason = ResetReason.fromCode(code);
      chips.add(_buildResetReasonChip(context, device, reason));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: chips,
      ),
    );
  }

  Widget _buildResetReasonChip(
    BuildContext context,
    Device device,
    ResetReason reason,
  ) {
    final color = switch (reason.severity) {
      ResetSeverity.alert => SaturdayColors.error,
      ResetSeverity.warning => SaturdayColors.warning,
      ResetSeverity.normal => SaturdayColors.info,
    };

    final macSuffix = device.macAddress.length >= 5
        ? device.macAddress.substring(device.macAddress.length - 5)
        : device.macAddress;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restart_alt, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '…$macSuffix',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: SaturdayColors.secondaryGrey,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Last boot: ${reason.label}',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMonitoring(RemoteMonitorState state) {
    final notifier = ref.read(remoteMonitorProvider(widget.unitId).notifier);
    if (state.isSubscribed) {
      notifier.stopMonitoring();
    } else {
      notifier.startMonitoring();
    }
  }

  void _copyLogs(BuildContext context, RemoteMonitorState state) {
    final buffer = StringBuffer();
    for (final entry in state.logEntries) {
      buffer.writeln('${entry.timestamp.toIso8601String()} ${entry.prefix} ${entry.displayText}');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied ${state.logEntries.length} log entries'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
