import 'package:equatable/equatable.dart';

/// StepLabel model representing a label to print for a production step
///
/// Each production step can have multiple labels (e.g., "LEFT SIDE", "RIGHT SIDE")
/// which will be printed when the step is completed.
class StepLabel extends Equatable {
  final String id; // UUID
  final String stepId; // Foreign key to ProductionStep
  final String labelText; // Text to print on label (e.g., "LEFT SIDE")
  final int labelOrder; // Order in which to print labels
  final DateTime createdAt;
  final DateTime updatedAt;

  const StepLabel({
    required this.id,
    required this.stepId,
    required this.labelText,
    required this.labelOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create StepLabel from JSON
  factory StepLabel.fromJson(Map<String, dynamic> json) {
    return StepLabel(
      id: json['id'] as String,
      stepId: json['step_id'] as String,
      labelText: json['label_text'] as String,
      labelOrder: json['label_order'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert StepLabel to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'step_id': stepId,
      'label_text': labelText,
      'label_order': labelOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of StepLabel with updated fields
  StepLabel copyWith({
    String? id,
    String? stepId,
    String? labelText,
    int? labelOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StepLabel(
      id: id ?? this.id,
      stepId: stepId ?? this.stepId,
      labelText: labelText ?? this.labelText,
      labelOrder: labelOrder ?? this.labelOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        stepId,
        labelText,
        labelOrder,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() {
    return 'StepLabel(id: $id, stepId: $stepId, labelText: $labelText, order: $labelOrder)';
  }
}
