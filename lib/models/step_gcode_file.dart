import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/gcode_file.dart';

/// StepGCodeFile model representing the junction table between production steps and gCode files
class StepGCodeFile extends Equatable {
  final String id; // UUID
  final String stepId; // Foreign key to ProductionStep
  final String gcodeFileId; // Foreign key to GCodeFile
  final int executionOrder; // Order in which to execute (1, 2, 3, etc.)
  final DateTime createdAt;

  /// Optional: The actual GCodeFile object (populated via join)
  final GCodeFile? gcodeFile;

  const StepGCodeFile({
    required this.id,
    required this.stepId,
    required this.gcodeFileId,
    required this.executionOrder,
    required this.createdAt,
    this.gcodeFile,
  });

  /// Validate that the step gCode file is valid
  bool isValid() {
    if (stepId.isEmpty) return false;
    if (gcodeFileId.isEmpty) return false;
    if (executionOrder <= 0) return false;
    return true;
  }

  /// Create StepGCodeFile from JSON
  factory StepGCodeFile.fromJson(Map<String, dynamic> json) {
    return StepGCodeFile(
      id: json['id'] as String,
      stepId: json['step_id'] as String,
      gcodeFileId: json['gcode_file_id'] as String,
      executionOrder: json['execution_order'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      gcodeFile: json['gcode_files'] != null
          ? GCodeFile.fromJson(json['gcode_files'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Convert StepGCodeFile to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'step_id': stepId,
      'gcode_file_id': gcodeFileId,
      'execution_order': executionOrder,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Create a copy of StepGCodeFile with updated fields
  StepGCodeFile copyWith({
    String? id,
    String? stepId,
    String? gcodeFileId,
    int? executionOrder,
    DateTime? createdAt,
    GCodeFile? gcodeFile,
  }) {
    return StepGCodeFile(
      id: id ?? this.id,
      stepId: stepId ?? this.stepId,
      gcodeFileId: gcodeFileId ?? this.gcodeFileId,
      executionOrder: executionOrder ?? this.executionOrder,
      createdAt: createdAt ?? this.createdAt,
      gcodeFile: gcodeFile ?? this.gcodeFile,
    );
  }

  @override
  List<Object?> get props => [
        id,
        stepId,
        gcodeFileId,
        executionOrder,
        createdAt,
        gcodeFile,
      ];

  @override
  String toString() {
    return 'StepGCodeFile(id: $id, stepId: $stepId, executionOrder: $executionOrder)';
  }
}
