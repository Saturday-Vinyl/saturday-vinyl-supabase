import 'package:equatable/equatable.dart';

/// StepTimer model representing a configurable timer for a production step
///
/// Each production step can have multiple timers (e.g., "Cure Time - 15 min", "Cool Down - 30 min")
/// which can be started when the step is completed.
class StepTimer extends Equatable {
  final String id; // UUID
  final String stepId; // Foreign key to ProductionStep
  final String timerName; // Descriptive name (e.g., "Cure Time")
  final int durationMinutes; // Timer duration in minutes
  final int timerOrder; // Order in which to display timers
  final DateTime createdAt;
  final DateTime updatedAt;

  const StepTimer({
    required this.id,
    required this.stepId,
    required this.timerName,
    required this.durationMinutes,
    required this.timerOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create StepTimer from JSON
  factory StepTimer.fromJson(Map<String, dynamic> json) {
    return StepTimer(
      id: json['id'] as String,
      stepId: json['step_id'] as String,
      timerName: json['timer_name'] as String,
      durationMinutes: json['duration_minutes'] as int,
      timerOrder: json['timer_order'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert StepTimer to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'step_id': stepId,
      'timer_name': timerName,
      'duration_minutes': durationMinutes,
      'timer_order': timerOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of StepTimer with updated fields
  StepTimer copyWith({
    String? id,
    String? stepId,
    String? timerName,
    int? durationMinutes,
    int? timerOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StepTimer(
      id: id ?? this.id,
      stepId: stepId ?? this.stepId,
      timerName: timerName ?? this.timerName,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      timerOrder: timerOrder ?? this.timerOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Get duration as a formatted string (e.g., "15 min", "1 hr 30 min")
  String get durationFormatted {
    if (durationMinutes < 60) {
      return '$durationMinutes min';
    }

    final hours = durationMinutes ~/ 60;
    final minutes = durationMinutes % 60;

    if (minutes == 0) {
      return '$hours hr';
    }

    return '$hours hr $minutes min';
  }

  @override
  List<Object?> get props => [
        id,
        stepId,
        timerName,
        durationMinutes,
        timerOrder,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'StepTimer(id: $id, stepId: $stepId, name: $timerName, duration: $durationMinutes min, order: $timerOrder)';
  }
}
