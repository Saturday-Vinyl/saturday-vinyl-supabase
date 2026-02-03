import 'package:equatable/equatable.dart';

/// Status of a device command
enum DeviceCommandStatus {
  pending,
  sent,
  acknowledged,
  completed,
  failed,
  expired,
}

/// Extension to convert DeviceCommandStatus to/from database string
extension DeviceCommandStatusExtension on DeviceCommandStatus {
  String get databaseValue {
    switch (this) {
      case DeviceCommandStatus.pending:
        return 'pending';
      case DeviceCommandStatus.sent:
        return 'sent';
      case DeviceCommandStatus.acknowledged:
        return 'acknowledged';
      case DeviceCommandStatus.completed:
        return 'completed';
      case DeviceCommandStatus.failed:
        return 'failed';
      case DeviceCommandStatus.expired:
        return 'expired';
    }
  }

  static DeviceCommandStatus fromString(String? value) {
    switch (value) {
      case 'pending':
        return DeviceCommandStatus.pending;
      case 'sent':
        return DeviceCommandStatus.sent;
      case 'acknowledged':
        return DeviceCommandStatus.acknowledged;
      case 'completed':
        return DeviceCommandStatus.completed;
      case 'failed':
        return DeviceCommandStatus.failed;
      case 'expired':
        return DeviceCommandStatus.expired;
      default:
        return DeviceCommandStatus.pending;
    }
  }
}

/// Represents a command sent to a device via websocket
///
/// Commands are stored in the device_commands table and broadcast
/// to devices via Supabase Realtime.
class DeviceCommand extends Equatable {
  final String id;

  /// Target device MAC address
  final String macAddress;

  /// Command type (e.g., get_status, run_test, reboot)
  final String command;

  /// Optional capability this command relates to
  final String? capability;

  /// Optional test name for run_test commands
  final String? testName;

  /// Command parameters
  final Map<String, dynamic> parameters;

  /// Priority (higher = more urgent)
  final int priority;

  /// Command lifecycle status
  final DeviceCommandStatus status;

  /// Optional expiration time
  final DateTime? expiresAt;

  /// Result from device (for completed commands)
  final Map<String, dynamic>? result;

  /// Error message (for failed commands)
  final String? errorMessage;

  /// Number of retries
  final int retryCount;

  /// Timestamps
  final DateTime createdAt;
  final DateTime updatedAt;

  /// User who created the command
  final String? createdBy;

  const DeviceCommand({
    required this.id,
    required this.macAddress,
    required this.command,
    this.capability,
    this.testName,
    this.parameters = const {},
    this.priority = 0,
    this.status = DeviceCommandStatus.pending,
    this.expiresAt,
    this.result,
    this.errorMessage,
    this.retryCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  /// Check if command is terminal (no more updates expected)
  bool get isTerminal =>
      status == DeviceCommandStatus.completed ||
      status == DeviceCommandStatus.failed ||
      status == DeviceCommandStatus.expired;

  /// Check if command is pending acknowledgement
  bool get isPending =>
      status == DeviceCommandStatus.pending ||
      status == DeviceCommandStatus.sent;

  /// Get display name for the command
  String get displayName {
    if (command == 'run_test' && testName != null) {
      return 'Test: $testName';
    }
    return command.replaceAll('_', ' ');
  }

  /// Create from JSON
  factory DeviceCommand.fromJson(Map<String, dynamic> json) {
    return DeviceCommand(
      id: json['id'] as String,
      macAddress: json['mac_address'] as String,
      command: json['command'] as String,
      capability: json['capability'] as String?,
      testName: json['test_name'] as String?,
      parameters: json['parameters'] != null
          ? Map<String, dynamic>.from(json['parameters'] as Map)
          : {},
      priority: json['priority'] as int? ?? 0,
      status: DeviceCommandStatusExtension.fromString(json['status'] as String?),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      result: json['result'] != null
          ? Map<String, dynamic>.from(json['result'] as Map)
          : null,
      errorMessage: json['error_message'] as String?,
      retryCount: json['retry_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      createdBy: json['created_by'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'mac_address': macAddress,
      'command': command,
      'capability': capability,
      'test_name': testName,
      'parameters': parameters,
      'priority': priority,
      'status': status.databaseValue,
      'expires_at': expiresAt?.toIso8601String(),
      'result': result,
      'error_message': errorMessage,
      'retry_count': retryCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'created_by': createdBy,
    };
  }

  /// Convert to JSON for insertion (without id, timestamps, result fields)
  Map<String, dynamic> toInsertJson() {
    return {
      'mac_address': macAddress,
      'command': command,
      if (capability != null) 'capability': capability,
      if (testName != null) 'test_name': testName,
      'parameters': parameters,
      'priority': priority,
      if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      if (createdBy != null) 'created_by': createdBy,
    };
  }

  /// Copy with method for immutability
  DeviceCommand copyWith({
    String? id,
    String? macAddress,
    String? command,
    String? capability,
    String? testName,
    Map<String, dynamic>? parameters,
    int? priority,
    DeviceCommandStatus? status,
    DateTime? expiresAt,
    Map<String, dynamic>? result,
    String? errorMessage,
    int? retryCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return DeviceCommand(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      command: command ?? this.command,
      capability: capability ?? this.capability,
      testName: testName ?? this.testName,
      parameters: parameters ?? this.parameters,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      expiresAt: expiresAt ?? this.expiresAt,
      result: result ?? this.result,
      errorMessage: errorMessage ?? this.errorMessage,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        macAddress,
        command,
        capability,
        testName,
        parameters,
        priority,
        status,
        expiresAt,
        result,
        errorMessage,
        retryCount,
        createdAt,
        updatedAt,
        createdBy,
      ];

  @override
  String toString() =>
      'DeviceCommand(id: $id, command: $command, status: $status)';
}
