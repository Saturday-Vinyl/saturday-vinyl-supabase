import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

/// Log level for activity entries
enum LogLevel {
  info,
  success,
  warning,
  error,
}

/// A single entry in the activity log
class ActivityLogEntry extends Equatable {
  final String id;
  final DateTime timestamp;
  final String message;
  final LogLevel level;
  final String? relatedEpc;

  ActivityLogEntry({
    String? id,
    DateTime? timestamp,
    required this.message,
    required this.level,
    this.relatedEpc,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  /// Create an info level entry
  factory ActivityLogEntry.info(String message, {String? relatedEpc}) {
    return ActivityLogEntry(
      message: message,
      level: LogLevel.info,
      relatedEpc: relatedEpc,
    );
  }

  /// Create a success level entry
  factory ActivityLogEntry.success(String message, {String? relatedEpc}) {
    return ActivityLogEntry(
      message: message,
      level: LogLevel.success,
      relatedEpc: relatedEpc,
    );
  }

  /// Create a warning level entry
  factory ActivityLogEntry.warning(String message, {String? relatedEpc}) {
    return ActivityLogEntry(
      message: message,
      level: LogLevel.warning,
      relatedEpc: relatedEpc,
    );
  }

  /// Create an error level entry
  factory ActivityLogEntry.error(String message, {String? relatedEpc}) {
    return ActivityLogEntry(
      message: message,
      level: LogLevel.error,
      relatedEpc: relatedEpc,
    );
  }

  ActivityLogEntry copyWith({
    String? id,
    DateTime? timestamp,
    String? message,
    LogLevel? level,
    String? relatedEpc,
  }) {
    return ActivityLogEntry(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      message: message ?? this.message,
      level: level ?? this.level,
      relatedEpc: relatedEpc ?? this.relatedEpc,
    );
  }

  @override
  List<Object?> get props => [id, timestamp, message, level, relatedEpc];

  @override
  String toString() {
    return 'ActivityLogEntry(id: $id, level: $level, message: $message)';
  }
}
