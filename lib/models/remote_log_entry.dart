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
    if (data.isEmpty) return '{}';
    return jsonEncode(data);
  }

  String _formatCommandSent() {
    return command ?? 'unknown';
  }

  String _formatCommandAck() {
    if (data.isNotEmpty) return jsonEncode(data);
    return 'ACK: ${command ?? commandId ?? 'unknown'}';
  }

  String _formatCommandResult() {
    if (data.isNotEmpty) return jsonEncode(data);
    final status = commandStatus?.databaseValue ?? 'unknown';
    return '$status: ${command ?? commandId ?? 'unknown'}';
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

    // Use the telemetry JSONB column (raw device POST payload)
    final telemetry = json['telemetry'];
    final Map<String, dynamic> data = telemetry is Map<String, dynamic>
        ? Map<String, dynamic>.from(telemetry)
        : {};

    return RemoteLogEntry(
      id: json['id'] as String,
      type: entryType,
      timestamp: DateTime.parse(json['created_at'] as String),
      macAddress: json['mac_address'] as String,
      commandId: json['command_id'] as String?,
      data: data,
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
