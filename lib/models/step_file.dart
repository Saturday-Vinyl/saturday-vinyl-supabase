import 'package:equatable/equatable.dart';
import 'package:saturday_app/models/app_file.dart';

/// StepFile model representing the junction between production steps and files
class StepFile extends Equatable {
  final String id; // UUID
  final String stepId; // Foreign key to production_steps
  final String fileId; // Foreign key to files
  final int executionOrder; // Order for sequencing (1-based)
  final DateTime createdAt;

  // Optional: loaded AppFile object for convenience
  final AppFile? file;

  const StepFile({
    required this.id,
    required this.stepId,
    required this.fileId,
    required this.executionOrder,
    required this.createdAt,
    this.file,
  });

  /// Validate that execution order is positive
  bool isValid() {
    return executionOrder > 0 && stepId.isNotEmpty && fileId.isNotEmpty;
  }

  /// Create StepFile from JSON
  factory StepFile.fromJson(Map<String, dynamic> json) {
    return StepFile(
      id: json['id'] as String,
      stepId: json['step_id'] as String,
      fileId: json['file_id'] as String,
      executionOrder: json['execution_order'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      // If the JSON includes nested file data, parse it
      file: json['files'] != null ? AppFile.fromJson(json['files']) : null,
    );
  }

  /// Convert StepFile to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'step_id': stepId,
      'file_id': fileId,
      'execution_order': executionOrder,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Create a copy of StepFile with updated fields
  StepFile copyWith({
    String? id,
    String? stepId,
    String? fileId,
    int? executionOrder,
    DateTime? createdAt,
    AppFile? file,
  }) {
    return StepFile(
      id: id ?? this.id,
      stepId: stepId ?? this.stepId,
      fileId: fileId ?? this.fileId,
      executionOrder: executionOrder ?? this.executionOrder,
      createdAt: createdAt ?? this.createdAt,
      file: file ?? this.file,
    );
  }

  @override
  List<Object?> get props => [
        id,
        stepId,
        fileId,
        executionOrder,
        createdAt,
        file,
      ];

  @override
  String toString() {
    return 'StepFile(id: $id, stepId: $stepId, fileId: $fileId, order: $executionOrder)';
  }
}
