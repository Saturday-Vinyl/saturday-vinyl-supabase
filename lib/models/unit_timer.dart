import 'package:equatable/equatable.dart';

/// Status of a unit timer
enum UnitTimerStatus {
  active,
  completed,
  cancelled;

  String toJson() => name;

  static UnitTimerStatus fromJson(String value) {
    return UnitTimerStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UnitTimerStatus.active,
    );
  }
}

/// UnitTimer model representing an active timer instance for a production unit
///
/// When a worker starts a timer from a production step, a UnitTimer is created
/// to track when it was started, when it expires, and its current status.
class UnitTimer extends Equatable {
  final String id; // UUID
  final String unitId; // Foreign key to units table
  final String stepTimerId; // Foreign key to StepTimer (configuration)
  final DateTime startedAt; // When the timer was started
  final DateTime expiresAt; // When the timer should expire
  final DateTime? completedAt; // When the timer was acknowledged/completed
  final UnitTimerStatus status; // Current status
  final DateTime createdAt;
  final DateTime updatedAt;

  const UnitTimer({
    required this.id,
    required this.unitId,
    required this.stepTimerId,
    required this.startedAt,
    required this.expiresAt,
    this.completedAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create UnitTimer from JSON
  factory UnitTimer.fromJson(Map<String, dynamic> json) {
    return UnitTimer(
      id: json['id'] as String,
      unitId: json['unit_id'] as String,
      stepTimerId: json['step_timer_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      expiresAt: DateTime.parse(json['expires_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      status: UnitTimerStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert UnitTimer to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'unit_id': unitId,
      'step_timer_id': stepTimerId,
      'started_at': startedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'status': status.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of UnitTimer with updated fields
  UnitTimer copyWith({
    String? id,
    String? unitId,
    String? stepTimerId,
    DateTime? startedAt,
    DateTime? expiresAt,
    DateTime? completedAt,
    UnitTimerStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UnitTimer(
      id: id ?? this.id,
      unitId: unitId ?? this.unitId,
      stepTimerId: stepTimerId ?? this.stepTimerId,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      completedAt: completedAt ?? this.completedAt,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Check if the timer has expired
  bool get isExpired {
    return status == UnitTimerStatus.active &&
        DateTime.now().toUtc().isAfter(expiresAt);
  }

  /// Check if the timer is currently running
  bool get isRunning {
    return status == UnitTimerStatus.active && !isExpired;
  }

  /// Get remaining time in seconds (0 if expired or not active)
  int get remainingSeconds {
    if (status != UnitTimerStatus.active) return 0;

    final now = DateTime.now().toUtc();
    if (now.isAfter(expiresAt)) return 0;

    return expiresAt.difference(now).inSeconds;
  }

  /// Get elapsed time in seconds
  int get elapsedSeconds {
    final now = DateTime.now().toUtc();
    return now.difference(startedAt).inSeconds;
  }

  /// Get remaining time as a formatted string (e.g., "5:30", "1:15:45")
  String get remainingFormatted {
    final seconds = remainingSeconds;
    if (seconds <= 0) return '0:00';

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }

    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [
        id,
        unitId,
        stepTimerId,
        startedAt,
        expiresAt,
        completedAt,
        status,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'UnitTimer(id: $id, unitId: $unitId, status: $status, remaining: $remainingFormatted)';
  }
}
