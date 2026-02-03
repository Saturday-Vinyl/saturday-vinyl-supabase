import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/device_command.dart';

/// Type of remote log entry
enum RemoteLogEntryType {
  /// Regular device heartbeat (telemetry)
  heartbeat,

  /// Command sent from admin to device
  commandSent,

  /// Device acknowledged receiving command
  commandAck,

  /// Device reported command result (completed/failed)
  commandResult,
}

/// A unified log entry for remote device monitoring
///
/// Combines data from device_heartbeats and device_commands tables
/// into a single model for display in the remote log viewer.
class RemoteLogEntry extends Equatable {
  final String id;
  final RemoteLogEntryType type;
  final DateTime timestamp;
  final String macAddress;

  /// For command-related entries
  final String? commandId;
  final String? command;
  final DeviceCommandStatus? commandStatus;

  /// Raw data payload
  final Map<String, dynamic> data;

  const RemoteLogEntry({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.macAddress,
    this.commandId,
    this.command,
    this.commandStatus,
    this.data = const {},
  });

  /// Get formatted display text for log viewer
  String get displayText {
    switch (type) {
      case RemoteLogEntryType.heartbeat:
        return _formatHeartbeat();
      case RemoteLogEntryType.commandSent:
        return _formatCommandSent();
      case RemoteLogEntryType.commandAck:
        return _formatCommandAck();
      case RemoteLogEntryType.commandResult:
        return _formatCommandResult();
    }
  }

  String _formatHeartbeat() {
    // Show key telemetry fields
    final buffer = StringBuffer();
    if (data['firmware_version'] != null) {
      buffer.write('v${data['firmware_version']} ');
    }
    if (data['uptime_sec'] != null) {
      buffer.write('up:${_formatUptime(data['uptime_sec'] as int)} ');
    }
    if (data['free_heap'] != null) {
      buffer.write('heap:${_formatBytes(data['free_heap'] as int)} ');
    }
    if (data['wifi_rssi'] != null) {
      buffer.write('rssi:${data['wifi_rssi']}dBm');
    }
    return buffer.isEmpty ? jsonEncode(data) : buffer.toString().trim();
  }

  String _formatCommandSent() {
    final buffer = StringBuffer(command ?? 'unknown');
    if (data['capability'] != null) {
      buffer.write(' (${data['capability']})');
    }
    if (data['test_name'] != null) {
      buffer.write(' test:${data['test_name']}');
    }
    return buffer.toString();
  }

  String _formatCommandAck() {
    return 'ACK: ${command ?? commandId ?? 'unknown'}';
  }

  String _formatCommandResult() {
    final status = data['status'] ?? commandStatus?.databaseValue ?? 'unknown';
    final buffer = StringBuffer('$status: ${command ?? commandId ?? 'unknown'}');
    if (data['error_message'] != null) {
      buffer.write(' - ${data['error_message']}');
    }
    return buffer.toString();
  }

  String _formatUptime(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) return '${seconds ~/ 3600}h';
    return '${seconds ~/ 86400}d';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  /// Get prefix indicator for log display
  String get prefix {
    switch (type) {
      case RemoteLogEntryType.heartbeat:
        return '[HB]';
      case RemoteLogEntryType.commandSent:
        return '[TX]';
      case RemoteLogEntryType.commandAck:
        return '[ACK]';
      case RemoteLogEntryType.commandResult:
        return '[RX]';
    }
  }

  /// Check if this is an error entry
  bool get isError =>
      type == RemoteLogEntryType.commandResult &&
      commandStatus == DeviceCommandStatus.failed;

  /// Create from device_heartbeats row
  factory RemoteLogEntry.fromHeartbeat(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'status';

    RemoteLogEntryType entryType;
    if (type == 'command_ack') {
      entryType = RemoteLogEntryType.commandAck;
    } else if (type == 'command_result') {
      entryType = RemoteLogEntryType.commandResult;
    } else {
      entryType = RemoteLogEntryType.heartbeat;
    }

    return RemoteLogEntry(
      id: json['id'] as String,
      type: entryType,
      timestamp: DateTime.parse(json['received_at'] as String),
      macAddress: json['mac_address'] as String,
      commandId: json['command_id'] as String?,
      data: json['heartbeat_data'] != null
          ? Map<String, dynamic>.from(json['heartbeat_data'] as Map)
          : {},
    );
  }

  /// Create from device_commands row
  factory RemoteLogEntry.fromCommand(Map<String, dynamic> json) {
    final status =
        DeviceCommandStatusExtension.fromString(json['status'] as String?);

    // Determine entry type based on command status
    RemoteLogEntryType entryType;
    if (status == DeviceCommandStatus.completed ||
        status == DeviceCommandStatus.failed) {
      entryType = RemoteLogEntryType.commandResult;
    } else if (status == DeviceCommandStatus.acknowledged) {
      entryType = RemoteLogEntryType.commandAck;
    } else {
      entryType = RemoteLogEntryType.commandSent;
    }

    return RemoteLogEntry(
      id: json['id'] as String,
      type: entryType,
      timestamp: DateTime.parse(json['created_at'] as String),
      macAddress: json['mac_address'] as String,
      commandId: json['id'] as String,
      command: json['command'] as String?,
      commandStatus: status,
      data: {
        if (json['capability'] != null) 'capability': json['capability'],
        if (json['test_name'] != null) 'test_name': json['test_name'],
        if (json['parameters'] != null) 'parameters': json['parameters'],
        if (json['result'] != null) 'result': json['result'],
        if (json['error_message'] != null)
          'error_message': json['error_message'],
      },
    );
  }

  @override
  List<Object?> get props => [
        id,
        type,
        timestamp,
        macAddress,
        commandId,
        command,
        commandStatus,
        data,
      ];

  @override
  String toString() => 'RemoteLogEntry($prefix $displayText)';
}
