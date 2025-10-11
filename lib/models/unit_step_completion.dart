import 'package:equatable/equatable.dart';

/// Represents a completed production step for a unit
class UnitStepCompletion extends Equatable {
  final String id;
  final String unitId;
  final String stepId;
  final DateTime completedAt;
  final String completedBy;
  final String? notes;

  const UnitStepCompletion({
    required this.id,
    required this.unitId,
    required this.stepId,
    required this.completedAt,
    required this.completedBy,
    this.notes,
  });

  /// Create from JSON
  factory UnitStepCompletion.fromJson(Map<String, dynamic> json) {
    return UnitStepCompletion(
      id: json['id'] as String,
      unitId: json['unit_id'] as String,
      stepId: json['step_id'] as String,
      completedAt: DateTime.parse(json['completed_at'] as String),
      completedBy: json['completed_by'] as String,
      notes: json['notes'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'unit_id': unitId,
      'step_id': stepId,
      'completed_at': completedAt.toIso8601String(),
      'completed_by': completedBy,
      'notes': notes,
    };
  }

  /// Copy with method for immutability
  UnitStepCompletion copyWith({
    String? id,
    String? unitId,
    String? stepId,
    DateTime? completedAt,
    String? completedBy,
    String? notes,
  }) {
    return UnitStepCompletion(
      id: id ?? this.id,
      unitId: unitId ?? this.unitId,
      stepId: stepId ?? this.stepId,
      completedAt: completedAt ?? this.completedAt,
      completedBy: completedBy ?? this.completedBy,
      notes: notes ?? this.notes,
    );
  }

  @override
  List<Object?> get props => [
        id,
        unitId,
        stepId,
        completedAt,
        completedBy,
        notes,
      ];
}
